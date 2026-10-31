# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

EvoPad: an iPad app that turns the iPad into a wireless trackpad/gesture pad for a Mac, plus a macOS helper app that receives the input. Two targets in one Xcode project, communicating over a local-network TCP socket discovered via Bonjour.

- `EvoPad.xcodeproj` — single project, two targets: `EvoPad iPad` (product `EvoPad`, iOS 17+) and `EvoPad Mac` (product `EvoPad Mac`, macOS 14+). No test targets exist.
- `iOS/` — iPad app (SwiftUI + UIKit touch handling).
- `macOS/` — Mac helper app (SwiftUI UI, AppKit/Quartz event posting).
- `Shared/PadCommand.swift` — wire protocol shared by both targets (only file both targets compile).

No Swift Package Manager manifest, no CocoaPods/Carthage — everything is plain Foundation/Network/UIKit/AppKit, no third-party dependencies.

## Build / run

Requires full Xcode (the CLI Command Line Tools alone cannot build this — `xcodebuild` needs `xcode-select -s /Applications/Xcode.app`).

```bash
open EvoPad.xcodeproj
```
Then build/run the `EvoPad iPad` scheme on a real iPad (Simulator has no real multitouch/Bonjour peer) and the `EvoPad Mac` scheme on the Mac. Both must be on the same local network.

There is no CLI test runner, lint config, or CI in this repo — there are no automated tests. Verify changes by running both apps and exercising the trackpad gestures manually.

Required runtime permissions:
- Mac Helper: **System Settings → Privacy & Security → Accessibility** (needed for `CGEvent` posting — `InputEventController.hasAccessibilityPermission`/`requestAccessibilityPermission` wrap `CGPreflightPostEventAccess`/`CGRequestPostEventAccess`).
- Both apps: **Local Network** permission (Bonjour service `_evopad._tcp`, TCP port `49321`, declared in `Shared/PadCommand.swift` as `PadProtocol`).
- iPad: **Settings → Multitasking & Gestures → Four & Five Finger App Switching** should be OFF, or iPadOS system gestures compete with EvoPad's own 4-finger swipe recognition (see `touchesCancelled` handling in `TrackpadInputView`).

## Architecture

### Protocol (`Shared/PadCommand.swift`)
Newline-delimited JSON over a single raw TCP connection (`NWConnection`/`NWListener`, TCP `noDelay` enabled for low latency). `PadCommand` carries `move`/`scroll`/`click`/`buttonDown`/`buttonUp`/`gesture` events from iPad → Mac. `PadAcknowledgement` carries a `gestureAck` back from Mac → iPad (confirms the Quartz event was *posted*, not that macOS actually opened the corresponding system UI — there's no OS-level callback for that).

### iPad side (`iOS/`)
- `TrackpadInputView` (in `TrackpadSurface.swift`) owns all touch handling and gesture classification. Finger-count mapping: 1 finger = pointer/tap-click, 2 fingers = scroll (tap = right-click), 3 fingers = press-and-drag (mouse-down held while 3 fingers are down), 4 fingers = directional system-gesture swipe (Mission Control / App Exposé / Spaces by default).
- Pointer/scroll deltas are accumulated and flushed once per `CADisplayLink` tick (60 Hz target on iPad Air 5) rather than once per UIKit touch callback — see `queueMotion`/`flushFrameMotion`. When touching code here, preserve this frame-coalescing; don't reintroduce a `send` call per touch event.
- 4-finger swipe is recognized as soon as ≥3 of the original 4 touches cross a per-finger movement threshold in a dominant direction (`classifyFourFingerSwipe`) — it does not wait for touch-up, because iPadOS may cancel the touches first to claim the same gesture for app switching.
- `PadConnectionManager.swift` owns the `NWConnection`/Bonjour discovery lifecycle and reconnect-with-backoff logic.

### Mac side (`macOS/`)
- `MacServer` owns the `NWListener`/Bonjour advertisement and the per-connection receive loop. A single `inputQueue` (serial, `.userInteractive`) handles JSON decoding and all `InputEventController` calls — kept off the SwiftUI/AppKit main thread. Only one client connection is accepted at a time; accepting a new one cancels the previous.
- `InputEventController` turns `PadCommand`s into `CGEvent`s posted via `.cghidEventTap` (mouse move/drag/scroll/click) or `.cgSessionEventTap` (the Control+Arrow key chords used for 4-finger gesture actions). It tracks mouse-button-down state itself (`leftButtonIsDown`/`rightButtonIsDown`) since Quartz has no query for "is a button currently synthetically held" — and arms a watchdog (`armButtonReleaseWatchdog`, 12s) plus releases-on-disconnect so a dropped TCP connection or lost packet can never leave a mouse button stuck down.
- Per-direction 4-finger gesture action (Mission Control / App Exposé / previous-desktop / next-desktop / disabled) is user-configurable via `@AppStorage("gestureAction.<direction>")` in `MacContentView`, read back in `InputEventController.performGesture` via `UserDefaults` with `PadSystemAction.defaultAction` as fallback.

### Cross-cutting invariants worth preserving when editing either side
- All mutation of `NWConnection`/`NWListener` state-update handlers must re-validate `self.connection === <the specific connection>` (or equivalent) before acting, since a stale/replaced connection's async callback can otherwise fire after a reconnect.
- Any code path that can leave early (disconnect, cancel, error, replaced connection) should call `releaseAllButtons()` on the Mac side — never assume the iPad will always send a matching `buttonUp`.
- JSON messages are framed by `\n`; both sides buffer partial reads and split on `0x0A`, never assuming one `receive` call back = one message.

## Known state of this repo

- All targets build successfully using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild`.
- Four-finger gestures are stabilized: they use a `Control + SecondaryFn` modifier mask (0x840000) to match macOS symbolic hotkeys for Mission Control and Spaces.
- Pointer performance is instrumented via `PadLog` and `PadRateCounter`; check `log stream --predicate 'subsystem == "id.evonex.evopad" AND category == "pointer"'` for Hz metrics.
- `iOS/PadConnectionManager.swift` is fully reconstructed and functional.
