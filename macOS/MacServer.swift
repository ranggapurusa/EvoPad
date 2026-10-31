import Combine
import Foundation
import Network
import Security
import CoreGraphics
import AppKit

final class MacServer: ObservableObject {
    @Published private(set) var statusText = "Menyiapkan layanan..."
    @Published private(set) var connectedDevice = "Belum ada iPad"
    @Published private(set) var isListening = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var lastInputText = "Belum ada input diterima"
    @Published private(set) var pointerInputHz = 0

    // M2 Security & Pairing States
    @Published private(set) var serverDeviceId = UUID().uuidString
    @Published private(set) var certFingerprintHex = ""
    @Published private(set) var currentQRData: PadPairingQRData?
    @Published private(set) var qrImage: NSImage?
    @Published private(set) var pairedDevices: [PadPairedDevice] = []
    @Published var pendingPairingRequest: PendingPairingApproval?

    struct PendingPairingApproval: Identifiable {
        let id: String // pairingId
        let clientDeviceId: String
        let clientName: String
        let connectionId: String
    }

    private var pointerFrameCount = 0
    private var pointerRateWindowStart = DispatchTime.now().uptimeNanoseconds
    private let receivedRate = PadRateCounter(label: "Mac pointer received")
    private var listener: NWListener?

    // Connection Isolation: pending vs active
    private var activeConnection: NWConnection?
    private var activeSession: AuthenticatedSession?
    private var pendingConnections: [String: PendingConnection] = [:]

    private let inputQueue = DispatchQueue(label: "id.evonex.evopad.mac-input", qos: .userInteractive)
    private let securityQueue = DispatchQueue(label: "id.evonex.evopad.mac-security", qos: .default)
    private let eventController = InputEventController()
    private var serverIdentity: PadServerIdentity?

    // Active one-time pairing QR secret
    private var activeQRSecretHex: String?
    private var activeQRExpiry: TimeInterval = 0

    private struct AuthenticatedSession {
        let clientDeviceId: String
        let clientName: String
        let authenticatedAt: Date
        let connection: NWConnection

        var isExpired: Bool {
            Date().timeIntervalSince(authenticatedAt) > PadSecurityConstants.sessionMaxLifetimeSeconds
        }
    }

    private final class PendingConnection {
        let id: String
        let connection: NWConnection
        let createdAt: Date
        var timeoutWorkItem: DispatchWorkItem?

        var clientDeviceId: String?
        var clientName: String?
        var clientNonce: Data?
        var serverNonce: Data?
        var pairingId: String?
        var authMode: String?
        var pendingTokenHex: String?

        init(id: String, connection: NWConnection) {
            self.id = id
            self.connection = connection
            self.createdAt = Date()
        }
    }

    func start() {
        guard listener == nil else { return }
        refreshPermission()
        loadPairedDevicesList()

        // 1. Initialize Server Identity & Keychain (M2.1)
        do {
            let identity = try PadServerIdentity.loadOrCreate()
            self.serverIdentity = identity
            self.certFingerprintHex = identity.fingerprintHex
            PadLog.network("MacServer: loaded server identity with fingerprint: \(identity.fingerprintHex)")
        } catch {
            statusText = "Gagal memuat Server Identity dari Keychain: \(error.localizedDescription)"
            PadLog.network("MacServer: server identity error: \(error)")
            return
        }

        guard let identity = serverIdentity else { return }

        // 2. Start TLS 1.3 Listener (M2.2)
        do {
            guard let port = NWEndpoint.Port(rawValue: PadProtocol.port) else {
                statusText = "Port tidak valid"
                return
            }

            let parameters = PadProtocol.tlsServerParameters(secIdentity: identity.secIdentity)
            let newListener = try NWListener(using: parameters, on: port)

            let deviceName = Host.current().localizedName ?? "Mac"
            newListener.service = NWListener.Service(
                name: "EvoPad-\(deviceName)",
                type: PadProtocol.serviceType
            )

            newListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.statusText = "Siap (TLS 1.3 Aktif) — menunggu iPad"
                    case .failed(let error):
                        self.isListening = false
                        self.statusText = "Gagal membuka layanan TLS: \(error.localizedDescription)"
                        self.listener?.cancel()
                        self.listener = nil
                    case .cancelled:
                        self.isListening = false
                        self.statusText = "Layanan dihentikan"
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener = newListener
            newListener.start(queue: .main)
        } catch {
            statusText = "Tidak dapat menjalankan server TLS: \(error.localizedDescription)"
        }
    }

    func refreshPermission() {
        hasAccessibilityPermission = eventController.hasAccessibilityPermission
    }

    func loadPairedDevicesList() {
        securityQueue.async { [weak self] in
            let devices = PadKeychainStore.shared.loadPairedDevices()
            DispatchQueue.main.async {
                self?.pairedDevices = devices
            }
        }
    }

    // MARK: - Pairing QR Management (M2.3)

    func generateNewPairingQR() {
        securityQueue.async { [weak self] in
            guard let self, let identity = self.serverIdentity else { return }

            let secretHex = PadCryptoUtils.randomHex(count: 32)
            let expiry = Date().timeIntervalSince1970 + PadSecurityConstants.pairingQRExpirySeconds
            self.activeQRSecretHex = secretHex
            self.activeQRExpiry = expiry

            let deviceName = Host.current().localizedName ?? "Mac"
            let qrData = PadPairingQRData(
                version: 2,
                servicePort: PadProtocol.port,
                serverDeviceId: self.serverDeviceId,
                serverName: deviceName,
                certFingerprintHex: identity.fingerprintHex,
                oneTimeSecretHex: secretHex,
                expiresAt: expiry
            )

            let image = self.createQRCodeImage(from: qrData.serialize() ?? "")

            DispatchQueue.main.async {
                self.currentQRData = qrData
                self.qrImage = image
            }
        }
    }

    private func createQRCodeImage(from string: String) -> NSImage? {
        guard let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let scaledCIImage = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledCIImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    // MARK: - Pairing Approval Handling (M2.3)

    func approvePendingPairing(approved: Bool) {
        guard let approval = pendingPairingRequest else { return }
        pendingPairingRequest = nil

        securityQueue.async { [weak self] in
            guard let self,
                  let pending = self.pendingConnections[approval.connectionId],
                  let pairingId = pending.pairingId else {
                return
            }

            if !approved {
                PadLog.network("MacServer: pairing rejected by user for connection \(pending.id)")
                self.sendEnvelopeV2(
                    .error(requestId: pairingId, code: .pairingRejected, message: "Pairing ditolak oleh pengguna Mac"),
                    over: pending.connection
                )
                self.cleanupPendingConnection(id: pending.id)
                return
            }

            // Generate persistent 256-bit pairing token
            let pairingTokenHex = PadCryptoUtils.randomHex(count: 32)
            pending.pendingTokenHex = pairingTokenHex

            // Send .authResult with token over TLS
            let response = PadEnvelopeV2(
                requestId: pairingId,
                type: .authResult,
                payload: PadPayloadV2(
                    status: "approved",
                    message: "Pairing disetujui",
                    pairingToken: pairingTokenHex
                )
            )
            self.sendEnvelopeV2(response, over: pending.connection)
            PadLog.network("MacServer: sent approved pairing token to iPad")
        }
    }

    // MARK: - Device Revocation (M2.5)

    func revokeDevice(deviceId: String) {
        securityQueue.async { [weak self] in
            guard let self else { return }
            try? PadKeychainStore.shared.removeDevice(deviceId: deviceId)
            self.loadPairedDevicesList()

            // If active connection matches revoked device, invalidate immediately
            self.inputQueue.async {
                if let active = self.activeSession, active.clientDeviceId == deviceId {
                    PadLog.network("MacServer: active session device revoked, terminating connection")
                    self.eventController.releaseAllButtons()
                    self.activeConnection?.cancel()
                    self.activeConnection = nil
                    self.activeSession = nil
                    DispatchQueue.main.async {
                        self.connectedDevice = "Belum ada iPad"
                        self.statusText = "Koneksi diputus karena izin perangkat dicabut"
                    }
                }
            }
        }
    }

    func revokeAllDevices() {
        securityQueue.async { [weak self] in
            guard let self else { return }
            try? PadKeychainStore.shared.removeAllDevices()
            self.loadPairedDevicesList()

            self.inputQueue.async {
                self.eventController.releaseAllButtons()
                self.activeConnection?.cancel()
                self.activeConnection = nil
                self.activeSession = nil
                DispatchQueue.main.async {
                    self.connectedDevice = "Belum ada iPad"
                    self.statusText = "Semua perangkat dicabut"
                }
            }
        }
    }

    // MARK: - Connection Isolation & Lifecycle (M2.4 & M2.5)

    private func handleNewConnection(_ connection: NWConnection) {
        securityQueue.async { [weak self] in
            guard let self else { return }

            // Guard pending count limit
            if self.pendingConnections.count >= PadSecurityConstants.maxPendingConnections {
                PadLog.network("MacServer: rejected connection (max pending reached)")
                connection.cancel()
                return
            }

            let connectionId = UUID().uuidString
            let pending = PendingConnection(id: connectionId, connection: connection)

            // Arm 10s handshake timeout
            let timeoutItem = DispatchWorkItem { [weak self, weak connection] in
                PadLog.network("MacServer: pending handshake timed out for \(connectionId)")
                connection?.cancel()
                self?.cleanupPendingConnection(id: connectionId)
            }
            pending.timeoutWorkItem = timeoutItem
            self.securityQueue.asyncAfter(deadline: .now() + PadSecurityConstants.handshakeTimeoutSeconds, execute: timeoutItem)

            self.pendingConnections[connectionId] = pending

            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    self?.cleanupPendingConnection(id: connectionId)
                default:
                    break
                }
            }

            connection.start(queue: self.inputQueue)
            self.receive(on: connection, connectionId: connectionId, pendingBuffer: Data())
        }
    }

    private func cleanupPendingConnection(id: String) {
        securityQueue.async { [weak self] in
            guard let self, let pending = self.pendingConnections.removeValue(forKey: id) else { return }
            pending.timeoutWorkItem?.cancel()
            pending.connection.cancel()
        }
    }

    private func promoteToActiveConnection(pending: PendingConnection) {
        pending.timeoutWorkItem?.cancel()
        pendingConnections.removeValue(forKey: pending.id)

        inputQueue.async { [weak self] in
            guard let self else { return }

            // Safe replacement of active connection
            self.eventController.releaseAllButtons()
            self.activeConnection?.cancel()

            let session = AuthenticatedSession(
                clientDeviceId: pending.clientDeviceId ?? "Unknown",
                clientName: pending.clientName ?? "iPad",
                authenticatedAt: Date(),
                connection: pending.connection
            )
            self.activeSession = session
            self.activeConnection = pending.connection

            DispatchQueue.main.async {
                self.connectedDevice = "\(session.clientName) (Terautentikasi)"
                self.statusText = "Terhubung (TLS 1.3 Terautentikasi)"
            }

            pending.connection.stateUpdateHandler = { [weak self, weak connection = pending.connection] state in
                guard let self else { return }
                switch state {
                case .failed, .cancelled:
                    self.eventController.releaseAllButtons()
                    DispatchQueue.main.async {
                        guard let connection, self.activeConnection === connection else { return }
                        self.lastInputText = "Koneksi terputus — tombol mouse dilepas"
                        self.activeConnection = nil
                        self.activeSession = nil
                        self.connectedDevice = "Belum ada iPad"
                        self.statusText = self.isListening ? "Siap (TLS 1.3 Aktif) — menunggu iPad" : "Koneksi terputus"
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - Receive Loop & Authorization Gate

    private func receive(on connection: NWConnection, connectionId: String, pendingBuffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            var buffer = pendingBuffer
            if let data {
                buffer.append(data)
            }

            loop: while true {
                switch PadFrameCodec.popNextFrame(from: &buffer) {
                case .needMoreData:
                    break loop

                case .frameTooLarge(let size):
                    PadLog.network("Mac: frame rejected (>16KB, size=\(size))")
                    self.sendEnvelopeV2(
                        .error(requestId: "frame-limit", code: .frameTooLarge, message: "Frame melebihi 16 KB"),
                        over: connection
                    )
                    connection.cancel()
                    self.cleanupPendingConnection(id: connectionId)
                    return

                case .line(let line):
                    if line.isEmpty { continue }
                    self.processFrame(line, connection: connection, connectionId: connectionId)
                }
            }

            if error != nil || isComplete {
                self.inputQueue.async {
                    if self.activeConnection === connection {
                        self.eventController.releaseAllButtons()
                        self.activeConnection = nil
                        self.activeSession = nil
                    }
                }
                self.cleanupPendingConnection(id: connectionId)
                connection.cancel()
                return
            }

            self.receive(on: connection, connectionId: connectionId, pendingBuffer: buffer)
        }
    }

    private func processFrame(_ line: Data, connection: NWConnection, connectionId: String) {
        switch PadFrameCodec.decodeClientFrame(line) {
        case .success(.v1Command(let command)):
            // Authorization Gate: V1 commands are ONLY allowed on active authenticated session
            guard isConnectionActiveAndAuthorized(connection) else {
                PadLog.network("Mac: rejected unauthenticated V1 command")
                sendEnvelopeV2(
                    .error(requestId: "auth-gate", code: .unauthenticated, message: "Koneksi belum terautentikasi"),
                    over: connection
                )
                return
            }
            handleV1Command(command, over: connection)

        case .success(.v2Envelope(let envelope)):
            // Check if envelope is handshake/pairing
            switch envelope.type {
            case .hello, .auth, .pairingCommit:
                handleSecurityHandshake(envelope, connection: connection, connectionId: connectionId)
            default:
                // Other V2 commands require authenticated session
                guard isConnectionActiveAndAuthorized(connection) else {
                    PadLog.network("Mac: rejected unauthenticated V2 command \(envelope.type.rawValue)")
                    sendEnvelopeV2(
                        .error(requestId: envelope.requestId, code: .unauthenticated, message: "Koneksi belum terautentikasi"),
                        over: connection
                    )
                    return
                }
                handleV2Envelope(envelope, over: connection)
            }

        case .failure(let decodeError):
            handleDecodeError(decodeError, over: connection)
        }
    }

    private func isConnectionActiveAndAuthorized(_ connection: NWConnection) -> Bool {
        guard let session = activeSession,
              !session.isExpired,
              activeConnection === connection else {
            return false
        }
        return true
    }

    // MARK: - Handshake, Pairing & Reconnect Logic (M2.3 & M2.4)

    private func handleSecurityHandshake(_ envelope: PadEnvelopeV2, connection: NWConnection, connectionId: String) {
        securityQueue.async { [weak self] in
            guard let self, let pending = self.pendingConnections[connectionId] else { return }

            switch envelope.type {
            case .hello:
                guard let payload = envelope.payload,
                      let clientDevId = payload.clientDeviceId,
                      let clientNonceHex = payload.nonce,
                      let clientNonce = Data(hexString: clientNonceHex),
                      let mode = payload.authMode else {
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .invalidPayload, message: "Payload hello tidak lengkap"), over: connection)
                    return
                }

                pending.clientDeviceId = clientDevId
                pending.clientName = payload.deviceName ?? "iPad"
                pending.clientNonce = clientNonce
                pending.authMode = mode
                pending.pairingId = envelope.requestId

                let serverNonce = PadCryptoUtils.randomBytes(count: 32)
                pending.serverNonce = serverNonce

                let challenge = PadEnvelopeV2(
                    requestId: envelope.requestId,
                    type: .challenge,
                    payload: PadPayloadV2(
                        serverDeviceId: self.serverDeviceId,
                        pairingId: envelope.requestId,
                        nonce: serverNonce.map { String(format: "%02x", $0) }.joined(),
                        authMode: mode
                    )
                )
                self.sendEnvelopeV2(challenge, over: connection)
                PadLog.network("MacServer: sent challenge to client mode=\(mode)")

            case .auth:
                guard let payload = envelope.payload,
                      let clientHmac = payload.hmac,
                      let clientNonce = pending.clientNonce,
                      let serverNonce = pending.serverNonce,
                      let pairingId = pending.pairingId,
                      let mode = pending.authMode,
                      let clientDevId = pending.clientDeviceId else {
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .invalidPayload, message: "Payload auth tidak lengkap"), over: connection)
                    return
                }

                let certFingerprintData = Data(hexString: self.certFingerprintHex) ?? Data()

                if mode == "pairing" {
                    // Check QR Secret expiry & presence
                    guard let activeSecretHex = self.activeQRSecretHex,
                          Date().timeIntervalSince1970 <= self.activeQRExpiry,
                          let secretData = Data(hexString: activeSecretHex) else {
                        PadLog.network("MacServer: pairing attempt with expired or missing QR secret")
                        self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .pairingExpired, message: "Kode QR pairing sudah kedaluwarsa"), over: connection)
                        self.cleanupPendingConnection(id: connectionId)
                        return
                    }

                    // Single-use: consume QR secret immediately
                    self.activeQRSecretHex = nil

                    // Verify Client Proof HMAC
                    let transcript = PadCanonicalTranscript(
                        domain: PadSecurityConstants.domainPairingClientProof,
                        protocolVersion: PadSecurityConstants.protocolVersion,
                        pairingId: pairingId,
                        clientDeviceId: clientDevId,
                        serverDeviceId: self.serverDeviceId,
                        clientNonce: clientNonce,
                        serverNonce: serverNonce,
                        certFingerprint: certFingerprintData,
                        sessionContext: "pairing",
                        role: "client"
                    )

                    guard transcript.verifyHMAC(keyData: secretData, expectedHmacHex: clientHmac) else {
                        PadLog.network("MacServer: client pairing proof HMAC verification failed")
                        self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .authFailed, message: "HMAC pairing client tidak valid"), over: connection)
                        self.cleanupPendingConnection(id: connectionId)
                        return
                    }

                    // Request User Approval on UI
                    DispatchQueue.main.async {
                        self.pendingPairingRequest = PendingPairingApproval(
                            id: pairingId,
                            clientDeviceId: clientDevId,
                            clientName: pending.clientName ?? "iPad",
                            connectionId: connectionId
                        )
                    }

                } else if mode == "reconnect" {
                    // Reconnect: lookup persistent token from Keychain
                    let pairedDevices = PadKeychainStore.shared.loadPairedDevices()
                    guard let matchedDevice = pairedDevices.first(where: { $0.deviceId == clientDevId }),
                          let tokenData = Data(hexString: matchedDevice.pairingTokenHex) else {
                        PadLog.network("MacServer: reconnect failed, device not paired: \(clientDevId)")
                        self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .unauthenticated, message: "Perangkat belum terdaftar"), over: connection)
                        self.cleanupPendingConnection(id: connectionId)
                        return
                    }

                    // Verify Client Proof
                    let transcript = PadCanonicalTranscript(
                        domain: PadSecurityConstants.domainReconnectClientProof,
                        protocolVersion: PadSecurityConstants.protocolVersion,
                        pairingId: pairingId,
                        clientDeviceId: clientDevId,
                        serverDeviceId: self.serverDeviceId,
                        clientNonce: clientNonce,
                        serverNonce: serverNonce,
                        certFingerprint: certFingerprintData,
                        sessionContext: "reconnect",
                        role: "client"
                    )

                    guard transcript.verifyHMAC(keyData: tokenData, expectedHmacHex: clientHmac) else {
                        PadLog.network("MacServer: client reconnect HMAC verification failed")
                        self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .authFailed, message: "HMAC reconnect tidak valid"), over: connection)
                        self.cleanupPendingConnection(id: connectionId)
                        return
                    }

                    // Compute Server Proof
                    let serverTranscript = PadCanonicalTranscript(
                        domain: PadSecurityConstants.domainReconnectServerProof,
                        protocolVersion: PadSecurityConstants.protocolVersion,
                        pairingId: pairingId,
                        clientDeviceId: clientDevId,
                        serverDeviceId: self.serverDeviceId,
                        clientNonce: clientNonce,
                        serverNonce: serverNonce,
                        certFingerprint: certFingerprintData,
                        sessionContext: "reconnect",
                        role: "server"
                    )
                    let serverHmac = serverTranscript.computeHMAC(keyData: tokenData)

                    // Send authResult
                    self.sendEnvelopeV2(
                        PadEnvelopeV2(
                            requestId: envelope.requestId,
                            type: .authResult,
                            payload: PadPayloadV2(status: "authenticated", hmac: serverHmac)
                        ),
                        over: connection
                    )

                    // Promote connection to active
                    self.promoteToActiveConnection(pending: pending)
                    PadLog.network("MacServer: reconnect mutual authentication successful")
                }

            case .pairingCommit:
                guard let payload = envelope.payload,
                      let commitHmac = payload.hmac,
                      let tokenHex = pending.pendingTokenHex,
                      let tokenData = Data(hexString: tokenHex),
                      let clientDevId = pending.clientDeviceId,
                      let pairingId = pending.pairingId,
                      let clientNonce = pending.clientNonce,
                      let serverNonce = pending.serverNonce else {
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .invalidPayload, message: "Commit payload tidak valid"), over: connection)
                    return
                }

                let certFingerprintData = Data(hexString: self.certFingerprintHex) ?? Data()
                let commitTranscript = PadCanonicalTranscript(
                    domain: PadSecurityConstants.domainPairingCommit,
                    protocolVersion: PadSecurityConstants.protocolVersion,
                    pairingId: pairingId,
                    clientDeviceId: clientDevId,
                    serverDeviceId: self.serverDeviceId,
                    clientNonce: clientNonce,
                    serverNonce: serverNonce,
                    certFingerprint: certFingerprintData,
                    sessionContext: "pairing-commit",
                    role: "client"
                )

                guard commitTranscript.verifyHMAC(keyData: tokenData, expectedHmacHex: commitHmac) else {
                    PadLog.network("MacServer: pairingCommit HMAC verification failed")
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .authFailed, message: "HMAC pairing commit tidak valid"), over: connection)
                    self.cleanupPendingConnection(id: connectionId)
                    return
                }

                // Persist device in Keychain
                let deviceRecord = PadPairedDevice(
                    deviceId: clientDevId,
                    name: pending.clientName ?? "iPad",
                    pairingTokenHex: tokenHex,
                    certFingerprintHex: nil,
                    pairedDate: Date(),
                    lastAuthenticatedDate: Date()
                )
                try? PadKeychainStore.shared.saveDevice(deviceRecord)
                self.loadPairedDevicesList()

                // Send pairingComplete
                self.sendEnvelopeV2(
                    PadEnvelopeV2(
                        requestId: envelope.requestId,
                        type: .pairingComplete,
                        payload: PadPayloadV2(status: "success", message: "Pairing selesai")
                    ),
                    over: connection
                )

                // Activate connection
                self.promoteToActiveConnection(pending: pending)
                PadLog.network("MacServer: pairing complete, device registered and connection active")

            default:
                break
            }
        }
    }

    // MARK: - Input Command Dispatch

    private func handleV1Command(_ command: PadCommand, over connection: NWConnection) {
        if command.type == .gesture, let direction = command.gestureDirection {
            PadLog.network("Mac: received gesture command direction=\(direction.rawValue)")
            self.eventController.releaseAllButtons()
            let sent = self.eventController.performGesture(direction)
            let message = sent
                ? "Mac Helper menerima \(direction.title) dan mem-post Control + panah ke sesi macOS."
                : "Mac Helper menerima \(direction.title), tetapi gagal membuat event keyboard."
            self.sendGestureAcknowledgement(
                PadAcknowledgement.gesture(direction: direction, accepted: sent, message: message),
                over: connection
            )
            DispatchQueue.main.async {
                self.lastInputText = sent
                    ? "\(direction.title): event dipost ke sesi macOS"
                    : "\(direction.title): event gagal dibuat/dipost"
            }
        } else {
            let start = DispatchTime.now().uptimeNanoseconds
            self.eventController.handle(command)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
            if elapsedMs > 8 {
                PadLog.pointer("Mac: \(command.type.rawValue) decode+post took \(String(format: "%.1f", elapsedMs))ms")
            }
            self.updateInputFeedback(for: command)
        }
    }

    private func handleV2Envelope(_ envelope: PadEnvelopeV2, over connection: NWConnection) {
        switch envelope.type {
        case .pointerEvent:
            guard let payload = envelope.payload, let action = payload.pointerAction else { return }
            let mapped = PadCommand(
                type: action,
                dx: payload.dx,
                dy: payload.dy,
                button: payload.button,
                gestureDirection: nil
            )
            handleV1Command(mapped, over: connection)

        case .gestureEvent:
            guard let direction = envelope.payload?.gestureDirection else { return }
            eventController.releaseAllButtons()
            let sent = eventController.performGesture(direction)
            sendEnvelopeV2(
                .ack(requestId: envelope.requestId, accepted: sent, message: direction.title),
                over: connection
            )

        case .keyboardEvent, .textInput, .shortcutExecute, .mediaControl, .systemControl, .macroExecute:
            sendEnvelopeV2(
                .error(
                    requestId: envelope.requestId,
                    code: .unsupportedAction,
                    message: "Tipe \(envelope.type.rawValue) belum diaktifkan pada milestone M2"
                ),
                over: connection
            )

        default:
            break
        }
    }

    private func handleDecodeError(_ decodeError: PadProtocolDecodeError, over connection: NWConnection) {
        switch decodeError {
        case .emptyFrame:
            break
        case .malformedJSON:
            sendEnvelopeV2(.error(requestId: "invalid-json", code: .invalidPayload, message: "Format JSON tidak valid"), over: connection)
        case .frameTooLarge(let size):
            sendEnvelopeV2(.error(requestId: "frame-limit", code: .frameTooLarge, message: "Frame melebihi 16 KB (\(size) bytes)"), over: connection)
        case .unsupportedVersion(let version, let requestId):
            sendEnvelopeV2(
                .error(
                    requestId: requestId ?? "version-check",
                    code: .unsupportedVersion,
                    message: "Versi protokol \(version) tidak didukung",
                    minVersion: PadProtocol.minimumSupportedVersion,
                    maxVersion: PadProtocol.currentVersion
                ),
                over: connection
            )
        case .invalidPayload(let requestId, let err):
            sendEnvelopeV2(PadEnvelopeV2(requestId: requestId, type: .error, error: err), over: connection)
        }
    }

    private func sendEnvelopeV2(_ envelope: PadEnvelopeV2, over connection: NWConnection) {
        guard var data = try? JSONEncoder().encode(envelope) else { return }
        data.append(0x0A)
        connection.send(
            content: data,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { error in
                if let error {
                    PadLog.network("Mac: V2 send error: \(error.localizedDescription)")
                }
            }
        )
    }

    private func sendGestureAcknowledgement(_ acknowledgement: PadAcknowledgement, over connection: NWConnection) {
        guard var data = try? JSONEncoder().encode(acknowledgement) else { return }
        data.append(0x0A)
        connection.send(
            content: data,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.lastInputText = "ACK gagal dikirim ke iPad: \(error.localizedDescription)"
                }
            }
        )
    }

    private func recordPointerFrame() {
        receivedRate.tick()
        pointerFrameCount += 1
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now &- pointerRateWindowStart
        guard elapsed >= 1_000_000_000 else { return }

        let measuredHz = Int((Double(pointerFrameCount) / (Double(elapsed) / 1_000_000_000)).rounded())
        pointerFrameCount = 0
        pointerRateWindowStart = now
        DispatchQueue.main.async { [weak self] in
            self?.pointerInputHz = measuredHz
        }
    }

    private func updateInputFeedback(for command: PadCommand) {
        if command.type == .move {
            recordPointerFrame()
        }

        let message: String?
        switch command.type {
        case .buttonDown:
            message = "Drag diterima: tombol kiri ditahan"
        case .buttonUp:
            message = "Drag selesai: tombol mouse dilepas"
        case .click:
            message = command.button == .right ? "Klik kanan diterima" : "Klik kiri diterima"
        case .move, .scroll, .gesture:
            message = nil
        }

        guard let message else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastInputText = message
        }
    }

    func testGesture(_ direction: PadGestureDirection) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.eventController.releaseAllButtons()
            let sent = self.eventController.performGesture(direction)
            DispatchQueue.main.async {
                self.lastInputText = sent
                    ? "Tes \(direction.title): event Control + panah dikirim"
                    : "Tes \(direction.title) gagal: periksa izin Accessibility atau shortcut"
            }
        }
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let granted = eventController.requestAccessibilityPermission()
        refreshPermission()
        return granted
    }
}
