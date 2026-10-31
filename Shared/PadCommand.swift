import Foundation
import Network

enum PadProtocol {
    static let serviceType = "_evopad._tcp"
    static let port: UInt16 = 49321

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
