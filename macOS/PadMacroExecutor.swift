import AppKit
import CoreGraphics
import Foundation

/// Executes macro step sequences sequentially with safety boundaries, cancellation, and timeout.
/// Runs on its own serial queue (`id.evonex.evopad.macro`) so it never blocks pointer or keyboard queues.
final class PadMacroExecutor {
    private let macroQueue = DispatchQueue(label: "id.evonex.evopad.macro", qos: .userInitiated)
    private let keyboardController: PadKeyboardController

    private var activeMacroId: String?
    private var isCancelled = false
    private var macroTimeoutWorkItem: DispatchWorkItem?

    private let maxMacroDurationSeconds: TimeInterval = 15.0

    init(keyboardController: PadKeyboardController) {
        self.keyboardController = keyboardController
    }

    /// Executes a macro sequence consisting of discrete actions (shortcut, key, text, delay, launchApp).
    func executeMacro(
        macroId: String,
        steps: [PadMacroStepV2],
        completion: @escaping (Bool, PadErrorCodeV2?, String) -> Void
    ) {
        guard !steps.isEmpty else {
            completion(false, .invalidPayload, "Langkah macro tidak boleh kosong")
            return
        }

        guard steps.count <= PadProtocol.maximumMacroSteps else {
            completion(false, .macroLimitExceeded, "Jumlah langkah macro melebihi \(PadProtocol.maximumMacroSteps)")
            return
        }

        macroQueue.async { [weak self] in
            guard let self else { return }

            // Cancel any previously executing macro cleanly
            self.cancelCurrentMacroInternal()

            self.activeMacroId = macroId
            self.isCancelled = false

            // Arm global macro watchdog (15 seconds max execution duration)
            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self else { return }
                PadLog.keyboard("Mac: macro \(macroId) timed out after \(self.maxMacroDurationSeconds)s")
                self.cancelCurrentMacroInternal()
            }
            self.macroTimeoutWorkItem = timeoutWork
            self.macroQueue.asyncAfter(deadline: .now() + self.maxMacroDurationSeconds, execute: timeoutWork)

            PadLog.keyboard("Mac: starting macro execution id=\(macroId) steps=\(steps.count)")

            for (index, step) in steps.enumerated() {
                if self.isCancelled {
                    self.cleanupWatchdog()
                    self.keyboardController.releaseAll()
                    DispatchQueue.main.async {
                        completion(false, .macroCancelled, "Macro \(macroId) dibatalkan")
                    }
                    return
                }

                let stepSuccess = self.executeStep(step)
                if !stepSuccess {
                    self.cleanupWatchdog()
                    self.keyboardController.releaseAll()
                    DispatchQueue.main.async {
                        completion(false, .invalidPayload, "Gagal menjalankan langkah ke-\(index + 1) [\(step.action)]")
                    }
                    return
                }
            }

            self.cleanupWatchdog()
            self.activeMacroId = nil

            PadLog.keyboard("Mac: macro \(macroId) completed successfully")
            DispatchQueue.main.async {
                completion(true, nil, "Macro \(macroId) selesai dieksekusi")
            }
        }
    }

    /// Cancels currently executing macro and releases any held keys.
    func cancelCurrentMacro() {
        macroQueue.async { [weak self] in
            self?.cancelCurrentMacroInternal()
        }
    }

    private func cancelCurrentMacroInternal() {
        isCancelled = true
        cleanupWatchdog()
        activeMacroId = nil
        keyboardController.releaseAll()
    }

    private func cleanupWatchdog() {
        macroTimeoutWorkItem?.cancel()
        macroTimeoutWorkItem = nil
    }

    // MARK: - Step Dispatcher

    private func executeStep(_ step: PadMacroStepV2) -> Bool {
        switch step.action.lowercased() {
        case "shortcut":
            guard let key = step.keyCode else { return false }
            let sema = DispatchSemaphore(value: 0)
            var success = false

            keyboardController.executeShortcut(keyCode: key, modifiers: step.modifiers ?? []) { ok, _ in
                success = ok
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 2.0)
            return success

        case "key":
            guard let key = step.keyCode else { return false }
            let sema = DispatchSemaphore(value: 0)
            var success = false

            keyboardController.handleKeyEvent(keyCode: key, phase: .press, modifiers: step.modifiers) { ok, _ in
                success = ok
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 2.0)
            return success

        case "delay":
            let rawDelay = step.delayMs ?? 100
            // Clamp safe delay between 5 ms and 5,000 ms per step
            let safeDelay = max(5, min(5000, rawDelay))
            usleep(UInt32(safeDelay * 1000))
            return true

        case "launchapp":
            guard let target = step.text, !target.isEmpty else { return false }
            return launchApplication(namedOrBundleId: target)

        case "text":
            guard let text = step.text, !text.isEmpty else { return false }
            return typeText(text)

        default:
            PadLog.keyboard("Mac: unsupported macro step action '\(step.action)'")
            return false
        }
    }

    // MARK: - Native App Launch & Text Typing

    private func launchApplication(namedOrBundleId: String) -> Bool {
        let sema = DispatchSemaphore(value: 0)
        var launched = false

        DispatchQueue.main.async {
            let ws = NSWorkspace.shared
            // 1. Try bundle ID lookup
            if let appUrl = ws.urlForApplication(withBundleIdentifier: namedOrBundleId) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                ws.openApplication(at: appUrl, configuration: config) { _, error in
                    launched = (error == nil)
                    sema.signal()
                }
                return
            }

            // 2. Try application name lookup
            let appName = namedOrBundleId.hasSuffix(".app") ? namedOrBundleId : "\(namedOrBundleId).app"
            let searchPaths = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
            for dirPath in searchPaths {
                let appUrl = URL(fileURLWithPath: dirPath).appendingPathComponent(appName)
                if FileManager.default.fileExists(atPath: appUrl.path) {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    ws.openApplication(at: appUrl, configuration: config) { _, error in
                        launched = (error == nil)
                        sema.signal()
                    }
                    return
                }
            }

            sema.signal()
        }

        _ = sema.wait(timeout: .now() + 3.0)
        return launched
    }

    /// Types unicode text via native CGEvent.
    func typeTextExternal(_ text: String) -> Bool {
        return typeText(text)
    }

    private func typeText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        for scalar in text.utf16 {
            var charCode = scalar
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &charCode)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &charCode)

            down.post(tap: .cghidEventTap)
            usleep(6_000)
            up.post(tap: .cghidEventTap)
            usleep(6_000)
        }
        return true
    }
}
