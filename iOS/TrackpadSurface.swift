import SwiftUI
import UIKit
import QuartzCore

struct TrackpadSurface: UIViewRepresentable {
    let onCommand: (PadCommand) -> Void
    var onStatus: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> TrackpadInputView {
        let view = TrackpadInputView()
        view.onCommand = onCommand
        view.onStatus = onStatus
        return view
    }

    func updateUIView(_ uiView: TrackpadInputView, context: Context) {
        uiView.onCommand = onCommand
        uiView.onStatus = onStatus
    }
}

/// Gesture mapping:
/// - 1 finger: pointer, tap = left click, long-press + move = fallback drag.
/// - 2 fingers: tap = right click, move = scroll.
/// - 3 fingers: drag (mouse-down while moving; release when any finger lifts).
/// - 4 fingers: Mission Control / App Exposé / Spaces.
///
/// Pointer and scroll deltas are flushed on CADisplayLink at 60 Hz. This avoids
/// sending a TCP/JSON command for every UIKit touch callback and keeps the input
/// stream aligned with the iPad Air display refresh rate.
final class TrackpadInputView: UIView {
    private enum GestureMode {
        case pointer
        case twoFingerTapPending
        case scrolling
        case threeFingerDragPending
        case threeFingerDragging
        case fourFingerSwipe
        case ignored
    }

    private enum MotionKind {
        case pointer
        case scroll
    }

    private final class DisplayLinkTarget: NSObject {
        weak var owner: TrackpadInputView?

        init(owner: TrackpadInputView) {
            self.owner = owner
        }

        @objc func tick(_ link: CADisplayLink) {
            owner?.flushFrameMotion()
        }
    }

    var onCommand: ((PadCommand) -> Void)?
    var onStatus: ((String) -> Void)?

    private var activeTouches: [ObjectIdentifier: CGPoint] = [:]
    private var gestureMode: GestureMode = .pointer
    private var gestureStartedAt = CACurrentMediaTime()
    private var maximumTouchCount = 0
    private var totalMovement: CGFloat = 0
    private var threeFingerDragMovement: CGFloat = 0

    private var fourFingerTouchIDs = Set<ObjectIdentifier>()
    private var fourFingerDeltas: [ObjectIdentifier: CGPoint] = [:]
    private var fourFingerGestureSent = false

    private var isDragging = false
    private var dragWorkItem: DispatchWorkItem?

    // Touchpad Scrollbar
    private let scrollBarContainer = UIView()
    private let scrollTrackView = UIView()
    private let scrollThumbView = UIView()
    private let scrollUpIcon = UIImageView()
    private let scrollDownIcon = UIImageView()
    private var scrollFadeWorkItem: DispatchWorkItem?
    private var isScrollBarTouchActive = false
    private let scrollZoneWidth: CGFloat = 52

    // Frame-coalesced motion queue.
    private var pendingPointerDelta = CGPoint.zero
    private var pendingScrollDelta = CGPoint.zero
    private var displayLink: CADisplayLink?
    private lazy var displayLinkTarget = DisplayLinkTarget(owner: self)

    // Diagnostics: "generated" counts every raw touch delta before 60 Hz
    // coalescing; "sent" counts the coalesced commands actually emitted.
    // The gap between the two is exactly how much the frame-coalescing is
    // reducing the network/CGEvent load.
    private let generatedRate = PadRateCounter(label: "iPad pointer generated")
    private let sentRate = PadRateCounter(label: "iPad pointer sent")

    private let tapMovementLimit: CGFloat = 10
    private let dragStartJitterLimit: CGFloat = 18
    private let dragHoldDuration: TimeInterval = 0.42
    private let tapMaximumDuration: TimeInterval = 0.38
    private let scrollStartThreshold: CGFloat = 3
    private let threeFingerDragStartThreshold: CGFloat = 3
    private let fourFingerPerFingerThreshold: CGFloat = 9
    private let fourFingerDirectionDominance: CGFloat = 1.04

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        displayLink?.invalidate()
        dragWorkItem?.cancel()
        scrollFadeWorkItem?.cancel()
    }

    private func commonInit() {
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isUserInteractionEnabled = true
        backgroundColor = UIColor(red: 0.105, green: 0.115, blue: 0.14, alpha: 1)
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        // Touchpad Scrollbar on right edge
        scrollBarContainer.backgroundColor = UIColor(white: 0.14, alpha: 0.65)
        scrollBarContainer.layer.cornerRadius = 9
        scrollBarContainer.layer.borderWidth = 1
        scrollBarContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        scrollBarContainer.clipsToBounds = true
        scrollBarContainer.isUserInteractionEnabled = false

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        scrollUpIcon.image = UIImage(systemName: "chevron.up", withConfiguration: symbolConfig)
        scrollUpIcon.tintColor = UIColor.white.withAlphaComponent(0.50)
        scrollUpIcon.contentMode = .center

        scrollDownIcon.image = UIImage(systemName: "chevron.down", withConfiguration: symbolConfig)
        scrollDownIcon.tintColor = UIColor.white.withAlphaComponent(0.50)
        scrollDownIcon.contentMode = .center

        scrollTrackView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        scrollTrackView.layer.cornerRadius = 2
        scrollTrackView.clipsToBounds = true

        scrollThumbView.backgroundColor = UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.90) // Indigo
        scrollThumbView.layer.cornerRadius = 2

        scrollTrackView.addSubview(scrollThumbView)
        scrollBarContainer.addSubview(scrollUpIcon)
        scrollBarContainer.addSubview(scrollTrackView)
        scrollBarContainer.addSubview(scrollDownIcon)
        addSubview(scrollBarContainer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barWidth: CGFloat = 18
        let barHeight: CGFloat = min(bounds.height * 0.65, 240)
        let rightMargin: CGFloat = 8
        scrollBarContainer.frame = CGRect(
            x: bounds.width - barWidth - rightMargin,
            y: (bounds.height - barHeight) / 2,
            width: barWidth,
            height: barHeight
        )

        let iconHeight: CGFloat = 18
        scrollUpIcon.frame = CGRect(x: 0, y: 2, width: barWidth, height: iconHeight)
        scrollDownIcon.frame = CGRect(x: 0, y: barHeight - iconHeight - 2, width: barWidth, height: iconHeight)

        let trackY = iconHeight + 4
        let trackHeight = barHeight - (iconHeight * 2) - 8
        let trackWidth: CGFloat = 4
        scrollTrackView.frame = CGRect(
            x: (barWidth - trackWidth) / 2,
            y: trackY,
            width: trackWidth,
            height: trackHeight
        )

        updateThumbFrame(trackHeight: trackHeight, trackWidth: trackWidth, normalizedPosition: 0.5)
    }

    private func updateThumbFrame(trackHeight: CGFloat, trackWidth: CGFloat, normalizedPosition: CGFloat) {
        let thumbHeight: CGFloat = max(32, trackHeight * 0.30)
        let clampedPos = min(max(normalizedPosition, 0), 1)
        let availableTravel = trackHeight - thumbHeight
        let thumbY = availableTravel * clampedPos
        scrollThumbView.frame = CGRect(
            x: 0,
            y: thumbY,
            width: trackWidth,
            height: thumbHeight
        )
    }

    private func isPointInScrollZone(_ point: CGPoint) -> Bool {
        point.x >= (bounds.width - scrollZoneWidth)
    }

    private func updateThumbFromTouch(_ point: CGPoint) {
        let container = scrollBarContainer.frame
        let track = scrollTrackView.frame
        let trackAbsoluteY = container.origin.y + track.origin.y
        let relativeY = point.y - trackAbsoluteY
        let normalized = track.height > 0 ? (relativeY / track.height) : 0.5
        updateThumbFrame(trackHeight: track.height, trackWidth: track.width, normalizedPosition: normalized)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            flushFrameMotion()
            displayLink?.invalidate()
            displayLink = nil
            if !activeTouches.isEmpty || isDragging {
                finishGesture(cancelled: true)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let isNewGesture = activeTouches.isEmpty
        if isNewGesture {
            resetGestureState()
        }

        for touch in touches {
            activeTouches[ObjectIdentifier(touch)] = touch.location(in: self)
        }

        maximumTouchCount = max(maximumTouchCount, activeTouches.count)

        if activeTouches.count == 1, isNewGesture,
           let touch = touches.first, isPointInScrollZone(touch.location(in: self)) {
            gestureMode = .scrolling
            isScrollBarTouchActive = true
            highlightScrollIndicator(active: true)
            updateThumbFromTouch(touch.location(in: self))
            UISelectionFeedbackGenerator().selectionChanged()
            onStatus?("Touchpad scrollbar aktif — geser untuk scroll")
            return
        }

        updateModeForTouchCount(isNewGesture: isNewGesture)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activeTouches.isEmpty else { return }

        if isScrollBarTouchActive, let touch = touches.first {
            let current = touch.location(in: self)
            let previous = touch.previousLocation(in: self)
            let dy = current.y - previous.y
            queueMotion(CGPoint(x: 0, y: dy * 2.2), kind: .scroll)
            updateThumbFromTouch(current)
            highlightScrollIndicator(active: true)
            return
        }

        if case .fourFingerSwipe = gestureMode {
            updateFourFingerDeltas(touches, event: event)
            dispatchFourFingerGestureIfRecognized()
            return
        }

        let oldCentroid = centroid()
        updateTouchLocations(touches, event: event)
        let newCentroid = centroid()
        applyMovement(CGPoint(x: newCentroid.x - oldCentroid.x, y: newCentroid.y - oldCentroid.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activeTouches.isEmpty else { return }

        if case .fourFingerSwipe = gestureMode {
            updateFourFingerDeltas(touches, event: event)
            dispatchFourFingerGestureIfRecognized()
        } else {
            let oldCentroid = centroid()
            updateTouchLocations(touches, event: event)
            let newCentroid = centroid()
            applyMovement(CGPoint(x: newCentroid.x - oldCentroid.x, y: newCentroid.y - oldCentroid.y))
        }

        for touch in touches {
            activeTouches.removeValue(forKey: ObjectIdentifier(touch))
        }

        if isScrollBarTouchActive {
            isScrollBarTouchActive = false
            highlightScrollIndicator(active: false)
        }

        // A 3-finger drag releases as soon as one finger lifts. Flush its last
        // coalesced motion before mouse-up so the final segment is not dropped.
        if activeTouches.count < 3 {
            switch gestureMode {
            case .threeFingerDragPending, .threeFingerDragging:
                flushFrameMotion()
                if isDragging {
                    onCommand?(.buttonUp(.left))
                    onStatus?("3-finger drag selesai — tombol mouse dilepas")
                }
                isDragging = false
                gestureMode = .ignored
                dragWorkItem?.cancel()
            default:
                break
            }
        }

        if activeTouches.isEmpty {
            finishGesture(cancelled: false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // UIKit can cancel touches when a system gesture or interruption takes
        // ownership. Treat this as a terminal event, but preserve a 4-finger
        // swipe if the accumulated motion already crossed our recognition rule.
        if case .fourFingerSwipe = gestureMode {
            updateFourFingerDeltas(touches, event: event)
            dispatchFourFingerGestureIfRecognized()

            for touch in touches {
                activeTouches.removeValue(forKey: ObjectIdentifier(touch))
            }

            // UIKit can report cancellation for a subset of touches. Keep the
            // remaining contacts alive so their final movement can still help
            // classify the 4-finger swipe. If all contacts were cancelled, end
            // the sequence after the final classification attempt.
            if activeTouches.isEmpty {
                finishGesture(cancelled: !fourFingerGestureSent)
            } else if fourFingerGestureSent {
                onStatus?("Swipe empat jari sudah dikirim — menunggu sentuhan dilepas")
            } else {
                onStatus?("iPadOS membatalkan sebagian sentuhan 4 jari sebelum ambang swipe. Matikan Four & Five Finger App Switching di Settings → Multitasking & Gestures.")
            }
            return
        }

        for touch in touches {
            activeTouches.removeValue(forKey: ObjectIdentifier(touch))
        }
        if isScrollBarTouchActive {
            isScrollBarTouchActive = false
            highlightScrollIndicator(active: false)
        }
        finishGesture(cancelled: true)
    }

    private func updateModeForTouchCount(isNewGesture: Bool) {
        let count = activeTouches.count

        if case .ignored = gestureMode { return }

        if count > 4 {
            flushFrameMotion()
            releaseDragIfNeeded(message: "Drag dilepas")
            gestureMode = .ignored
            dragWorkItem?.cancel()
            onStatus?("Gesture diabaikan: terdeteksi lebih dari 4 sentuhan. Gunakan tepat 4 jari untuk navigasi.")
            return
        }

        if count == 4 {
            if case .fourFingerSwipe = gestureMode { return }
            flushFrameMotion()
            releaseDragIfNeeded(message: "Drag dilepas untuk gesture empat jari")
            gestureMode = .fourFingerSwipe
            fourFingerTouchIDs = Set(activeTouches.keys)
            fourFingerDeltas = Dictionary(uniqueKeysWithValues: fourFingerTouchIDs.map { ($0, .zero) })
            fourFingerGestureSent = false
            dragWorkItem?.cancel()
            PadLog.gesture("iPad: 4-finger gesture started, touches=\(fourFingerTouchIDs.count)")
            onStatus?("4 jari terdeteksi. Swipe searah. Pastikan Four & Five Finger App Switching iPad OFF.")
            return
        }

        if count == 3 {
            if case .fourFingerSwipe = gestureMode { return }
            if case .threeFingerDragPending = gestureMode { return }
            if case .threeFingerDragging = gestureMode { return }
            flushFrameMotion()
            if isDragging {
                releaseDragIfNeeded(message: "Drag sebelumnya dilepas")
            }
            gestureMode = .threeFingerDragPending
            threeFingerDragMovement = 0
            dragWorkItem?.cancel()
            onStatus?("3-finger drag siap — geser ketiga jari")
            return
        }

        if count == 2 {
            if case .fourFingerSwipe = gestureMode { return }
            if case .threeFingerDragPending = gestureMode { return }
            if case .threeFingerDragging = gestureMode { return }
            if case .scrolling = gestureMode { return }
            flushFrameMotion()
            if isDragging {
                releaseDragIfNeeded(message: "Drag dilepas saat beralih ke dua jari")
            }
            gestureMode = .twoFingerTapPending
            dragWorkItem?.cancel()
            return
        }

        if count == 1, isNewGesture {
            gestureMode = .pointer
            scheduleLongPressDrag()
        }
    }

    private func releaseDragIfNeeded(message: String) {
        flushFrameMotion()
        if isDragging {
            onCommand?(.buttonUp(.left))
            isDragging = false
            onStatus?(message)
        }
    }

    private func updateTouchLocations(_ touches: Set<UITouch>, event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard activeTouches[id] != nil else { continue }
            activeTouches[id] = latestLocation(for: touch, event: event)
        }
    }

    private func latestLocation(for touch: UITouch, event: UIEvent?) -> CGPoint {
        event?.coalescedTouches(for: touch)?.last?.location(in: self) ?? touch.location(in: self)
    }

    private func updateFourFingerDeltas(_ touches: Set<UITouch>, event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard fourFingerTouchIDs.contains(id), let previous = activeTouches[id] else { continue }
            let current = latestLocation(for: touch, event: event)
            let delta = CGPoint(x: current.x - previous.x, y: current.y - previous.y)
            let accumulated = fourFingerDeltas[id] ?? .zero
            fourFingerDeltas[id] = CGPoint(
                x: accumulated.x + delta.x,
                y: accumulated.y + delta.y
            )
            activeTouches[id] = current
        }
    }

    private func dispatchFourFingerGestureIfRecognized() {
        guard !fourFingerGestureSent,
              let direction = classifyFourFingerSwipe() else { return }

        flushFrameMotion()
        fourFingerGestureSent = true
        PadLog.gesture("iPad: classified direction=\(direction.rawValue), deltas=\(fourFingerDeltas.values.map { "(\(Int($0.x)),\(Int($0.y)))" })")
        onCommand?(.gesture(direction))
        PadLog.gesture("iPad: gesture command sent to connection layer, direction=\(direction.rawValue)")
        onStatus?("4 jari dikenali: \(direction.title). Dikirim ke Mac; menunggu konfirmasi.")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func applyMovement(_ delta: CGPoint) {
        guard !activeTouches.isEmpty else { return }
        totalMovement += hypot(delta.x, delta.y)

        if totalMovement > dragStartJitterLimit && !isDragging {
            dragWorkItem?.cancel()
        }

        switch gestureMode {
        case .pointer:
            queueMotion(delta, kind: .pointer)

        case .twoFingerTapPending:
            if totalMovement >= scrollStartThreshold {
                gestureMode = .scrolling
                queueMotion(delta, kind: .scroll)
                highlightScrollIndicator(active: true)
            }

        case .scrolling:
            queueMotion(delta, kind: .scroll)
            highlightScrollIndicator(active: true)

        case .threeFingerDragPending:
            threeFingerDragMovement += hypot(delta.x, delta.y)
            if threeFingerDragMovement >= threeFingerDragStartThreshold {
                gestureMode = .threeFingerDragging
                isDragging = true
                dragWorkItem?.cancel()
                onCommand?(.buttonDown(.left))
                onStatus?("3-finger drag aktif — angkat satu jari atau semua jari untuk melepas")
                queueMotion(delta, kind: .pointer)
            }

        case .threeFingerDragging:
            queueMotion(delta, kind: .pointer)

        case .fourFingerSwipe, .ignored:
            break
        }
    }

    private func highlightScrollIndicator(active: Bool) {
        scrollFadeWorkItem?.cancel()
        if active {
            UIView.animate(withDuration: 0.12) {
                self.scrollBarContainer.backgroundColor = UIColor(white: 0.20, alpha: 0.85)
                self.scrollBarContainer.layer.borderColor = UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.60).cgColor
                self.scrollThumbView.backgroundColor = UIColor(red: 0.488, green: 0.500, blue: 1.0, alpha: 1.0)
                self.scrollUpIcon.tintColor = UIColor.white.withAlphaComponent(0.90)
                self.scrollDownIcon.tintColor = UIColor.white.withAlphaComponent(0.90)
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.highlightScrollIndicator(active: false)
            }
            scrollFadeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        } else {
            UIView.animate(withDuration: 0.35) {
                self.scrollBarContainer.backgroundColor = UIColor(white: 0.14, alpha: 0.65)
                self.scrollBarContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
                self.scrollThumbView.backgroundColor = UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.90)
                self.scrollUpIcon.tintColor = UIColor.white.withAlphaComponent(0.50)
                self.scrollDownIcon.tintColor = UIColor.white.withAlphaComponent(0.50)
            }
        }
    }

    private func queueMotion(_ delta: CGPoint, kind: MotionKind) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        generatedRate.tick()
        switch kind {
        case .pointer:
            pendingPointerDelta.x += delta.x
            pendingPointerDelta.y += delta.y
        case .scroll:
            pendingScrollDelta.x += delta.x
            pendingScrollDelta.y += delta.y
        }
        startDisplayLinkIfNeeded()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, window != nil else { return }
        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Called by CADisplayLink. At most one move/scroll message is emitted per
    /// display frame (60 Hz on iPad Air 5), with all interim deltas accumulated.
    fileprivate func flushFrameMotion() {
        let pointer = pendingPointerDelta
        let scroll = pendingScrollDelta
        pendingPointerDelta = .zero
        pendingScrollDelta = .zero

        if pointer != .zero {
            onCommand?(.move(dx: Double(pointer.x), dy: Double(pointer.y)))
            sentRate.tick()
        }
        if scroll != .zero {
            onCommand?(.scroll(dx: Double(scroll.x), dy: Double(scroll.y)))
            sentRate.tick()
        }

        // Keep the display link alive for the entire active touch sequence.
        // Invalidating it after every quiet frame would recreate it for nearly
        // every touch callback and add avoidable scheduling jitter.
        if pendingPointerDelta == .zero && pendingScrollDelta == .zero && activeTouches.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func finishGesture(cancelled: Bool) {
        flushFrameMotion()
        dragWorkItem?.cancel()
        dragWorkItem = nil

        if isDragging {
            onCommand?(.buttonUp(.left))
            onStatus?(cancelled ? "Drag dibatalkan — tombol mouse dilepas" : "Drag selesai — tombol mouse dilepas")
        } else if case .fourFingerSwipe = gestureMode {
            dispatchFourFingerGestureIfRecognized()
            if !fourFingerGestureSent {
                onStatus?("4 jari dibatalkan sebelum terdeteksi. Matikan Settings → Multitasking & Gestures → Four & Five Finger App Switching, lalu coba lagi.")
            }
        } else if !cancelled {
            let elapsed = CACurrentMediaTime() - gestureStartedAt
            switch gestureMode {
            case .pointer:
                if maximumTouchCount == 1,
                   totalMovement <= tapMovementLimit,
                   elapsed <= tapMaximumDuration {
                    onCommand?(.click(.left))
                }
            case .twoFingerTapPending:
                if maximumTouchCount == 2,
                   totalMovement <= tapMovementLimit,
                   elapsed <= tapMaximumDuration {
                    onCommand?(.click(.right))
                }
            case .threeFingerDragPending, .threeFingerDragging, .scrolling, .fourFingerSwipe, .ignored:
                break
            }
        }

        isDragging = false
        activeTouches.removeAll()
        resetGestureState()
    }

    private func resetGestureState() {
        gestureStartedAt = CACurrentMediaTime()
        maximumTouchCount = 0
        totalMovement = 0
        threeFingerDragMovement = 0
        fourFingerTouchIDs.removeAll()
        fourFingerDeltas.removeAll()
        fourFingerGestureSent = false
        pendingPointerDelta = .zero
        pendingScrollDelta = .zero
        gestureMode = .pointer
        isDragging = false
        isScrollBarTouchActive = false
        dragWorkItem?.cancel()
        dragWorkItem = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    /// A swipe is accepted when at least 3 of the 4 original fingers move in
    /// one dominant direction. It is dispatched as soon as the threshold is
    /// crossed, rather than waiting for touch-up (which iPadOS may cancel).
    private func classifyFourFingerSwipe() -> PadGestureDirection? {
        guard fourFingerTouchIDs.count == 4 else { return nil }

        var votes: [PadGestureDirection: Int] = [:]
        for id in fourFingerTouchIDs {
            guard let delta = fourFingerDeltas[id] else { continue }
            let horizontal = abs(delta.x)
            let vertical = abs(delta.y)

            if horizontal >= fourFingerPerFingerThreshold,
               horizontal >= vertical * fourFingerDirectionDominance {
                let direction: PadGestureDirection = delta.x < 0 ? .left : .right
                votes[direction, default: 0] += 1
            } else if vertical >= fourFingerPerFingerThreshold,
                      vertical >= horizontal * fourFingerDirectionDominance {
                let direction: PadGestureDirection = delta.y < 0 ? .up : .down
                votes[direction, default: 0] += 1
            }
        }

        return votes.first(where: { $0.value >= 3 })?.key
    }

    private func scheduleLongPressDrag() {
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeTouches.count == 1,
                  case .pointer = self.gestureMode,
                  self.totalMovement <= self.dragStartJitterLimit else { return }

            self.flushFrameMotion()
            self.isDragging = true
            self.onCommand?(.buttonDown(.left))
            self.onStatus?("Drag aktif — geser jari, lalu angkat untuk melepas")
        }
        dragWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dragHoldDuration, execute: work)
    }

    private func centroid() -> CGPoint {
        guard !activeTouches.isEmpty else { return .zero }
        let points = Array(activeTouches.values)
        let count = CGFloat(points.count)
        let x = points.reduce(CGFloat.zero) { $0 + $1.x } / count
        let y = points.reduce(CGFloat.zero) { $0 + $1.y } / count
        return CGPoint(x: x, y: y)
    }
}
