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
    @Published private(set) var serverDeviceId: String = {
        let key = "id.evonex.evopad.serverDeviceId.v2"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }()
    @Published private(set) var certFingerprintHex = ""
    @Published private(set) var currentQRData: PadPairingQRData?
    @Published private(set) var qrImage: NSImage?
    @Published private(set) var qrErrorMessage: String?
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

    // Connection Isolation:
    // - `activeConnection` and `activeSession` are owned exclusively by `inputQueue`.
    // - `pendingConnections` is owned exclusively by `securityQueue`.
    private var activeConnection: NWConnection?
    private var activeSession: AuthenticatedSession?
    private var pendingConnections: [String: PendingConnection] = [:]

    private let inputQueue = DispatchQueue(label: "id.evonex.evopad.mac-input", qos: .userInteractive)
    private let securityQueue = DispatchQueue(label: "id.evonex.evopad.mac-security", qos: .default)
    private let eventController = InputEventController()
    private let keyboardController = PadKeyboardController()
    private lazy var macroExecutor = PadMacroExecutor(keyboardController: keyboardController)
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

    private var isInitializing = false

    func start() {
        guard listener == nil else { return }
        refreshPermission()
        loadPairedDevicesList()

        // 1. Initialize Server Identity & Keychain (M2.1)
        do {
            let identity = try PadServerIdentity.loadOrCreate()
            self.serverIdentity = identity
            self.certFingerprintHex = identity.fingerprintHex
            self.qrErrorMessage = nil
            PadLog.network("MacServer: loaded server identity with fingerprint: \(identity.fingerprintHex)")
        } catch {
            statusText = "Gagal memuat Server Identity dari Keychain: \(error.localizedDescription)"
            qrErrorMessage = "Gagal memuat Server Identity dari Keychain: \(error.localizedDescription)"
            PadLog.network("MacServer: server identity error: \(error)")
            return
        }

        guard let identity = serverIdentity else { return }

        // 2. Start TLS 1.3 Listener (M2.2)
        startListener(with: identity)
    }

    func retryIdentityInitialization() {
        securityQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isInitializing else {
                PadLog.network("MacServer: identity initialization already in progress, ignoring retry")
                return
            }
            self.isInitializing = true
            defer { self.isInitializing = false }

            DispatchQueue.main.async {
                self.statusText = "Menginisialisasi Server Identity..."
                self.qrErrorMessage = nil
            }

            do {
                let identity = try PadServerIdentity.loadOrCreate()
                self.serverIdentity = identity
                DispatchQueue.main.async {
                    self.certFingerprintHex = identity.fingerprintHex
                    self.qrErrorMessage = nil
                    self.statusText = "Server Identity berhasil dimuat"
                }
                PadLog.network("MacServer: successfully reloaded server identity: \(identity.fingerprintHex)")
                self.startListener(with: identity)
            } catch {
                DispatchQueue.main.async {
                    self.statusText = "Gagal memuat Server Identity dari Keychain: \(error.localizedDescription)"
                    self.qrErrorMessage = "Gagal memuat Server Identity dari Keychain: \(error.localizedDescription)"
                }
                PadLog.network("MacServer: retry server identity error: \(error)")
            }
        }
    }

    private func startListener(with identity: PadServerIdentity) {
        guard listener == nil else {
            PadLog.network("MacServer: listener already running, skipping startListener")
            return
        }
        guard let port = NWEndpoint.Port(rawValue: PadProtocol.port) else {
            DispatchQueue.main.async {
                self.statusText = "Port tidak valid"
            }
            return
        }

        do {
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
            DispatchQueue.main.async {
                self.statusText = "Tidak dapat menjalankan server TLS: \(error.localizedDescription)"
            }
        }
    }

    func refreshPermission() {
        hasAccessibilityPermission = eventController.hasAccessibilityPermission && keyboardController.hasAccessibilityPermission
    }

    /// Runs local testing of a shortcut on the Mac Helper side.
    func testShortcut(_ shortcut: PadStandardShortcut) {
        keyboardController.executeShortcut(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers
        ) { [weak self] success, message in
            DispatchQueue.main.async {
                self?.lastInputText = success
                    ? "Tes shortcut \(shortcut.title) (\(shortcut.chordDescription)): sukses"
                    : "Tes shortcut \(shortcut.title) gagal: \(message)"
            }
        }
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
            guard let self else { return }

            guard let identity = self.serverIdentity else {
                DispatchQueue.main.async {
                    self.qrErrorMessage = "Server Identity belum siap: \(self.statusText)"
                    self.qrImage = nil
                }
                PadLog.network("MacServer: generateNewPairingQR failed because serverIdentity is nil")
                return
            }

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

            guard let serialized = qrData.serialize(),
                  let image = self.createQRCodeImage(from: serialized) else {
                DispatchQueue.main.async {
                    self.qrErrorMessage = "Gagal membuat gambar QR code"
                    self.qrImage = nil
                }
                return
            }

            DispatchQueue.main.async {
                self.qrErrorMessage = nil
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
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.securityQueue))
            guard let pending = self.pendingConnections[approval.connectionId],
                  let pairingId = pending.pairingId else {
                return
            }

            if !approved {
                PadLog.network("MacServer: pairing rejected by user for connection \(pending.id)")
                self.sendEnvelopeV2(
                    .error(requestId: pairingId, code: .pairingRejected, message: "Pairing ditolak oleh pengguna Mac"),
                    over: pending.connection
                )
                self.cleanupPendingConnectionOnSecurityQueue(id: pending.id)
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
                    pairingToken: pairingTokenHex,
                    status: "approved",
                    message: "Pairing disetujui"
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
            dispatchPrecondition(condition: .onQueue(self.securityQueue))
            try? PadKeychainStore.shared.removeDevice(deviceId: deviceId)
            self.loadPairedDevicesList()

            // Cancel any pending connection from this device
            let matchingPendingIds = self.pendingConnections.values
                .filter { $0.clientDeviceId == deviceId }
                .map { $0.id }
            for pendingId in matchingPendingIds {
                self.cleanupPendingConnectionOnSecurityQueue(id: pendingId)
            }

            // If active connection matches revoked device, invalidate on inputQueue
            self.inputQueue.async { [weak self] in
                guard let self else { return }
                dispatchPrecondition(condition: .onQueue(self.inputQueue))
                if let active = self.activeSession, active.clientDeviceId == deviceId {
                    PadLog.network("MacServer: active session device revoked, terminating connection")
                    self.invalidateActiveConnectionOnInputQueue(
                        statusMessage: "Koneksi diputus karena izin perangkat dicabut",
                        inputMessage: nil
                    )
                }
            }
        }
    }

    func revokeAllDevices() {
        securityQueue.async { [weak self] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.securityQueue))
            try? PadKeychainStore.shared.removeAllDevices()
            self.loadPairedDevicesList()

            let allPendingIds = Array(self.pendingConnections.keys)
            for pendingId in allPendingIds {
                self.cleanupPendingConnectionOnSecurityQueue(id: pendingId)
            }

            self.inputQueue.async { [weak self] in
                guard let self else { return }
                dispatchPrecondition(condition: .onQueue(self.inputQueue))
                self.invalidateActiveConnectionOnInputQueue(
                    statusMessage: "Semua perangkat dicabut",
                    inputMessage: nil
                )
            }
        }
    }

    // MARK: - Connection Isolation & Lifecycle (M2.4 & M2.5)

    private func handleNewConnection(_ connection: NWConnection) {
        securityQueue.async { [weak self, connection] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.securityQueue))

            // Guard pending count limit
            if self.pendingConnections.count >= PadSecurityConstants.maxPendingConnections {
                PadLog.network("MacServer: rejected connection (max pending reached)")
                connection.cancel()
                return
            }

            let connectionId = UUID().uuidString
            let pending = PendingConnection(id: connectionId, connection: connection)

            // Arm 10s handshake timeout on securityQueue
            let timeoutItem = DispatchWorkItem { [weak self, weak connection] in
                guard let self else { return }
                dispatchPrecondition(condition: .onQueue(self.securityQueue))
                PadLog.network("MacServer: pending handshake timed out for \(connectionId)")
                connection?.cancel()
                self.cleanupPendingConnectionOnSecurityQueue(id: connectionId)
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
            guard let self else { return }
            self.cleanupPendingConnectionOnSecurityQueue(id: id)
        }
    }

    private func cleanupPendingConnectionOnSecurityQueue(id: String) {
        dispatchPrecondition(condition: .onQueue(securityQueue))
        guard let pending = pendingConnections.removeValue(forKey: id) else { return }
        pending.timeoutWorkItem?.cancel()
        pending.connection.cancel()
        DispatchQueue.main.async { [weak self] in
            if self?.pendingPairingRequest?.connectionId == id {
                self?.pendingPairingRequest = nil
            }
        }
    }

    private func promoteToActiveConnection(pending: PendingConnection) {
        dispatchPrecondition(condition: .onQueue(securityQueue))
        pending.timeoutWorkItem?.cancel()
        pendingConnections.removeValue(forKey: pending.id)

        let clientDeviceId = pending.clientDeviceId ?? "Unknown"
        let clientName = pending.clientName ?? "iPad"
        let promotedConnection = pending.connection

        inputQueue.async { [weak self] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.inputQueue))

            // Safe replacement of previous active connection on inputQueue
            if let oldConnection = self.activeConnection, oldConnection !== promotedConnection {
                oldConnection.stateUpdateHandler = nil
                oldConnection.cancel()
            }
            self.eventController.releaseAllButtons()
            self.keyboardController.releaseAll()
            self.macroExecutor.cancelCurrentMacro()

            let session = AuthenticatedSession(
                clientDeviceId: clientDeviceId,
                clientName: clientName,
                authenticatedAt: Date(),
                connection: promotedConnection
            )
            self.activeSession = session
            self.activeConnection = promotedConnection

            DispatchQueue.main.async { [weak self] in
                self?.connectedDevice = "\(session.clientName) (Terautentikasi)"
                self?.statusText = "Terhubung (TLS 1.3 Terautentikasi)"
            }

            // Since `promotedConnection` was started on `inputQueue`, its stateUpdateHandler
            // runs on `inputQueue`. Validate queue ownership and mutate `activeConnection`
            // / `activeSession` strictly on `inputQueue`.
            promotedConnection.stateUpdateHandler = { [weak self, weak connection = promotedConnection] state in
                guard let self else { return }
                dispatchPrecondition(condition: .onQueue(self.inputQueue))
                switch state {
                case .failed, .cancelled:
                    guard let connection, self.activeConnection === connection else { return }
                    self.invalidateActiveConnectionOnInputQueue(
                        statusMessage: nil,
                        inputMessage: "Koneksi terputus — tombol mouse & keyboard dilepas"
                    )
                default:
                    break
                }
            }
        }
    }

    private func invalidateActiveConnectionOnInputQueue(
        statusMessage: String?,
        inputMessage: String?
    ) {
        dispatchPrecondition(condition: .onQueue(inputQueue))
        let connectionToCancel = activeConnection
        activeConnection = nil
        activeSession = nil

        eventController.releaseAllButtons()
        keyboardController.releaseAll()
        macroExecutor.cancelCurrentMacro()
        connectionToCancel?.cancel()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let inputMessage {
                self.lastInputText = inputMessage
            }
            self.connectedDevice = "Belum ada iPad"
            if let statusMessage {
                self.statusText = statusMessage
            } else {
                self.statusText = self.isListening ? "Siap (TLS 1.3 Aktif) — menunggu iPad" : "Koneksi terputus"
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

            var pendingMoveDx: Double = 0
            var pendingMoveDy: Double = 0
            var hasPendingMove = false

            loop: while true {
                switch PadFrameCodec.popNextFrame(from: &buffer) {
                case .needMoreData:
                    break loop

                case .frameTooLarge(let size):
                    if hasPendingMove {
                        self.handleV1Command(PadCommand(type: .move, dx: pendingMoveDx, dy: pendingMoveDy), over: connection)
                        hasPendingMove = false
                    }
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

                    // Batch-coalesce consecutive high-frequency pointer moves in the same network chunk
                    if line.count < 128,
                       let str = String(data: line, encoding: .utf8),
                       str.contains("\"move\""),
                       let cmd = PadFrameCodec.parseFastMotionCommand(from: str),
                       cmd.type == .move,
                       let dx = cmd.dx, let dy = cmd.dy {
                        guard self.isConnectionActiveAndAuthorized(connection) else { continue }
                        pendingMoveDx += dx
                        pendingMoveDy += dy
                        hasPendingMove = true
                        continue
                    }

                    // If a non-move frame is encountered, flush accumulated moves first to preserve strict event order
                    if hasPendingMove {
                        self.handleV1Command(PadCommand(type: .move, dx: pendingMoveDx, dy: pendingMoveDy), over: connection)
                        pendingMoveDx = 0
                        pendingMoveDy = 0
                        hasPendingMove = false
                    }

                    self.processFrame(line, connection: connection, connectionId: connectionId)
                }
            }

            // Flush remaining coalesced motion at end of chunk
            if hasPendingMove {
                self.handleV1Command(PadCommand(type: .move, dx: pendingMoveDx, dy: pendingMoveDy), over: connection)
            }

            if error != nil || isComplete {
                dispatchPrecondition(condition: .onQueue(self.inputQueue))
                if self.activeConnection === connection {
                    self.invalidateActiveConnectionOnInputQueue(
                        statusMessage: nil,
                        inputMessage: "Koneksi terputus — tombol mouse & keyboard dilepas"
                    )
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
        dispatchPrecondition(condition: .onQueue(inputQueue))
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
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.securityQueue))
            guard let pending = self.pendingConnections[connectionId] else { return }

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
                        self.cleanupPendingConnectionOnSecurityQueue(id: connectionId)
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
                        self.cleanupPendingConnectionOnSecurityQueue(id: connectionId)
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
                        self.cleanupPendingConnectionOnSecurityQueue(id: connectionId)
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
                        self.cleanupPendingConnectionOnSecurityQueue(id: connectionId)
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
                            payload: PadPayloadV2(hmac: serverHmac, status: "authenticated")
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
                    self.cleanupPendingConnectionOnSecurityQueue(id: connectionId)
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

        case .shortcutExecute:
            guard let payload = envelope.payload, let keyCode = payload.keyCode else {
                sendEnvelopeV2(
                    .error(requestId: envelope.requestId, code: .invalidPayload, message: "Payload shortcutExecute tidak lengkap (keyCode wajib diisi)"),
                    over: connection
                )
                return
            }

            keyboardController.executeShortcut(
                keyCode: keyCode,
                modifiers: payload.modifiers ?? []
            ) { [weak self, weak connection] accepted, message in
                guard let self, let connection else { return }
                self.sendEnvelopeV2(
                    .ack(requestId: envelope.requestId, accepted: accepted, message: message),
                    over: connection
                )
                DispatchQueue.main.async {
                    self.lastInputText = accepted ? message : "Shortcut gagal: \(message)"
                }
            }

        case .keyboardEvent:
            guard let payload = envelope.payload,
                  let keyCode = payload.keyCode,
                  let phase = payload.keyPhase else {
                sendEnvelopeV2(
                    .error(requestId: envelope.requestId, code: .invalidPayload, message: "Payload keyboardEvent tidak lengkap (keyCode & keyPhase wajib)"),
                    over: connection
                )
                return
            }

            keyboardController.handleKeyEvent(
                keyCode: keyCode,
                phase: phase,
                modifiers: payload.modifiers
            ) { [weak self, weak connection] accepted, message in
                guard let self, let connection else { return }
                self.sendEnvelopeV2(
                    .ack(requestId: envelope.requestId, accepted: accepted, message: message),
                    over: connection
                )
                DispatchQueue.main.async {
                    self.lastInputText = accepted ? message : "Key event gagal: \(message)"
                }
            }

        case .macroExecute:
            guard let payload = envelope.payload,
                  let steps = payload.steps,
                  let macroId = payload.macroId ?? payload.systemAction else {
                sendEnvelopeV2(
                    .error(requestId: envelope.requestId, code: .invalidPayload, message: "Payload macroExecute tidak lengkap (steps & macroId wajib)"),
                    over: connection
                )
                return
            }

            macroExecutor.executeMacro(macroId: macroId, steps: steps) { [weak self, weak connection] ok, errCode, message in
                guard let self, let connection else { return }
                if ok {
                    self.sendEnvelopeV2(
                        .ack(requestId: envelope.requestId, accepted: true, message: message),
                        over: connection
                    )
                    DispatchQueue.main.async {
                        self.lastInputText = message
                    }
                } else {
                    self.sendEnvelopeV2(
                        .error(requestId: envelope.requestId, code: errCode ?? .invalidPayload, message: message),
                        over: connection
                    )
                    DispatchQueue.main.async {
                        self.lastInputText = "Macro gagal: \(message)"
                    }
                }
            }

        case .mediaControl:
            guard let payload = envelope.payload,
                  let mediaKeyStr = payload.mediaKey,
                  let key = PadMediaControlKey(rawValue: mediaKeyStr) else {
                sendEnvelopeV2(
                    .error(requestId: envelope.requestId, code: .invalidPayload, message: "mediaKey tidak valid"),
                    over: connection
                )
                return
            }

            keyboardController.handleMediaKey(key) { [weak self, weak connection] ok, msg in
                guard let self, let connection else { return }
                if ok {
                    self.sendEnvelopeV2(.ack(requestId: envelope.requestId, accepted: true, message: msg), over: connection)
                    DispatchQueue.main.async { self.lastInputText = msg }
                } else {
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .permissionDenied, message: msg), over: connection)
                    DispatchQueue.main.async { self.lastInputText = "Media gagal: \(msg)" }
                }
            }

        case .systemControl:
            guard let payload = envelope.payload,
                  let actionStr = payload.systemAction,
                  let action = PadSystemControlAction(rawValue: actionStr) else {
                sendEnvelopeV2(
                    .error(requestId: envelope.requestId, code: .invalidPayload, message: "systemAction tidak valid"),
                    over: connection
                )
                return
            }

            keyboardController.handleSystemAction(action, targetApp: payload.text) { [weak self, weak connection] ok, msg in
                guard let self, let connection else { return }
                if ok {
                    self.sendEnvelopeV2(.ack(requestId: envelope.requestId, accepted: true, message: msg), over: connection)
                    DispatchQueue.main.async { self.lastInputText = msg }
                } else {
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: .permissionDenied, message: msg), over: connection)
                    DispatchQueue.main.async { self.lastInputText = "System action gagal: \(msg)" }
                }
            }

        case .textInput:
            guard let payload = envelope.payload,
                  let text = payload.text,
                  !text.isEmpty else {
                sendEnvelopeV2(
                    .error(requestId: envelope.requestId, code: .invalidPayload, message: "Teks kosong"),
                    over: connection
                )
                return
            }

            macroExecutor.executeTextInput(text) { [weak self, weak connection] ok, errCode, msg in
                guard let self, let connection else { return }
                if ok {
                    self.sendEnvelopeV2(.ack(requestId: envelope.requestId, accepted: true, message: msg), over: connection)
                    DispatchQueue.main.async { self.lastInputText = "Teks diketik: \(text)" }
                } else {
                    self.sendEnvelopeV2(.error(requestId: envelope.requestId, code: errCode ?? .permissionDenied, message: msg), over: connection)
                    DispatchQueue.main.async { self.lastInputText = "Teks gagal: \(msg)" }
                }
            }

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
        guard let data = PadFrameCodec.encodeV2Envelope(envelope) else { return }
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
        guard let data = PadFrameCodec.encodeV1Ack(acknowledgement) else { return }
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
