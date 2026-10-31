import AppKit
import CoreGraphics
import Foundation

final class InputEventController {
    private var cursorLocation: CGPoint?
    private var leftButtonIsDown = false
    private var rightButtonIsDown = false
    private var buttonReleaseWatchdog: DispatchWorkItem?

    private let pointerSensitivity: CGFloat = 1.8
    private let scrollSensitivity: CGFloat = 2.2
    private let maximumButtonHoldDuration: TimeInterval = 12

    // Diagnostics only. `handle(_:)` runs serially on MacServer's inputQueue,
    // so this is never touched concurrently.
    private let postedRate = PadRateCounter(label: "Mac pointer posted")

    var hasAccessibilityPermission: Bool {
        CGPreflightPostEventAccess()
    }

    func requestAccessibilityPermission() -> Bool {
        CGRequestPostEventAccess()
    }

    func handle(_ command: PadCommand) {
        switch command.type {
        case .move:
            moveCursor(dx: command.dx ?? 0, dy: command.dy ?? 0)
        case .scroll:
            scroll(dx: command.dx ?? 0, dy: command.dy ?? 0)
        case .click:
            guard let button = command.button else { return }
            click(button)
        case .buttonDown:
            guard let button = command.button else { return }
            mouseButton(button, isDown: true)
        case .buttonUp:
            guard let button = command.button else { return }
            mouseButton(button, isDown: false)
        case .gesture:
            guard let direction = command.gestureDirection else { return }
            releaseAllButtons()
            _ = performGesture(direction)
        }
    }

    /// Releases any held mouse button. Called on disconnect and before a new click
    /// so a lost TCP packet cannot leave the Mac stuck in a right/left-drag state.
    func releaseAllButtons() {
        buttonReleaseWatchdog?.cancel()
        buttonReleaseWatchdog = nil

        let location = cursorLocation ?? currentQuartzLocation()
        if leftButtonIsDown {
            _ = postMouseEvent(type: .leftMouseUp, button: .left, at: location)
        }
        if rightButtonIsDown {
            _ = postMouseEvent(type: .rightMouseUp, button: .right, at: location)
        }

        leftButtonIsDown = false
        rightButtonIsDown = false
    }

    private func moveCursor(dx: Double, dy: Double) {
        guard hasAccessibilityPermission else { return }

        let current = cursorLocation ?? currentQuartzLocation()
        let next = CGPoint(
            x: current.x + CGFloat(dx) * pointerSensitivity,
            y: current.y + CGFloat(dy) * pointerSensitivity
        )
        cursorLocation = next

        let eventType: CGEventType
        let button: CGMouseButton
        if leftButtonIsDown {
            eventType = .leftMouseDragged
            button = .left
        } else if rightButtonIsDown {
            eventType = .rightMouseDragged
            button = .right
        } else {
            eventType = .mouseMoved
            button = .left
        }

        if postMouseEvent(type: eventType, button: button, at: next) {
            postedRate.tick()
        }
    }

    private func click(_ button: PadMouseButton) {
        guard hasAccessibilityPermission else { return }

        // Normalize state before a click. This prevents a stale button-down state
        // from turning subsequent pointer movement into a drag.
        releaseAllButtons()
        mouseButton(button, isDown: true)
        mouseButton(button, isDown: false)
    }

    private func mouseButton(_ button: PadMouseButton, isDown: Bool) {
        guard hasAccessibilityPermission else {
            if !isDown { clearButtonState(button) }
            return
        }

        let cgButton: CGMouseButton = button == .left ? .left : .right
        let eventType: CGEventType

        if button == .left {
            eventType = isDown ? .leftMouseDown : .leftMouseUp
        } else {
            eventType = isDown ? .rightMouseDown : .rightMouseUp
        }

        let location = cursorLocation ?? currentQuartzLocation()
        // Pin the drag start point at mouse-down. The next move event must be
        // relative to this exact location, not a fresh NSEvent.mouseLocation read.
        cursorLocation = location
        guard postMouseEvent(type: eventType, button: cgButton, at: location) else {
            if !isDown { clearButtonState(button) }
            return
        }

        if button == .left {
            leftButtonIsDown = isDown
        } else {
            rightButtonIsDown = isDown
        }

        if isDown {
            armButtonReleaseWatchdog()
        } else if !leftButtonIsDown && !rightButtonIsDown {
            buttonReleaseWatchdog?.cancel()
            buttonReleaseWatchdog = nil
        }
    }

    private func clearButtonState(_ button: PadMouseButton) {
        if button == .left { leftButtonIsDown = false }
        else { rightButtonIsDown = false }
        if !leftButtonIsDown && !rightButtonIsDown {
            buttonReleaseWatchdog?.cancel()
            buttonReleaseWatchdog = nil
        }
    }

    private func armButtonReleaseWatchdog() {
        buttonReleaseWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.releaseAllButtons()
        }
        buttonReleaseWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumButtonHoldDuration, execute: work)
    }

    private func scroll(dx: Double, dy: Double) {
        guard hasAccessibilityPermission else { return }

        let vertical = Int32(max(-2_000, min(2_000, (-dy * scrollSensitivity).rounded())))
        let horizontal = Int32(max(-2_000, min(2_000, (dx * scrollSensitivity).rounded())))
        guard vertical != 0 || horizontal != 0 else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    /// Posts a system shortcut (Mission Control / App Exposé / Spaces).
    ///
    /// These are "symbolic hot keys" matched by WindowServer *before* an
    /// event reaches any app's session event stream, at the HID event tap
    /// stage — so all four events post to `.cghidEventTap` (same tap the
    /// mouse events in this file already use successfully), not
    /// `.cgSessionEventTap`.
    ///
    /// The arrow events must also carry `.maskSecondaryFn` alongside
    /// `.maskControl`. Arrow keys belong to macOS's function-key group, so
    /// real hardware arrow events always set that flag, and the stored
    /// hotkey binding records it: Mission Control is persisted in
    /// com.apple.symbolichotkeys as modifier mask 0x840000
    /// (maskControl | maskSecondaryFn), not 0x40000. WindowServer matches
    /// the full modifier mask, so sending Control alone matches nothing and
    /// the event falls through to the focused app as a plain arrow key.
    ///
    /// `true` confirms the Quartz events were created and posted, not that
    /// macOS actually displayed the requested system UI.
    @discardableResult
    func performGesture(_ direction: PadGestureDirection) -> Bool {
        guard hasAccessibilityPermission else { return false }

        let key = "gestureAction.\(direction.rawValue)"
        let fallback = PadSystemAction.defaultAction(for: direction)
        let savedValue = UserDefaults.standard.string(forKey: key) ?? fallback.rawValue
        guard let action = PadSystemAction(rawValue: savedValue),
              let shortcut = keyboardShortcut(for: action) else { return false }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let controlKeyCode: CGKeyCode = 59 // kVK_Control (left Control)
        guard
            let controlDown = CGEvent(keyboardEventSource: source, virtualKey: controlKeyCode, keyDown: true),
            let arrowDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut, keyDown: true),
            let arrowUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut, keyDown: false),
            let controlUp = CGEvent(keyboardEventSource: source, virtualKey: controlKeyCode, keyDown: false)
        else { return false }

        // Flags are computed at creation time from the source's modifier
        // state at that instant, not updated retroactively — set them
        // explicitly on every event rather than relying on posting order.
        let chordFlags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        controlDown.flags = .maskControl
        arrowDown.flags = chordFlags
        arrowUp.flags = chordFlags
        controlUp.flags = []

        let chordGap: UInt32 = 15_000 // 15ms, mirrors a human hold-then-press

        controlDown.post(tap: .cghidEventTap)
        usleep(chordGap)
        arrowDown.post(tap: .cghidEventTap)
        usleep(chordGap)
        arrowUp.post(tap: .cghidEventTap)
        usleep(chordGap)
        controlUp.post(tap: .cghidEventTap)
        PadLog.gesture("Mac: posted Control+Fn+\(direction.rawValue) chord (action=\(action.rawValue)), flags=\(chordFlags.rawValue)")
        return true
    }

    private func keyboardShortcut(for action: PadSystemAction) -> CGKeyCode? {
        switch action {
        case .missionControl: return 126 // Control + Up
        case .appExpose: return 125      // Control + Down
        case .previousDesktop: return 123
        case .nextDesktop: return 124
        case .disabled: return nil
        }
    }

    @discardableResult
    private func postMouseEvent(type: CGEventType, button: CGMouseButton, at point: CGPoint) -> Bool {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func currentQuartzLocation() -> CGPoint {
        let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        let mainScreenHeight = primaryScreen?.frame.height ?? 900
        let appKitPoint = NSEvent.mouseLocation
        return CGPoint(x: appKitPoint.x, y: mainScreenHeight - appKitPoint.y)
    }
}
