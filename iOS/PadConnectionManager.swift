import Combine
import Foundation
import Network
import UIKit

/// Owns Bonjour discovery, TLS 1.3 pinned transport, and mutual authentication
/// between iPad and Mac Helper.
final class PadConnectionManager: ObservableObject {
    @Published private(set) var statusText = "Mencari Mac..."
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var macFeedback = "Menunggu respons Mac"
    @Published private(set) var isPairedWithMac = false
    @Published private(set) var currentPairedMacName: String?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lastEndpoint: NWEndpoint?
    private let networkQueue = DispatchQueue(label: "id.evonex.evopad.ios-network", qos: .userInteractive)

    private var outstandingSends = 0
    private let clientDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    // Pairing Session State
    private var activeQRData: PadPairingQRData?
    private var clientNonce: Data?
    private var serverNonce: Data?
    private var currentPairingId: String?
    private var authMode: String = "reconnect" // "pairing" or "reconnect"

    init() {
        checkPairedStatus()
    }

    func checkPairedStatus() {
        let paired = PadKeychainStore.shared.loadPairedDevices()
        if let first = paired.first {
            isPairedWithMac = true
            currentPairedMacName = first.name
        } else {
            isPairedWithMac = false
            currentPairedMacName = nil
        }
    }

    func startDiscovery() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: PadProtocol.serviceType, domain: nil)
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failed(let error) = state {
                    self.statusText = "Pencarian gagal: \(error.localizedDescription)"
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, let first = results.first else { return }
            DispatchQueue.main.async {
                guard self.connection == nil else { return }
                self.lastEndpoint = first.endpoint

                let paired = PadKeychainStore.shared.loadPairedDevices()
                if let saved = paired.first, let fingerprint = saved.certFingerprintHex {
                    self.statusText = "Mac ditemukan, menghubungkan kembali via TLS..."
                    self.connectWithTLS(to: first.endpoint, pinnedFingerprintHex: fingerprint, mode: "reconnect")
                } else {
                    self.statusText = "Mac ditemukan. Pindai kode QR untuk pairing."
                }
            }
        }

        browser = newBrowser
        newBrowser.start(queue: networkQueue)
        statusText = "Mencari Mac di jaringan lokal..."
    }

    // MARK: - QR Pairing Initiation (M2.3)

    func pairWithQR(qrData: PadPairingQRData) {
        if qrData.isExpired {
            statusText = "Kode QR sudah kedaluwarsa. Buat kode baru di Mac."
            return
        }

        self.activeQRData = qrData
        self.authMode = "pairing"
        self.statusText = "Menghubungi Mac via TLS 1.3 (Verifikasi Pinning)..."

        if let endpoint = lastEndpoint {
            connectWithTLS(to: endpoint, pinnedFingerprintHex: qrData.certFingerprintHex, mode: "pairing")
        } else {
            // Fallback: connect directly using servicePort if discovered endpoint not yet available
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("Mac.local"),
                port: NWEndpoint.Port(rawValue: qrData.servicePort) ?? 49321
            )
            connectWithTLS(to: endpoint, pinnedFingerprintHex: qrData.certFingerprintHex, mode: "pairing")
        }
    }

    func unpairCurrentMac() {
        try? PadKeychainStore.shared.removeAllDevices()
        checkPairedStatus()
        connection?.cancel()
        connection = nil
        isConnected = false
        isAuthenticated = false
        statusText = "Pairing dicabut. Pindai QR untuk pairing baru."
    }

    // MARK: - TLS Connection & Pinned Verification (M2.2)

    private func connectWithTLS(to endpoint: NWEndpoint, pinnedFingerprintHex: String, mode: String) {
        lastEndpoint = endpoint
        connection?.cancel()
        isAuthenticated = false
        isConnected = false
        self.authMode = mode

        let parameters = PadProtocol.tlsClientParameters(
            pinnedFingerprintHex: pinnedFingerprintHex,
            verifyQueue: networkQueue
        )

        let newConnection = NWConnection(to: endpoint, using: parameters)
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let newConnection else { return }

            switch state {
            case .ready:
                DispatchQueue.main.async { [weak self, weak newConnection] in
                    guard let self,
                          let activeConn = newConnection,
                          self.connection === activeConn else { return }

                    PadLog.network("iPad: TLS 1.3 handshake successful, certificate pinned")
                    self.statusText = "TLS 1.3 Terhubung — Mengautentikasi..."
                    self.startHandshakeAuth(over: activeConn)
                    self.receiveLoop(on: activeConn)
                }

            case .failed(let error):
                DispatchQueue.main.async { [weak self, weak newConnection] in
                    guard let self,
                          let failedConn = newConnection,
                          self.connection === failedConn else { return }

                    self.isConnected = false
                    self.isAuthenticated = false
                    self.statusText = "Koneksi TLS gagal: \(error.localizedDescription)"
                    failedConn.cancel()
                    self.connection = nil
                    self.retryConnection()
                }

            case .cancelled:
                DispatchQueue.main.async { [weak self, weak newConnection] in
                    guard let self,
                          let cancelledConn = newConnection,
                          self.connection === cancelledConn else { return }

                    self.isConnected = false
                    self.isAuthenticated = false
                    self.connection = nil
                }

            default:
                break
            }
        }

        newConnection.start(queue: networkQueue)
    }

    // MARK: - Handshake & Authentication (M2.3 & M2.4)

    private func startHandshakeAuth(over connection: NWConnection) {
        let nonce = PadCryptoUtils.randomBytes(count: 32)
        self.clientNonce = nonce
        let nonceHex = nonce.map { String(format: "%02x", $0) }.joined()

        let deviceName = UIDevice.current.name
        let hello = PadEnvelopeV2(
            requestId: UUID().uuidString,
            type: .hello,
            payload: PadPayloadV2(
                clientDeviceId: clientDeviceId,
                deviceName: deviceName,
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

        networkQueue.async { [weak self] in
            guard let self, let connection = self.connection else { return }
            guard var data = try? JSONEncoder().encode(command) else { return }
            data.append(0x0A)

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
            guard var data = try? JSONEncoder().encode(envelope),
                  data.count <= PadProtocol.maximumFrameBytes else {
                return
            }
            data.append(0x0A)

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

    private func sendEnvelopeDirect(_ envelope: PadEnvelopeV2, over connection: NWConnection) {
        guard var data = try? JSONEncoder().encode(envelope) else { return }
        data.append(0x0A)
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
        activeConnection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak activeConnection] data, _, isComplete, error in
            guard let self, let activeConnection else { return }

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
                    activeConnection.cancel()
                    return

                case .line(let line):
                    if line.isEmpty { continue }
                    self.processIncomingLine(line, connection: activeConnection)
                }
            }

            if error != nil || isComplete {
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isAuthenticated = false
                }
                activeConnection.cancel()
                return
            }

            self.receiveLoop(on: activeConnection, pending: buffer)
        }
    }

    private func processIncomingLine(_ line: Data, connection: NWConnection) {
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
                    connection.cancel()
                }
            }

        default:
            break
        }
    }

    private func handleChallenge(_ envelope: PadEnvelopeV2, connection: NWConnection) {
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
            guard let saved = paired.first(where: { $0.deviceId == serverDevId }),
                  let tokenData = Data(hexString: saved.pairingTokenHex),
                  let certFingerprintData = Data(hexString: saved.certFingerprintHex ?? "") else {
                return
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
            DispatchQueue.main.async { self.checkPairedStatus() }

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
                connection.cancel()
                return
            }

            DispatchQueue.main.async {
                self.isConnected = true
                self.isAuthenticated = true
                self.statusText = "Terhubung ke Mac (TLS 1.3 Terautentikasi)"
            }
            PadLog.network("iPad: reconnect authentication complete and active")
        }
    }

    private func handlePairingComplete(_ envelope: PadEnvelopeV2) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.isAuthenticated = true
            self.statusText = "Terhubung ke Mac (Pairing Selesai)"
            self.checkPairedStatus()
        }
        PadLog.network("iPad: pairing complete and connection active")
    }

    private func retryConnection() {
        guard let endpoint = lastEndpoint else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.connection == nil else { return }
            let paired = PadKeychainStore.shared.loadPairedDevices()
            if let saved = paired.first, let fingerprint = saved.certFingerprintHex {
                self.statusText = "Mencoba menghubungkan kembali..."
                self.connectWithTLS(to: endpoint, pinnedFingerprintHex: fingerprint, mode: "reconnect")
            }
        }
    }
}
