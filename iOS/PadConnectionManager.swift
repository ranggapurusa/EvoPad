import Combine
import Foundation
import Network
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Owns Bonjour discovery, TLS 1.3 pinned transport, and mutual authentication
/// between iPad and Mac Helper.
final class PadConnectionManager: ObservableObject {
    @Published private(set) var statusText = "Mencari Mac..."
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var macFeedback = "Menunggu respons Mac"
    @Published private(set) var isPairedWithMac = false
    @Published private(set) var currentPairedMacName: String?

    // Evo Island Notification & Now Playing HUD state
    @Published var activeNotification: EvoIslandNotification?
    @Published var nowPlaying: EvoNowPlayingState?
    private var notificationWorkItem: DispatchWorkItem?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lastEndpoint: NWEndpoint?
    private let networkQueue = DispatchQueue(label: "id.evonex.evopad.ios-network", qos: .userInteractive)

    private var outstandingSends = 0
    private let clientDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let clientDeviceName = UIDevice.current.name

    // High-frequency pointer move accumulator to prevent network queue backpressure & jitter
    private var pendingMoveDx: Double = 0
    private var pendingMoveDy: Double = 0
    private var isMoveScheduled = false
    private let moveLock = NSLock()

    // Pairing & Handshake Session State — owned exclusively by `networkQueue`
    private var activeQRData: PadPairingQRData?
    private var clientNonce: Data?
    private var serverNonce: Data?
    private var currentPairingId: String?
    private var authMode: String = "reconnect" // "pairing" or "reconnect"
    private var reconnectAttemptCount: Int = 0
    private static let reconnectBackoffSchedule: [TimeInterval] = [0.4, 1.0, 2.0, 5.0]

    /// Computes adaptive reconnect delay in seconds for the given 0-based attempt index.
    static func reconnectDelay(forAttempt attempt: Int) -> TimeInterval {
        let clampedIndex = max(0, min(reconnectBackoffSchedule.count - 1, attempt))
        return reconnectBackoffSchedule[clampedIndex]
    }

    /// Derives a Bonjour `.local` hostname from a Mac server name when Bonjour endpoint discovery hasn't resolved yet.
    static func fallbackHostName(fromServerName serverName: String) -> String {
        let trimmed = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Mac.local" }
        if trimmed.lowercased().hasSuffix(".local") {
            return trimmed
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        return normalized.isEmpty ? "Mac.local" : "\(normalized).local"
    }

    init() {
        checkPairedStatus()
    }

    func checkPairedStatus() {
        let paired = PadKeychainStore.shared.loadPairedDevices()
        let updateUI = {
            if let first = paired.first {
                self.isPairedWithMac = true
                self.currentPairedMacName = first.name
            } else {
                self.isPairedWithMac = false
                self.currentPairedMacName = nil
            }
        }
        if Thread.isMainThread {
            updateUI()
        } else {
            DispatchQueue.main.async(execute: updateUI)
        }
    }

    func startDiscovery() {
        networkQueue.async { [weak self] in
            guard let self else { return }
            self.startDiscoveryOnNetworkQueue()
        }
    }

    func stopDiscovery() {
        networkQueue.async { [weak self] in
            guard let self else { return }
            self.stopDiscoveryOnNetworkQueue()
        }
    }

    private func startDiscoveryOnNetworkQueue() {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: PadProtocol.serviceType, domain: nil)
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] (state: NWBrowser.State) in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))
            if case .failed(let error) = state {
                DispatchQueue.main.async {
                    self.statusText = "Pencarian gagal: \(error.localizedDescription)"
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in
            guard let self, let first = results.first else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))
            self.lastEndpoint = first.endpoint
            guard self.connection == nil else { return }

            if let qr = self.activeQRData, !qr.isExpired {
                DispatchQueue.main.async {
                    self.statusText = "Mac ditemukan, menghubungkan untuk pairing via TLS..."
                }
                self.connectWithTLSOnNetworkQueue(to: first.endpoint, pinnedFingerprintHex: qr.certFingerprintHex, mode: "pairing")
                return
            }

            let paired = PadKeychainStore.shared.loadPairedDevices()
            if let saved = paired.first, let fingerprint = saved.certFingerprintHex {
                DispatchQueue.main.async {
                    self.statusText = "Mac ditemukan, menghubungkan kembali via TLS..."
                }
                self.connectWithTLSOnNetworkQueue(to: first.endpoint, pinnedFingerprintHex: fingerprint, mode: "reconnect")
            } else {
                DispatchQueue.main.async {
                    self.statusText = "Mac ditemukan. Pindai kode QR untuk pairing."
                }
            }
        }

        self.browser = newBrowser
        newBrowser.start(queue: self.networkQueue)
        DispatchQueue.main.async {
            self.statusText = "Mencari Mac di jaringan lokal..."
        }
    }

    private func stopDiscoveryOnNetworkQueue() {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        browser?.cancel()
        browser = nil
    }

    // MARK: - QR Pairing Initiation (M2.3)

    func pairWithQR(qrData: PadPairingQRData) {
        if qrData.isExpired {
            DispatchQueue.main.async {
                self.statusText = "Kode QR sudah kedaluwarsa. Buat kode baru di Mac."
            }
            return
        }

        DispatchQueue.main.async {
            self.statusText = "Menghubungi Mac via TLS 1.3 (Verifikasi Pinning)..."
        }

        networkQueue.async { [weak self] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))

            self.activeQRData = qrData
            self.authMode = "pairing"
            self.reconnectAttemptCount = 0

            if let endpoint = self.lastEndpoint {
                self.connectWithTLSOnNetworkQueue(to: endpoint, pinnedFingerprintHex: qrData.certFingerprintHex, mode: "pairing")
            } else {
                // Fallback: derive `.local` host from QR `serverName` and connect using `servicePort`
                let hostName = Self.fallbackHostName(fromServerName: qrData.serverName)
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(hostName),
                    port: NWEndpoint.Port(rawValue: qrData.servicePort) ?? 49321
                )
                self.connectWithTLSOnNetworkQueue(to: endpoint, pinnedFingerprintHex: qrData.certFingerprintHex, mode: "pairing")
            }
        }
    }

    func unpairCurrentMac() {
        try? PadKeychainStore.shared.removeAllDevices()
        checkPairedStatus()

        networkQueue.async { [weak self] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))
            self.clearHandshakeStateOnNetworkQueue()
            self.connection?.cancel()
            self.connection = nil

            DispatchQueue.main.async {
                self.isConnected = false
                self.isAuthenticated = false
                self.statusText = "Pairing dicabut. Pindai QR untuk pairing baru."
            }
        }
    }

    private func clearHandshakeStateOnNetworkQueue() {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        clientNonce = nil
        serverNonce = nil
        currentPairingId = nil
        activeQRData = nil
    }

    // MARK: - TLS Connection & Pinned Verification (M2.2)

    private func connectWithTLSOnNetworkQueue(to endpoint: NWEndpoint, pinnedFingerprintHex: String, mode: String) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        lastEndpoint = endpoint
        connection?.cancel()
        clientNonce = nil
        serverNonce = nil
        currentPairingId = nil
        self.authMode = mode

        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.isConnected = false
        }

        let parameters = PadProtocol.tlsClientParameters(
            pinnedFingerprintHex: pinnedFingerprintHex,
            verifyQueue: networkQueue
        )

        let newConnection = NWConnection(to: endpoint, using: parameters)
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let activeConn = newConnection else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))
            guard self.connection === activeConn else { return }

            switch state {
            case .ready:
                PadLog.network("iPad: TLS 1.3 handshake successful, certificate pinned")
                DispatchQueue.main.async {
                    self.statusText = "TLS 1.3 Terhubung — Mengautentikasi..."
                }
                self.startHandshakeAuth(over: activeConn)
                self.receiveLoop(on: activeConn)

            case .failed(let error):
                self.clearHandshakeStateOnNetworkQueue()
                activeConn.cancel()
                self.connection = nil
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isAuthenticated = false
                    self.statusText = "Koneksi TLS gagal: \(error.localizedDescription)"
                }
                self.retryConnectionOnNetworkQueue()

            case .cancelled:
                self.clearHandshakeStateOnNetworkQueue()
                self.connection = nil
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isAuthenticated = false
                }
                self.startDiscoveryOnNetworkQueue()

            default:
                break
            }
        }

        newConnection.start(queue: networkQueue)
    }

    // MARK: - Handshake & Authentication (M2.3 & M2.4)

    private func startHandshakeAuth(over connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        let nonce = PadCryptoUtils.randomBytes(count: 32)
        self.clientNonce = nonce
        self.serverNonce = nil
        self.currentPairingId = nil
        let nonceHex = nonce.map { String(format: "%02x", $0) }.joined()

        let hello = PadEnvelopeV2(
            requestId: UUID().uuidString,
            type: .hello,
            payload: PadPayloadV2(
                clientDeviceId: clientDeviceId,
                deviceName: clientDeviceName,
                nonce: nonceHex,
                authMode: authMode
            )
        )
        sendEnvelopeDirect(hello, over: connection)
        PadLog.network("iPad: sent hello mode=\(authMode)")
    }

    // MARK: - Command Transmission (Guarded by Authentication)

    func send(_ command: PadCommand) {
        guard isAuthenticated else { return }

        // Coalesce high-frequency pointer motion if network queue is busy
        if command.type == .move, let dx = command.dx, let dy = command.dy {
            moveLock.lock()
            pendingMoveDx += dx
            pendingMoveDy += dy
            if !isMoveScheduled {
                isMoveScheduled = true
                moveLock.unlock()

                networkQueue.async { [weak self] in
                    guard let self, let connection = self.connection else { return }
                    self.moveLock.lock()
                    let sendDx = self.pendingMoveDx
                    let sendDy = self.pendingMoveDy
                    self.pendingMoveDx = 0
                    self.pendingMoveDy = 0
                    self.isMoveScheduled = false
                    self.moveLock.unlock()

                    guard sendDx != 0 || sendDy != 0 else { return }
                    let coalescedCommand = PadCommand(type: .move, dx: sendDx, dy: sendDy)
                    guard let data = PadFrameCodec.encodeV1Command(coalescedCommand) else { return }

                    self.outstandingSends += 1
                    connection.send(
                        content: data,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { [weak self] _ in
                            self?.networkQueue.async {
                                self?.outstandingSends -= 1
                            }
                        }
                    )
                }
            } else {
                moveLock.unlock()
            }
            return
        }

        // For non-move commands (click, drag, gesture), flush any pending movement first
        moveLock.lock()
        let flushDx = pendingMoveDx
        let flushDy = pendingMoveDy
        pendingMoveDx = 0
        pendingMoveDy = 0
        isMoveScheduled = false
        moveLock.unlock()

        networkQueue.async { [weak self] in
            guard let self, let connection = self.connection else { return }

            if flushDx != 0 || flushDy != 0 {
                let flushCommand = PadCommand(type: .move, dx: flushDx, dy: flushDy)
                if let flushData = PadFrameCodec.encodeV1Command(flushCommand) {
                    self.outstandingSends += 1
                    connection.send(
                        content: flushData,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { [weak self] _ in
                            self?.networkQueue.async {
                                self?.outstandingSends -= 1
                            }
                        }
                    )
                }
            }

            guard let data = PadFrameCodec.encodeV1Command(command) else { return }

            if command.type == .gesture, let direction = command.gestureDirection {
                PadLog.network("iPad: sending gesture command over TLS, direction=\(direction.rawValue)")
            }

            self.outstandingSends += 1
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: false,
                completion: .contentProcessed { [weak self] error in
                    self?.networkQueue.async {
                        self?.outstandingSends -= 1
                    }
                    if let error, command.type == .gesture {
                        PadLog.network("iPad: gesture send failed: \(error.localizedDescription)")
                    }
                }
            )
        }
    }

    func sendV2(_ envelope: PadEnvelopeV2) {
        guard isAuthenticated else { return }

        networkQueue.async { [weak self] in
            guard let self, let connection = self.connection else { return }
            guard let data = PadFrameCodec.encodeV2Envelope(envelope) else {
                return
            }

            self.outstandingSends += 1
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: false,
                completion: .contentProcessed { [weak self] error in
                    self?.networkQueue.async {
                        self?.outstandingSends -= 1
                    }
                    if let error {
                        PadLog.network("iPad: V2 send failed: \(error.localizedDescription)")
                    }
                }
            )
        }
    }

    // MARK: - Evo Island Notifications & Actions

    func postIslandNotification(
        title: String,
        symbol: String,
        detail: String? = nil,
        tint: Color = EvoTheme.accent,
        duration: TimeInterval = 2.2
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notificationWorkItem?.cancel()
            let notif = EvoIslandNotification(title: title, symbol: symbol, detail: detail, tint: tint)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                self.activeNotification = notif
            }
            let workItem = DispatchWorkItem { [weak self] in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    if self?.activeNotification?.id == notif.id {
                        self?.activeNotification = nil
                    }
                }
            }
            self.notificationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    func sendShortcut(_ shortcut: PadStandardShortcut) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.shortcut(shortcut)
        sendV2(envelope)
        postIslandNotification(
            title: shortcut.title,
            symbol: shortcut.symbol,
            detail: shortcut.chordDescription,
            tint: EvoTheme.accent
        )
        DispatchQueue.main.async {
            self.macFeedback = "Shortcut \(shortcut.title) (\(shortcut.chordDescription)) dikirim..."
        }
    }

    func sendCustomShortcut(keyCode: UInt16, modifiers: [PadModifierFlagV2]) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.customShortcut(keyCode: keyCode, modifiers: modifiers)
        sendV2(envelope)
        postIslandNotification(
            title: "Shortcut",
            symbol: "command",
            detail: "Key \(keyCode)",
            tint: EvoTheme.accent
        )
        DispatchQueue.main.async {
            self.macFeedback = "Custom chord (key: \(keyCode)) dikirim..."
        }
    }

    func sendKeyEvent(keyCode: UInt16, phase: PadKeyPhaseV2, modifiers: [PadModifierFlagV2]? = nil) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.keyEvent(keyCode: keyCode, phase: phase, modifiers: modifiers)
        sendV2(envelope)
    }

    func sendMacro(macroId: String, steps: [PadMacroStepV2]) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.macro(macroId: macroId, steps: steps)
        sendV2(envelope)
        postIslandNotification(
            title: "Macro Running",
            symbol: "bolt.fill",
            detail: macroId,
            tint: Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
        )
        DispatchQueue.main.async {
            self.macFeedback = "Macro '\(macroId)' dikirim..."
        }
    }

    func sendMediaKey(_ key: PadMediaControlKey) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.media(key: key)
        sendV2(envelope)

        let tint: Color
        let detail: String?
        switch key {
        case .playPause:
            let isNowPlaying = !(nowPlaying?.isPlaying ?? false)
            nowPlaying = EvoNowPlayingState(
                isPlaying: isNowPlaying,
                title: nowPlaying?.title ?? "Media Player",
                artist: nowPlaying?.artist ?? "macOS"
            )
            tint = isNowPlaying ? Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) : EvoTheme.textSecondary
            detail = isNowPlaying ? "Playing" : "Paused"

        case .volumeUp:
            tint = EvoTheme.accent
            detail = "+6%"

        case .volumeDown:
            tint = EvoTheme.accent
            detail = "-6%"

        case .mute:
            tint = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
            detail = "Mute"

        case .nextTrack, .previousTrack:
            tint = EvoTheme.accent
            detail = nil
        }

        postIslandNotification(
            title: key.title,
            symbol: key.symbol,
            detail: detail,
            tint: tint
        )

        DispatchQueue.main.async {
            self.macFeedback = "Media: \(key.title) dikirim..."
        }
    }

    func sendSystemAction(_ action: PadSystemControlAction, targetApp: String? = nil) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.system(action: action, targetApp: targetApp)
        sendV2(envelope)
        postIslandNotification(
            title: action.title,
            symbol: action.symbol,
            detail: targetApp,
            tint: Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        )
        DispatchQueue.main.async {
            self.macFeedback = "System: \(action.title) dikirim..."
        }
    }

    func sendTextInput(_ text: String) {
        guard isAuthenticated else { return }
        let envelope = PadEnvelopeV2.textInput(text)
        sendV2(envelope)
        postIslandNotification(
            title: "Formula / Text",
            symbol: "function",
            detail: text.count > 14 ? "\(text.prefix(14))..." : text,
            tint: EvoTheme.accent
        )
    }

    private func sendEnvelopeDirect(_ envelope: PadEnvelopeV2, over connection: NWConnection) {
        guard let data = PadFrameCodec.encodeV2Envelope(envelope) else { return }
        connection.send(
            content: data,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { error in
                if let error {
                    PadLog.network("iPad: send envelope error: \(error.localizedDescription)")
                }
            }
        )
    }

    // MARK: - Receive Loop & Handshake Processing

    private func receiveLoop(on activeConnection: NWConnection, pending: Data = Data()) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        activeConnection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak activeConnection] data, _, isComplete, error in
            guard let self, let activeConnection else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))
            guard self.connection === activeConnection else { return }

            var buffer = pending
            if let data {
                buffer.append(data)
            }

            loop: while true {
                switch PadFrameCodec.popNextFrame(from: &buffer) {
                case .needMoreData:
                    break loop

                case .frameTooLarge:
                    PadLog.network("iPad: frame rejected >16KB")
                    self.clearHandshakeStateOnNetworkQueue()
                    activeConnection.cancel()
                    return

                case .line(let line):
                    if line.isEmpty { continue }
                    self.processIncomingLine(line, connection: activeConnection)
                }
            }

            if error != nil || isComplete {
                self.clearHandshakeStateOnNetworkQueue()
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isAuthenticated = false
                }
                activeConnection.cancel()
                self.startDiscoveryOnNetworkQueue()
                return
            }

            self.receiveLoop(on: activeConnection, pending: buffer)
        }
    }

    private func processIncomingLine(_ line: Data, connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        switch PadFrameCodec.decodeServerFrame(line) {
        case .success(.v1Ack(let ack)):
            guard ack.kind == "gestureAck" else { return }
            DispatchQueue.main.async {
                self.macFeedback = ack.message
            }

        case .success(.v2Envelope(let envelope)):
            handleServerEnvelope(envelope, connection: connection)

        case .failure(let err):
            PadLog.network("iPad: failed to decode server response: \(err)")
        }
    }

    private func handleServerEnvelope(_ envelope: PadEnvelopeV2, connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        switch envelope.type {
        case .challenge:
            handleChallenge(envelope, connection: connection)

        case .authResult:
            handleAuthResult(envelope, connection: connection)

        case .pairingComplete:
            handlePairingComplete(envelope)

        case .actionAck:
            if let msg = envelope.acknowledgement?.message {
                DispatchQueue.main.async { self.macFeedback = msg }
            }

        case .error:
            if let err = envelope.error {
                PadLog.network("iPad: received error from Mac: \(err.code.rawValue) - \(err.message)")
                DispatchQueue.main.async {
                    self.statusText = "Error Mac [\(err.code.rawValue)]: \(err.message)"
                }
                if err.code == .unauthenticated || err.code == .authFailed {
                    self.clearHandshakeStateOnNetworkQueue()
                    connection.cancel()
                }
            }

        default:
            break
        }
    }

    private func handleChallenge(_ envelope: PadEnvelopeV2, connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        guard let payload = envelope.payload,
              let serverNonceHex = payload.nonce,
              let serverNonce = Data(hexString: serverNonceHex),
              let serverDevId = payload.serverDeviceId,
              let clientNonce = self.clientNonce,
              let pairingId = payload.pairingId else {
            return
        }

        self.currentPairingId = pairingId
        self.serverNonce = serverNonce

        if authMode == "pairing", let qr = self.activeQRData {
            guard let secretData = Data(hexString: qr.oneTimeSecretHex),
                  let certFingerprintData = Data(hexString: qr.certFingerprintHex) else {
                return
            }

            let transcript = PadCanonicalTranscript(
                domain: PadSecurityConstants.domainPairingClientProof,
                protocolVersion: PadSecurityConstants.protocolVersion,
                pairingId: pairingId,
                clientDeviceId: clientDeviceId,
                serverDeviceId: serverDevId,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                certFingerprint: certFingerprintData,
                sessionContext: "pairing",
                role: "client"
            )
            let proof = transcript.computeHMAC(keyData: secretData)

            let authEnvelope = PadEnvelopeV2(
                requestId: pairingId,
                type: .auth,
                payload: PadPayloadV2(hmac: proof)
            )
            sendEnvelopeDirect(authEnvelope, over: connection)
            DispatchQueue.main.async {
                self.statusText = "Menunggu persetujuan pairing di Mac..."
            }

        } else if authMode == "reconnect" {
            let paired = PadKeychainStore.shared.loadPairedDevices()
            let matchedDevice = paired.first(where: { $0.deviceId == serverDevId })
                ?? (paired.count == 1 ? paired.first : nil)

            guard let saved = matchedDevice,
                  let tokenData = Data(hexString: saved.pairingTokenHex),
                  let certFingerprintData = Data(hexString: saved.certFingerprintHex ?? "") else {
                PadLog.network("iPad: reconnect rejected, Mac serverDeviceId=\(serverDevId) not recognized in Keychain")
                DispatchQueue.main.async {
                    self.statusText = "Mac tidak dikenali atau belum dipairing. Silakan pindai ulang QR Code."
                }
                return
            }

            // Sync serverDeviceId if it changed across Mac restarts
            if saved.deviceId != serverDevId {
                PadLog.network("iPad: updating saved Mac deviceId from \(saved.deviceId) to \(serverDevId)")
                let updated = PadPairedDevice(
                    deviceId: serverDevId,
                    name: saved.name,
                    pairingTokenHex: saved.pairingTokenHex,
                    certFingerprintHex: saved.certFingerprintHex,
                    pairedDate: saved.pairedDate,
                    lastAuthenticatedDate: Date()
                )
                try? PadKeychainStore.shared.removeDevice(deviceId: saved.deviceId)
                try? PadKeychainStore.shared.saveDevice(updated)
            }

            let transcript = PadCanonicalTranscript(
                domain: PadSecurityConstants.domainReconnectClientProof,
                protocolVersion: PadSecurityConstants.protocolVersion,
                pairingId: pairingId,
                clientDeviceId: clientDeviceId,
                serverDeviceId: serverDevId,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                certFingerprint: certFingerprintData,
                sessionContext: "reconnect",
                role: "client"
            )
            let proof = transcript.computeHMAC(keyData: tokenData)

            let authEnvelope = PadEnvelopeV2(
                requestId: pairingId,
                type: .auth,
                payload: PadPayloadV2(hmac: proof)
            )
            sendEnvelopeDirect(authEnvelope, over: connection)
        }
    }

    private func handleAuthResult(_ envelope: PadEnvelopeV2, connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        guard let payload = envelope.payload else { return }

        if authMode == "pairing" {
            guard payload.status == "approved",
                  let tokenHex = payload.pairingToken,
                  let tokenData = Data(hexString: tokenHex),
                  let qr = self.activeQRData,
                  let pairingId = self.currentPairingId,
                  let clientNonce = self.clientNonce else {
                return
            }

            // Persist token and pinned cert in Keychain
            let newDevice = PadPairedDevice(
                deviceId: qr.serverDeviceId,
                name: qr.serverName,
                pairingTokenHex: tokenHex,
                certFingerprintHex: qr.certFingerprintHex,
                pairedDate: Date(),
                lastAuthenticatedDate: Date()
            )
            try? PadKeychainStore.shared.saveDevice(newDevice)
            self.checkPairedStatus()

            // Send pairingCommit authenticated by newly received pairingToken
            let certFingerprintData = Data(hexString: qr.certFingerprintHex) ?? Data()
            let commitTranscript = PadCanonicalTranscript(
                domain: PadSecurityConstants.domainPairingCommit,
                protocolVersion: PadSecurityConstants.protocolVersion,
                pairingId: pairingId,
                clientDeviceId: clientDeviceId,
                serverDeviceId: qr.serverDeviceId,
                clientNonce: clientNonce,
                serverNonce: self.serverNonce ?? Data(),
                certFingerprint: certFingerprintData,
                sessionContext: "pairing-commit",
                role: "client"
            )
            let commitProof = commitTranscript.computeHMAC(keyData: tokenData)

            let commitEnvelope = PadEnvelopeV2(
                requestId: pairingId,
                type: .pairingCommit,
                payload: PadPayloadV2(
                    pairingId: pairingId,
                    hmac: commitProof
                )
            )
            sendEnvelopeDirect(commitEnvelope, over: connection)
            PadLog.network("iPad: sent pairingCommit authenticated with new token")

        } else if authMode == "reconnect" {
            guard payload.status == "authenticated" else {
                clearHandshakeStateOnNetworkQueue()
                connection.cancel()
                return
            }

            clearHandshakeStateOnNetworkQueue()
            stopDiscoveryOnNetworkQueue()
            reconnectAttemptCount = 0
            DispatchQueue.main.async {
                self.isConnected = true
                self.isAuthenticated = true
                self.statusText = "Terhubung ke Mac (TLS 1.3 Terautentikasi)"
            }
            PadLog.network("iPad: reconnect authentication complete and active")
        }
    }

    private func handlePairingComplete(_ envelope: PadEnvelopeV2) {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        clearHandshakeStateOnNetworkQueue()
        stopDiscoveryOnNetworkQueue()
        reconnectAttemptCount = 0
        self.checkPairedStatus()
        DispatchQueue.main.async {
            self.isConnected = true
            self.isAuthenticated = true
            self.statusText = "Terhubung ke Mac (Pairing Selesai)"
        }
        PadLog.network("iPad: pairing complete and connection active")
    }

    private func retryConnectionOnNetworkQueue() {
        dispatchPrecondition(condition: .onQueue(networkQueue))
        guard let endpoint = lastEndpoint else { return }

        let delay = Self.reconnectDelay(forAttempt: reconnectAttemptCount)
        reconnectAttemptCount += 1

        networkQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.networkQueue))
            guard self.connection == nil else { return }
            let paired = PadKeychainStore.shared.loadPairedDevices()
            if let saved = paired.first, let fingerprint = saved.certFingerprintHex {
                DispatchQueue.main.async {
                    self.statusText = "Mencoba menghubungkan kembali..."
                }
                self.connectWithTLSOnNetworkQueue(to: endpoint, pinnedFingerprintHex: fingerprint, mode: "reconnect")
            }
        }
    }
}
