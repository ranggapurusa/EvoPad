import AppKit
import CoreGraphics
import Foundation

/// Controller for executing keyboard shortcuts and virtual keyboard events on macOS.
/// Runs on a dedicated serial queue so execution never blocks pointer input on `inputQueue`.
final class PadKeyboardController {
    private let keyboardQueue = DispatchQueue(label: "id.evonex.evopad.keyboard", qos: .userInitiated)
    private var heldKeyCodes = Set<CGKeyCode>()
    private var releaseWatchdog: DispatchWorkItem?
    private let watchdogTimeout: TimeInterval = 5.0

    var hasAccessibilityPermission: Bool {
        CGPreflightPostEventAccess()
    }

    /// Executes a keyboard shortcut chord (e.g. Cmd+C, Cmd+Tab, Ctrl+Up, etc.).
    /// Posts modifier down -> key down -> key up -> modifier up with appropriate flags.
    func executeShortcut(
        keyCode: UInt16,
        modifiers: [PadModifierFlagV2],
        completion: @escaping (Bool, String) -> Void
    ) {
        guard hasAccessibilityPermission else {
            completion(false, "Izin Accessibility macOS belum diberikan")
            return
        }

        keyboardQueue.async { [weak self] in
            guard let self else { return }

            guard let source = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion(false, "Gagal membuat CGEventSource") }
                return
            }

            let cgKey = CGKeyCode(keyCode)
            let flags = Self.cgEventFlags(for: modifiers, virtualKey: cgKey)

            // Collect modifier virtual key codes to simulate proper chord down/up
            let modifierKeyCodes = Self.modifierKeyCodes(for: modifiers)

            // 1. Post modifier down events
            for modKey in modifierKeyCodes {
                if let modDown = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: true) {
                    modDown.flags = flags
                    modDown.post(tap: .cghidEventTap)
                    self.heldKeyCodes.insert(modKey)
                }
            }

            let chordDelay: UInt32 = 12_000 // 12 ms inter-event timing
            usleep(chordDelay)

            // 2. Post main key down & up
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cgKey, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cgKey, keyDown: false) {
                keyDown.flags = flags
                keyUp.flags = flags

                keyDown.post(tap: .cghidEventTap)
                self.heldKeyCodes.insert(cgKey)

                usleep(chordDelay)

                keyUp.post(tap: .cghidEventTap)
                self.heldKeyCodes.remove(cgKey)
            } else {
                self.releaseAll()
                DispatchQueue.main.async { completion(false, "Gagal membuat CGEvent untuk keycode \(keyCode)") }
                return
            }

            usleep(chordDelay)

            // 3. Post modifier up events (reverse order)
            for modKey in modifierKeyCodes.reversed() {
                if let modUp = CGEvent(keyboardEventSource: source, virtualKey: modKey, keyDown: false) {
                    modUp.flags = []
                    modUp.post(tap: .cghidEventTap)
                }
                self.heldKeyCodes.remove(modKey)
            }

            self.clearWatchdog()
            PadLog.keyboard("Mac: executed shortcut keyCode=\(keyCode), modifiers=\(modifiers.map(\.rawValue).joined(separator: ","))")

            DispatchQueue.main.async {
                completion(true, "Shortcut keyCode \(keyCode) berhasil dieksekusi")
            }
        }
    }

    /// Handles discrete key press, down, or up events.
    func handleKeyEvent(
        keyCode: UInt16,
        phase: PadKeyPhaseV2,
        modifiers: [PadModifierFlagV2]?,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard hasAccessibilityPermission else {
            completion(false, "Izin Accessibility macOS belum diberikan")
            return
        }

        keyboardQueue.async { [weak self] in
            guard let self else { return }

            guard let source = CGEventSource(stateID: .hidSystemState) else {
                DispatchQueue.main.async { completion(false, "Gagal membuat CGEventSource") }
                return
            }

            let cgKey = CGKeyCode(keyCode)
            let flags = Self.cgEventFlags(for: modifiers ?? [], virtualKey: cgKey)

            switch phase {
            case .down:
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: cgKey, keyDown: true) else {
                    DispatchQueue.main.async { completion(false, "Gagal membuat keyDown") }
                    return
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
                self.heldKeyCodes.insert(cgKey)
                self.armWatchdog()

            case .up:
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: cgKey, keyDown: false) else {
                    DispatchQueue.main.async { completion(false, "Gagal membuat keyUp") }
                    return
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
                self.heldKeyCodes.remove(cgKey)
                if self.heldKeyCodes.isEmpty {
                    self.clearWatchdog()
                }

            case .press:
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: cgKey, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: cgKey, keyDown: false) else {
                    DispatchQueue.main.async { completion(false, "Gagal membuat keyPress") }
                    return
                }
                down.flags = flags
                up.flags = flags

                down.post(tap: .cghidEventTap)
                usleep(10_000)
                up.post(tap: .cghidEventTap)
                self.heldKeyCodes.remove(cgKey)
            }

            DispatchQueue.main.async {
                completion(true, "Key \(keyCode) \(phase.rawValue) dipost")
            }
        }
    }

    /// Releases all currently held keys and modifiers to prevent stuck state on disconnect or timeout.
    func releaseAll() {
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            self.clearWatchdog()
            guard !self.heldKeyCodes.isEmpty else { return }

            guard let source = CGEventSource(stateID: .hidSystemState) else {
                self.heldKeyCodes.removeAll()
                return
            }

            for key in self.heldKeyCodes {
                if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                    up.flags = []
                    up.post(tap: .cghidEventTap)
                }
            }
            self.heldKeyCodes.removeAll()
            PadLog.keyboard("Mac: released all held keyboard keys and modifiers")
        }
    }

    private func armWatchdog() {
        clearWatchdog()
        let work = DispatchWorkItem { [weak self] in
            PadLog.keyboard("Mac: keyboard watchdog triggered; releasing all held keys")
            self?.releaseAll()
        }
        releaseWatchdog = work
        keyboardQueue.asyncAfter(deadline: .now() + watchdogTimeout, execute: work)
    }

    private func clearWatchdog() {
        releaseWatchdog?.cancel()
        releaseWatchdog = nil
    }

    // MARK: - Modifier Mapping

    static func cgEventFlags(for modifiers: [PadModifierFlagV2], virtualKey: CGKeyCode? = nil) -> CGEventFlags {
        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod {
            case .cmd:
                flags.insert(.maskCommand)
            case .shift:
                flags.insert(.maskShift)
            case .alt:
                flags.insert(.maskAlternate)
            case .ctrl:
                flags.insert(.maskControl)
            case .fn:
                flags.insert(.maskSecondaryFn)
            }
        }

        // Arrow keys belong to function-key group in macOS; must carry maskSecondaryFn
        if let key = virtualKey, (key == 123 || key == 124 || key == 125 || key == 126) {
            flags.insert(.maskSecondaryFn)
        }

        return flags
    }

    static func modifierKeyCodes(for modifiers: [PadModifierFlagV2]) -> [CGKeyCode] {
        var keys: [CGKeyCode] = []
        for mod in modifiers {
            switch mod {
            case .ctrl:
                keys.append(59) // kVK_Control
            case .alt:
                keys.append(58) // kVK_Option
            case .shift:
                keys.append(56) // kVK_Shift
            case .cmd:
                keys.append(55) // kVK_Command
            case .fn:
                break // Fn handled via flags
            }
        }
        return keys
    }
}
