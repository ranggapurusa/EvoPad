import AppKit
import CoreGraphics
import Foundation

/// Executes macro step sequences sequentially with safety boundaries, cancellation, and timeout.
/// Runs on its own serial queue (`id.evonex.evopad.macro`) so it never blocks pointer or keyboard queues.
final class PadMacroExecutor {
    private let macroQueue = DispatchQueue(label: "id.evonex.evopad.macro", qos: .userInitiated)
    private let keyboardController: PadKeyboardController

    private var activeMacroId: String?
    private let cancellationLock = NSLock()
    private var _isCancelled = false
    private var isCancelled: Bool {
        get {
            cancellationLock.lock()
            defer { cancellationLock.unlock() }
            return _isCancelled
        }
        set {
            cancellationLock.lock()
            _isCancelled = newValue
            cancellationLock.unlock()
        }
    }
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
                    completion(false, .macroCancelled, "Macro \(macroId) dibatalkan")
                    return
                }

                let stepSuccess = self.executeStep(step)
                if !stepSuccess {
                    self.cleanupWatchdog()
                    self.keyboardController.releaseAll()
                    if self.isCancelled {
                        completion(false, .macroCancelled, "Macro \(macroId) dibatalkan")
                    } else {
                        completion(false, .invalidPayload, "Gagal menjalankan langkah ke-\(index + 1) [\(step.action)]")
                    }
                    return
                }
            }

            self.cleanupWatchdog()
            self.activeMacroId = nil

            PadLog.keyboard("Mac: macro \(macroId) completed successfully")
            completion(true, nil, "Macro \(macroId) selesai dieksekusi")
        }
    }

    /// Cancels currently executing macro or text input immediately and releases any held keys.
    func cancelCurrentMacro() {
        isCancelled = true
        macroQueue.async { [weak self] in
            self?.cancelCurrentMacroInternal()
        }
    }

    private func cancelCurrentMacroInternal() {
        dispatchPrecondition(condition: .onQueue(macroQueue))
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
            // Clamp safe delay between 5 ms and 5,000 ms per step, sleeping in <=20 ms slices
            // so `cancelCurrentMacro()` / disconnect aborts immediately without blocking `macroQueue`.
            var remainingMs = max(5, min(5000, rawDelay))
            let sliceMs = 20
            while remainingMs > 0 {
                if isCancelled {
                    return false
                }
                let currentSlice = min(sliceMs, remainingMs)
                usleep(UInt32(currentSlice * 1000))
                remainingMs -= currentSlice
            }
            return !isCancelled

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

            // 0. If web URL (http:// or https://), open directly in Google Chrome if installed, else default browser
            if let url = URL(string: namedOrBundleId), (url.scheme == "http" || url.scheme == "https") {
                if let chromeUrl = ws.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    ws.open([url], withApplicationAt: chromeUrl, configuration: config) { _, error in
                        launched = (error == nil)
                        sema.signal()
                    }
                } else {
                    ws.open(url)
                    launched = true
                    sema.signal()
                }
                return
            }

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

    /// Asynchronously types unicode text on `macroQueue` so `inputQueue` (60 Hz pointer stream) is never blocked.
    func executeTextInput(
        _ text: String,
        completion: @escaping (Bool, PadErrorCodeV2?, String) -> Void
    ) {
        guard !text.isEmpty else {
            completion(false, .invalidPayload, "Teks kosong")
            return
        }

        // Clear cancellation flag before queuing so sequential text inputs execute in order,
        // while an immediate `cancelCurrentMacro()` on disconnect can still abort in-flight typing.
        isCancelled = false

        macroQueue.async { [weak self] in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(self.macroQueue))

            if self.isCancelled {
                self.keyboardController.releaseAll()
                completion(false, .macroCancelled, "Input teks dibatalkan")
                return
            }

            let ok = self.typeText(text)
            if self.isCancelled {
                self.keyboardController.releaseAll()
                completion(false, .macroCancelled, "Input teks dibatalkan saat berjalan")
                return
            }

            if ok {
                completion(true, nil, "Teks diketik")
            } else {
                completion(false, .permissionDenied, "Gagal mengetik teks")
            }
        }
    }

    private func typeText(_ text: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(macroQueue))
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        for scalar in text.utf16 {
            if isCancelled {
                return false
            }
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
            if isCancelled {
                return false
            }
            usleep(6_000)
        }
        return true
    }
}
