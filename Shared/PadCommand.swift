import Foundation
import Network

enum PadProtocol {
    static let serviceType = "_evopad._tcp"
    static let port: UInt16 = 49321
    static let currentVersion = 2
    static let minimumSupportedVersion = 1
    static let maximumFrameBytes = 16_384
    static let maximumTextInputBytes = 512
    static let maximumMacroSteps = 24

    /// Disable Nagle buffering so small pointer packets are sent immediately.
    static func lowLatencyTCPParameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return NWParameters(tls: nil, tcp: tcp)
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
/// `accepted` means the Mac created and posted the Quartz keyboard events;
/// macOS does not expose a callback confirming that a system UI actually opened.
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

// MARK: - Protocol V2 Foundation (M1)

enum PadMessageTypeV2: String, Codable {
    // Handshake & Auth (reserved for M2)
    case hello
    case challenge
    case auth
    case authResult
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
}

enum PadKeyPhaseV2: String, Codable {
    case down
    case up
    case press
}

enum PadModifierFlagV2: String, Codable {
    case cmd
    case shift
    case alt
    case ctrl
    case fn
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

    // Auth / Handshake (prepared for M2)
    var clientDeviceId: String?
    var serverDeviceId: String?
    var nonce: String?
    var hmac: String?
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
        case .hello, .challenge, .auth, .authResult:
            break
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

/// Lightweight version sniffer so we can detect `protocolVersion` (or legacy `"v"`)
/// before deciding between V1 fast-path and V2 envelope decoding.
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

    /// Extracts the next newline-delimited frame while enforcing the 16 KB cap.
    ///// ponytail: single-buffer scan; upgrade to ring buffer only if throughput exceeds 10k msg/s.
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

    /// Decodes a single frame on the Mac side (accepts V1 `PadCommand` or V2 `PadEnvelopeV2`).
    static func decodeClientFrame(_ line: Data) -> Result<PadDecodedIncomingMessage, PadProtocolDecodeError> {
        guard !line.isEmpty else { return .failure(.emptyFrame) }
        guard line.count <= PadProtocol.maximumFrameBytes else {
            return .failure(.frameTooLarge(line.count))
        }

        let decoder = JSONDecoder()

        // Fast-path check: V1 frames never contain "protocolVersion"; only run V2 path when present.
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

    /// Decodes a single frame on the iPad side (accepts V1 `PadAcknowledgement` or V2 `PadEnvelopeV2`).
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
