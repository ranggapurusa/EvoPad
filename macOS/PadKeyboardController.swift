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

    /// Handles system media key events (play/pause, next, previous, volume up/down, mute).
    /// Uses native macOS media key events via NSEvent/CoreGraphics system keys.
    func handleMediaKey(
        _ key: PadMediaControlKey,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard hasAccessibilityPermission else {
            completion(false, "Izin Accessibility macOS belum diberikan")
            return
        }

        keyboardQueue.async { [weak self] in
            guard let self else { return }

            let systemKey: Int32
            switch key {
            case .playPause:
                systemKey = 16 // NX_KEYTYPE_PLAY
            case .nextTrack:
                systemKey = 17 // NX_KEYTYPE_NEXT
            case .previousTrack:
                systemKey = 18 // NX_KEYTYPE_PREVIOUS
            case .volumeUp:
                systemKey = 0  // NX_KEYTYPE_SOUND_UP
            case .volumeDown:
                systemKey = 1  // NX_KEYTYPE_SOUND_DOWN
            case .mute:
                systemKey = 7  // NX_KEYTYPE_MUTE
            }

            self.postAuxiliaryKey(systemKey: systemKey)
            PadLog.keyboard("Mac: posted media key '\(key.rawValue)' (code=\(systemKey))")

            DispatchQueue.main.async {
                completion(true, "Media key '\(key.title)' dieksekusi")
            }
        }
    }

    private func postAuxiliaryKey(systemKey: Int32) {
        func postKey(down: Bool) {
            let flags: NSEvent.ModifierFlags = down ? NSEvent.ModifierFlags(rawValue: 0xa00) : NSEvent.ModifierFlags(rawValue: 0xb00)
            let data1 = Int((systemKey << 16) | (down ? 0xa00 : 0xb00))

            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8, // 8 = media keys
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }

        postKey(down: true)
        usleep(15_000)
        postKey(down: false)
    }

    /// Handles discrete system control actions (Lock Screen, Sleep, Screenshot, App Launch).
    func handleSystemAction(
        _ action: PadSystemControlAction,
        targetApp: String? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        keyboardQueue.async { [weak self] in
            guard let self else { return }

            switch action {
            case .lockScreen:
                // Cmd + Ctrl + Q or SACLockScreenImmediate
                DispatchQueue.main.async {
                    _ = NSWorkspace.shared
                    // Use macOS system command via Process/AppleScript or shortcut
                    let process = Process()
                    process.launchPath = "/usr/bin/pmset"
                    process.arguments = ["displaysleepnow"]
                    try? process.run()
                    completion(true, "Layar Mac berhasil dikunci")
                }

            case .sleep:
                DispatchQueue.main.async {
                    let script = NSAppleScript(source: "tell application \"Finder\" to sleep")
                    var error: NSDictionary?
                    script?.executeAndReturnError(&error)
                    if error == nil {
                        completion(true, "Mac masuk ke mode Sleep")
                    } else {
                        // Fallback pmset sleepnow
                        let process = Process()
                        process.launchPath = "/usr/bin/pmset"
                        process.arguments = ["sleepnow"]
                        try? process.run()
                        completion(true, "Perintah Sleep dikirim")
                    }
                }

            case .screenshot:
                // Cmd + Shift + 4 (interactive) or Cmd + Shift + 3 (fullscreen)
                self.executeShortcut(keyCode: 20, modifiers: [.cmd, .shift]) { ok, msg in
                    completion(ok, ok ? "Tangkapan layar aktif" : msg)
                }

            case .launchApp:
                guard let target = targetApp, !target.isEmpty else {
                    DispatchQueue.main.async { completion(false, "Nama aplikasi tidak boleh kosong") }
                    return
                }

                DispatchQueue.main.async {
                    let ws = NSWorkspace.shared
                    if let appUrl = ws.urlForApplication(withBundleIdentifier: target) {
                        let config = NSWorkspace.OpenConfiguration()
                        config.activates = true
                        ws.openApplication(at: appUrl, configuration: config) { _, error in
                            completion(error == nil, error == nil ? "Aplikasi \(target) dibuka" : "Gagal membuka \(target)")
                        }
                        return
                    }

                    let appName = target.hasSuffix(".app") ? target : "\(target).app"
                    let searchPaths = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
                    for dirPath in searchPaths {
                        let appUrl = URL(fileURLWithPath: dirPath).appendingPathComponent(appName)
                        if FileManager.default.fileExists(atPath: appUrl.path) {
                            let config = NSWorkspace.OpenConfiguration()
                            config.activates = true
                            ws.openApplication(at: appUrl, configuration: config) { _, error in
                                completion(error == nil, error == nil ? "Aplikasi \(target) dibuka" : "Gagal membuka \(target)")
                            }
                            return
                        }
                    }

                    completion(false, "Aplikasi '\(target)' tidak ditemukan")
                }
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
