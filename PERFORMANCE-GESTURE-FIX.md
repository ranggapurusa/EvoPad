# EvoPad — Four-Finger Recovery and 60 Hz Pointer Path

## Changes in this build

### Four-finger gestures
- A four-finger swipe is dispatched as soon as at least 3 of the 4 original fingers move at least 22 points in one dominant direction.
- Gesture dispatch no longer waits for all fingers to lift.
- `touchesCancelled` now processes the latest positions and attempts classification before cleanup.
- If UIKit cancels only some contacts, the remaining contacts are allowed to continue contributing to the gesture.
- The iPad status explains when iPadOS may be taking over the same four-finger gesture.

### Pointer performance
- Pointer and scroll deltas are accumulated between display frames.
- `CADisplayLink` flushes at a 60 Hz target, so there is at most one motion command per display frame.
- UIKit's latest coalesced touch location is used when available.
- TCP `noDelay` is enabled to reduce small-packet latency.
- iPad sends use a serial high-priority queue.
- Mac JSON parsing and Quartz event posting use a dedicated serial high-priority queue, separate from the Mac Helper UI thread.
- Mac Helper displays the last measured pointer input rate in Hz.

## Required iPad setting

Open **Settings → Multitasking & Gestures** and turn **Four & Five Finger App Switching** off. Apple documents this feature as using four/five-finger swipes and pinches for system app switching, so it can compete with EvoPad for the same touch sequence.

## Install

1. Close Xcode.
2. Back up the current EvoPad folder.
3. Replace it with the `EvoPad` folder from this archive.
4. Open `EvoPad.xcodeproj`.
5. Build `EvoPad Mac`, then `EvoPad iPad`.
6. Keep Accessibility on for EvoPad Mac and Local Network on for both apps.

## Performance note

The iPad Air 5 display operates at 60 Hz. EvoPad now schedules a maximum of one pointer/scroll update per display frame and shows the measured incoming pointer event rate in Mac Helper. This is a 60 Hz design target, not a guarantee under every Wi-Fi condition. The displayed Hz value measures input events received by Mac Helper, not a photometric measurement of cursor rendering on the display.
