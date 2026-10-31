import Foundation
import os

/// Structured diagnostic logging for the 4-finger gesture pipeline and
/// pointer performance. View with Console.app (subsystem "id.evonex.evopad")
/// or `log stream --predicate 'subsystem == "id.evonex.evopad"'`.
enum PadLog {
    private static let gestureLogger = Logger(subsystem: "id.evonex.evopad", category: "gesture")
    private static let networkLogger = Logger(subsystem: "id.evonex.evopad", category: "network")
    private static let pointerLogger = Logger(subsystem: "id.evonex.evopad", category: "pointer")

    static func gesture(_ message: String) {
        gestureLogger.debug("\(message)")
    }

    static func network(_ message: String) {
        networkLogger.debug("\(message)")
    }

    static func pointer(_ message: String) {
        pointerLogger.debug("\(message)")
    }
}

/// Counts events and logs a rate once per second. Not thread-safe — call
/// `tick()` only from one fixed queue/thread per instance.
final class PadRateCounter {
    private let label: String
    private var count = 0
    private var windowStart = DispatchTime.now().uptimeNanoseconds

    init(label: String) {
        self.label = label
    }

    func tick() {
        count += 1
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now &- windowStart
        guard elapsed >= 1_000_000_000 else { return }

        let hz = Double(count) / (Double(elapsed) / 1_000_000_000)
        PadLog.pointer("\(label): \(Int(hz.rounded())) Hz")
        count = 0
        windowStart = now
    }
}
