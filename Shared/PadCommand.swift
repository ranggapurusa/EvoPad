import Foundation
import Network
import Security

enum PadProtocol {
    static let serviceType = "_evopad._tcp"
    static let port: UInt16 = 49321
    static let currentVersion = 2
    static let minimumSupportedVersion = 1
    static let maximumFrameBytes = 16_384
    static let maximumTextInputBytes = 512
    static let maximumMacroSteps = 24

    /// TLS 1.3 parameters for Mac Server using SecIdentity. Plaintext is strictly forbidden.
    static func tlsServerParameters(secIdentity: SecIdentity) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)

        if let identity = sec_identity_create(secIdentity) {
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
        }

        return NWParameters(tls: tls, tcp: tcp)
    }

    /// TLS 1.3 parameters for iPad Client with pinned certificate fingerprint verification.
    /// Plaintext is strictly forbidden.
    static func tlsClientParameters(
        pinnedFingerprintHex: String,
        verifyQueue: DispatchQueue
    ) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)

        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { (_, secTrust, complete) in
                let isValid = PadCertificateVerifier.verifyServerCertificate(
                    trust: sec_trust_copy_ref(secTrust).takeRetainedValue(),
                    pinnedFingerprintHex: pinnedFingerprintHex
                )
                complete(isValid)
            },
            verifyQueue
        )

        return NWParameters(tls: tls, tcp: tcp)
    }
}

enum PadCommandType: String, Codable {
    case move
    case scroll
    case click
    case buttonDown
    case buttonUp
    case gesture
}

enum PadMouseButton: String, Codable {
    case left
    case right
}

enum PadGestureDirection: String, Codable, CaseIterable, Identifiable {
    case up
    case down
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return "Swipe 4 jari ke atas"
        case .down: return "Swipe 4 jari ke bawah"
        case .left: return "Swipe 4 jari ke kiri"
        case .right: return "Swipe 4 jari ke kanan"
        }
    }
}

enum PadSystemAction: String, Codable, CaseIterable, Identifiable {
    case missionControl
    case appExpose
    case previousDesktop
    case nextDesktop
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .previousDesktop: return "Desktop sebelumnya"
        case .nextDesktop: return "Desktop berikutnya"
        case .disabled: return "Nonaktif"
        }
    }

    var shortcutDescription: String {
        switch self {
        case .missionControl: return "Control + ↑"
        case .appExpose: return "Control + ↓"
        case .previousDesktop: return "Control + ←"
        case .nextDesktop: return "Control + →"
        case .disabled: return "Tidak ada aksi"
        }
    }

    static func defaultAction(for direction: PadGestureDirection) -> PadSystemAction {
        switch direction {
        case .up: return .missionControl
        case .down: return .appExpose
        case .left: return .previousDesktop
        case .right: return .nextDesktop
        }
    }
}

struct PadCommand: Codable {
    let type: PadCommandType
    let dx: Double?
    let dy: Double?
    let button: PadMouseButton?
    let gestureDirection: PadGestureDirection?

    init(
        type: PadCommandType,
        dx: Double? = nil,
        dy: Double? = nil,
        button: PadMouseButton? = nil,
        gestureDirection: PadGestureDirection? = nil
    ) {
        self.type = type
        self.dx = dx
        self.dy = dy
        self.button = button
        self.gestureDirection = gestureDirection
    }

    static func move(dx: Double, dy: Double) -> PadCommand {
        PadCommand(type: .move, dx: dx, dy: dy)
    }

    static func scroll(dx: Double, dy: Double) -> PadCommand {
        PadCommand(type: .scroll, dx: dx, dy: dy)
    }

    static func click(_ button: PadMouseButton) -> PadCommand {
        PadCommand(type: .click, button: button)
    }

    static func buttonDown(_ button: PadMouseButton) -> PadCommand {
        PadCommand(type: .buttonDown, button: button)
    }

    static func buttonUp(_ button: PadMouseButton) -> PadCommand {
        PadCommand(type: .buttonUp, button: button)
    }

    static func gesture(_ direction: PadGestureDirection) -> PadCommand {
        PadCommand(type: .gesture, gestureDirection: direction)
    }
}

/// A lightweight acknowledgement sent from Mac Helper back to the iPad.
struct PadAcknowledgement: Codable {
    let kind: String
    let direction: PadGestureDirection
    let accepted: Bool
    let message: String

    static func gesture(
        direction: PadGestureDirection,
        accepted: Bool,
        message: String
    ) -> PadAcknowledgement {
        PadAcknowledgement(
            kind: "gestureAck",
            direction: direction,
            accepted: accepted,
            message: message
        )
    }
}

// MARK: - Protocol V2 Foundation (M1 + M2 Security)

enum PadMessageTypeV2: String, Codable {
    // Handshake & Authentication & Pairing (M2)
    case hello
    case challenge
    case auth
    case authResult
    case pairingCommit
    case pairingComplete

    // Input & Productivity Commands
    case pointerEvent
    case gestureEvent
    case keyboardEvent
    case textInput
    case shortcutExecute
    case mediaControl
    case systemControl
    case macroExecute

    // Responses
    case actionAck
    case error
}

enum PadErrorCodeV2: String, Codable {
    case unauthenticated = "UNAUTHENTICATED"
    case authFailed = "AUTH_FAILED"
    case rateLimited = "RATE_LIMITED"
    case unsupportedVersion = "UNSUPPORTED_VERSION"
    case frameTooLarge = "FRAME_TOO_LARGE"
    case invalidPayload = "INVALID_PAYLOAD"
    case permissionDenied = "PERMISSION_DENIED"
    case unsupportedAction = "UNSUPPORTED_ACTION"
    case macroCancelled = "MACRO_CANCELLED"
    case macroLimitExceeded = "MACRO_LIMIT_EXCEEDED"
    case pairingExpired = "PAIRING_EXPIRED"
    case pairingRejected = "PAIRING_REJECTED"
    case certMismatch = "CERT_MISMATCH"
}

enum PadKeyPhaseV2: String, Codable {
    case down
    case up
    case press
}

enum PadModifierFlagV2: String, Codable, Hashable {
    case cmd
    case shift
    case alt
    case ctrl
    case fn
}

enum PadStandardShortcut: String, Codable, Hashable, CaseIterable, Identifiable {
    case copy = "copy"
    case paste = "paste"
    case cut = "cut"
    case undo = "undo"
    case redo = "redo"
    case selectAll = "selectAll"
    case commandTab = "commandTab"
    case spotlight = "spotlight"
    case missionControl = "missionControl"
    case screenshot = "screenshot"
    case lockScreen = "lockScreen"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return "Salin"
        case .paste: return "Tempel"
        case .cut: return "Potong"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .selectAll: return "Pilih Semua"
        case .commandTab: return "Cmd + Tab"
        case .spotlight: return "Spotlight"
        case .missionControl: return "Mission Control"
        case .screenshot: return "Tangkapan Layar"
        case .lockScreen: return "Kunci Layar"
        }
    }

    var symbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .cut: return "scissors"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .selectAll: return "selection.pin.in.out"
        case .commandTab: return "app.badge"
        case .spotlight: return "magnifyingglass"
        case .missionControl: return "rectangle.3.group"
        case .screenshot: return "camera.viewfinder"
        case .lockScreen: return "lock.fill"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .copy: return 8        // kVK_ANSI_C
        case .paste: return 9       // kVK_ANSI_V
        case .cut: return 7         // kVK_ANSI_X
        case .undo: return 6        // kVK_ANSI_Z
        case .redo: return 6        // kVK_ANSI_Z
        case .selectAll: return 0   // kVK_ANSI_A
        case .commandTab: return 48 // kVK_Tab
        case .spotlight: return 49  // kVK_Space
        case .missionControl: return 126 // kVK_UpArrow
        case .screenshot: return 21 // kVK_ANSI_4
        case .lockScreen: return 12 // kVK_ANSI_Q
        }
    }

    var modifiers: [PadModifierFlagV2] {
        switch self {
        case .copy, .paste, .cut, .undo, .selectAll, .commandTab, .spotlight:
            return [.cmd]
        case .redo, .screenshot:
            return [.cmd, .shift]
        case .missionControl:
            return [.ctrl, .fn]
        case .lockScreen:
            return [.cmd, .ctrl]
        }
    }

    var chordDescription: String {
        switch self {
        case .copy: return "⌘C"
        case .paste: return "⌘V"
        case .cut: return "⌘X"
        case .undo: return "⌘Z"
        case .redo: return "⇧⌘Z"
        case .selectAll: return "⌘A"
        case .commandTab: return "⌘Tab"
        case .spotlight: return "⌘Space"
        case .missionControl: return "⌃↑"
        case .screenshot: return "⇧⌘4"
        case .lockScreen: return "⌃⌘Q"
        }
    }
}

// MARK: - Standard macOS Virtual Key Codes (M3.2)

enum PadVirtualKey: UInt16, CaseIterable {
    // Alphanumeric - Letters
    case a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, x = 7
    case c = 8, v = 9, b = 11, q = 12, w = 13, e = 14, r = 15
    case y = 16, t = 17, one = 18, two = 19, three = 20, four = 21
    case six = 22, five = 23, equal = 24, nine = 25, seven = 26
    case minus = 27, eight = 28, zero = 29, rightBracket = 30
    case o = 31, u = 32, leftBracket = 33, i = 34, p = 35
    case l = 37, j = 38, quote = 39, k = 40, semicolon = 41
    case backslash = 42, comma = 43, slash = 44, n = 45, m = 46
    case period = 47, grave = 50

    // Whitespace & Control
    case tab = 48
    case space = 49
    case delete = 51
    case escape = 53
    case returnKey = 36

    // Navigation & Editing
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126
    case pageUp = 116
    case pageDown = 121
    case home = 115
    case end = 119
    case forwardDelete = 117

    // Function Keys
    case f1 = 122, f2 = 120, f3 = 99, f4 = 118, f5 = 96, f6 = 97
    case f7 = 98, f8 = 100, f9 = 101, f10 = 109, f11 = 103, f12 = 111

    // Modifiers (as standalone keys)
    case command = 55
    case shift = 56
    case option = 58
    case control = 59
    case capsLock = 57
}

struct PadMacroStepV2: Codable, Equatable {
    let action: String
    let keyCode: UInt16?
    let modifiers: [PadModifierFlagV2]?
    let text: String?
    let delayMs: Int?
}

struct PadPayloadV2: Codable, Equatable {
    // Pointer & Gesture
    var pointerAction: PadCommandType?
    var dx: Double?
    var dy: Double?
    var button: PadMouseButton?
    var gestureDirection: PadGestureDirection?

    // Keyboard & Shortcut
    var keyCode: UInt16?
    var keyPhase: PadKeyPhaseV2?
    var modifiers: [PadModifierFlagV2]?
    var rawModifierMask: UInt64?

    // Text Input
    var text: String?

    // Media & System Control
    var mediaKey: String?
    var systemAction: String?

    // Macro
    var macroId: String?
    var steps: [PadMacroStepV2]?

    // Auth & Pairing (M2)
    var clientDeviceId: String?
    var serverDeviceId: String?
    var deviceName: String?
    var pairingId: String?
    var nonce: String?
    var hmac: String?
    var authMode: String? // "pairing" or "reconnect"
    var pairingToken: String?
    var certFingerprint: String?
    var status: String?
    var message: String?
}

struct PadAcknowledgementV2: Codable, Equatable {
    let requestId: String
    let accepted: Bool
    let message: String?
}

struct PadErrorPayloadV2: Codable, Equatable {
    let code: PadErrorCodeV2
    let message: String
    let minVersion: Int?
    let maxVersion: Int?
}

struct PadEnvelopeV2: Codable, Equatable {
    let protocolVersion: Int
    let requestId: String
    let type: PadMessageTypeV2
    let payload: PadPayloadV2?
    let acknowledgement: PadAcknowledgementV2?
    let error: PadErrorPayloadV2?

    init(
        protocolVersion: Int = PadProtocol.currentVersion,
        requestId: String = UUID().uuidString,
        type: PadMessageTypeV2,
        payload: PadPayloadV2? = nil,
        acknowledgement: PadAcknowledgementV2? = nil,
        error: PadErrorPayloadV2? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestId = requestId
        self.type = type
        self.payload = payload
        self.acknowledgement = acknowledgement
        self.error = error
    }

    static func ack(requestId: String, accepted: Bool, message: String? = nil) -> PadEnvelopeV2 {
        PadEnvelopeV2(
            requestId: requestId,
            type: .actionAck,
            acknowledgement: PadAcknowledgementV2(requestId: requestId, accepted: accepted, message: message)
        )
    }

    static func error(
        requestId: String,
        code: PadErrorCodeV2,
        message: String,
        minVersion: Int? = nil,
        maxVersion: Int? = nil
    ) -> PadEnvelopeV2 {
        PadEnvelopeV2(
            requestId: requestId,
            type: .error,
            error: PadErrorPayloadV2(code: code, message: message, minVersion: minVersion, maxVersion: maxVersion)
        )
    }

    static func shortcut(
        _ shortcut: PadStandardShortcut,
        requestId: String = UUID().uuidString
    ) -> PadEnvelopeV2 {
        PadEnvelopeV2(
            requestId: requestId,
            type: .shortcutExecute,
            payload: PadPayloadV2(
                keyCode: shortcut.keyCode,
                keyPhase: .press,
                modifiers: shortcut.modifiers,
                systemAction: shortcut.rawValue
            )
        )
    }

    static func customShortcut(
        keyCode: UInt16,
        modifiers: [PadModifierFlagV2],
        requestId: String = UUID().uuidString
    ) -> PadEnvelopeV2 {
        PadEnvelopeV2(
            requestId: requestId,
            type: .shortcutExecute,
            payload: PadPayloadV2(
                keyCode: keyCode,
                keyPhase: .press,
                modifiers: modifiers
            )
        )
    }

    static func keyEvent(
        keyCode: UInt16,
        phase: PadKeyPhaseV2,
        modifiers: [PadModifierFlagV2]? = nil,
        requestId: String = UUID().uuidString
    ) -> PadEnvelopeV2 {
        PadEnvelopeV2(
            requestId: requestId,
            type: .keyboardEvent,
            payload: PadPayloadV2(
                keyCode: keyCode,
                keyPhase: phase,
                modifiers: modifiers
            )
        )
    }

    /// Validates payload constraints for incoming V2 messages.
    func validatePayload() -> PadErrorPayloadV2? {
        guard !requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PadErrorPayloadV2(code: .invalidPayload, message: "requestId tidak boleh kosong", minVersion: nil, maxVersion: nil)
        }

        switch type {
        case .pointerEvent:
            guard let action = payload?.pointerAction else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "pointerEvent membutuhkan pointerAction", minVersion: nil, maxVersion: nil)
            }
            switch action {
            case .move, .scroll:
                guard let dx = payload?.dx, let dy = payload?.dy, dx.isFinite, dy.isFinite else {
                    return PadErrorPayloadV2(code: .invalidPayload, message: "dx/dy tidak valid", minVersion: nil, maxVersion: nil)
                }
            case .click, .buttonDown, .buttonUp:
                guard payload?.button != nil else {
                    return PadErrorPayloadV2(code: .invalidPayload, message: "button wajib diisi", minVersion: nil, maxVersion: nil)
                }
            case .gesture:
                return PadErrorPayloadV2(code: .invalidPayload, message: "Gunakan gestureEvent untuk gesture", minVersion: nil, maxVersion: nil)
            }
        case .gestureEvent:
            guard payload?.gestureDirection != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "gestureDirection wajib diisi", minVersion: nil, maxVersion: nil)
            }
        case .keyboardEvent:
            guard payload?.keyCode != nil, payload?.keyPhase != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "keyCode dan keyPhase wajib diisi", minVersion: nil, maxVersion: nil)
            }
        case .textInput:
            guard let text = payload?.text, !text.isEmpty, text.utf8.count <= PadProtocol.maximumTextInputBytes else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "text kosong atau melebihi \(PadProtocol.maximumTextInputBytes) bytes", minVersion: nil, maxVersion: nil)
            }
        case .shortcutExecute:
            guard payload?.keyCode != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "keyCode wajib diisi untuk shortcutExecute", minVersion: nil, maxVersion: nil)
            }
        case .mediaControl:
            guard let key = payload?.mediaKey, !key.isEmpty else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "mediaKey wajib diisi", minVersion: nil, maxVersion: nil)
            }
        case .systemControl:
            guard let action = payload?.systemAction, !action.isEmpty else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "systemAction wajib diisi", minVersion: nil, maxVersion: nil)
            }
        case .macroExecute:
            guard let steps = payload?.steps, !steps.isEmpty else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "steps wajib diisi untuk macroExecute", minVersion: nil, maxVersion: nil)
            }
            if steps.count > PadProtocol.maximumMacroSteps {
                return PadErrorPayloadV2(code: .macroLimitExceeded, message: "Jumlah langkah macro melebihi \(PadProtocol.maximumMacroSteps)", minVersion: nil, maxVersion: nil)
            }
        case .actionAck:
            guard acknowledgement != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "acknowledgement wajib diisi untuk actionAck", minVersion: nil, maxVersion: nil)
            }
        case .error:
            guard error != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "error payload wajib diisi untuk pesan error", minVersion: nil, maxVersion: nil)
            }
        case .hello:
            guard payload?.clientDeviceId != nil, payload?.nonce != nil, payload?.authMode != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "clientDeviceId, nonce, dan authMode wajib diisi untuk hello", minVersion: nil, maxVersion: nil)
            }
        case .challenge:
            guard payload?.serverDeviceId != nil, payload?.nonce != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "serverDeviceId dan nonce wajib diisi untuk challenge", minVersion: nil, maxVersion: nil)
            }
        case .auth:
            guard payload?.hmac != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "hmac wajib diisi untuk auth", minVersion: nil, maxVersion: nil)
            }
        case .authResult:
            guard payload?.status != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "status wajib diisi untuk authResult", minVersion: nil, maxVersion: nil)
            }
        case .pairingCommit:
            guard payload?.hmac != nil, payload?.pairingId != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "hmac dan pairingId wajib diisi untuk pairingCommit", minVersion: nil, maxVersion: nil)
            }
        case .pairingComplete:
            guard payload?.status != nil else {
                return PadErrorPayloadV2(code: .invalidPayload, message: "status wajib diisi untuk pairingComplete", minVersion: nil, maxVersion: nil)
            }
        }
        return nil
    }
}

// MARK: - Dual Protocol Decoder & Frame Buffer (V1 / V2)

enum PadDecodedIncomingMessage {
    case v1Command(PadCommand)
    case v2Envelope(PadEnvelopeV2)
}

enum PadDecodedServerResponse {
    case v1Ack(PadAcknowledgement)
    case v2Envelope(PadEnvelopeV2)
}

enum PadProtocolDecodeError: Error, Equatable {
    case frameTooLarge(Int)
    case emptyFrame
    case malformedJSON
    case unsupportedVersion(version: Int, requestId: String?)
    case invalidPayload(requestId: String, error: PadErrorPayloadV2)
}

private struct PadVersionProbe: Decodable {
    let protocolVersion: Int?
    let v: Int?
    let requestId: String?
    let id: String?

    var resolvedVersion: Int? { protocolVersion ?? v }
    var resolvedRequestId: String? { requestId ?? id }
}

enum PadFrameCodec {
    enum LineExtractionResult {
        case line(Data)
        case needMoreData
        case frameTooLarge(Int)
    }

    static func popNextFrame(from buffer: inout Data, maxBytes: Int = PadProtocol.maximumFrameBytes) -> LineExtractionResult {
        if let newline = buffer.firstIndex(of: 0x0A) {
            let length = buffer.distance(from: buffer.startIndex, to: newline)
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if length > maxBytes {
                return .frameTooLarge(length)
            }
            return .line(line)
        }
        if buffer.count > maxBytes {
            let offendingSize = buffer.count
            buffer.removeAll(keepingCapacity: false)
            return .frameTooLarge(offendingSize)
        }
        return .needMoreData
    }

    static func decodeClientFrame(_ line: Data) -> Result<PadDecodedIncomingMessage, PadProtocolDecodeError> {
        guard !line.isEmpty else { return .failure(.emptyFrame) }
        guard line.count <= PadProtocol.maximumFrameBytes else {
            return .failure(.frameTooLarge(line.count))
        }

        let decoder = JSONDecoder()

        if let probe = try? decoder.decode(PadVersionProbe.self, from: line),
           let version = probe.resolvedVersion {
            guard version == PadProtocol.currentVersion else {
                return .failure(.unsupportedVersion(version: version, requestId: probe.resolvedRequestId))
            }
            guard let envelope = try? decoder.decode(PadEnvelopeV2.self, from: line) else {
                return .failure(.malformedJSON)
            }
            if let validationError = envelope.validatePayload() {
                return .failure(.invalidPayload(requestId: envelope.requestId, error: validationError))
            }
            return .success(.v2Envelope(envelope))
        }

        if let v1 = try? decoder.decode(PadCommand.self, from: line) {
            return .success(.v1Command(v1))
        }

        return .failure(.malformedJSON)
    }

    static func decodeServerFrame(_ line: Data) -> Result<PadDecodedServerResponse, PadProtocolDecodeError> {
        guard !line.isEmpty else { return .failure(.emptyFrame) }
        guard line.count <= PadProtocol.maximumFrameBytes else {
            return .failure(.frameTooLarge(line.count))
        }

        let decoder = JSONDecoder()

        if let probe = try? decoder.decode(PadVersionProbe.self, from: line),
           let version = probe.resolvedVersion {
            guard version == PadProtocol.currentVersion else {
                return .failure(.unsupportedVersion(version: version, requestId: probe.resolvedRequestId))
            }
            guard let envelope = try? decoder.decode(PadEnvelopeV2.self, from: line) else {
                return .failure(.malformedJSON)
            }
            if let validationError = envelope.validatePayload() {
                return .failure(.invalidPayload(requestId: envelope.requestId, error: validationError))
            }
            return .success(.v2Envelope(envelope))
        }

        if let v1Ack = try? decoder.decode(PadAcknowledgement.self, from: line) {
            return .success(.v1Ack(v1Ack))
        }

        return .failure(.malformedJSON)
    }
}
