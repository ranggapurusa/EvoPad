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

/// Precision mechanical camera lens focal ring / focus dial scrollbar.
/// Features machined knurled tick marks (major/minor notches), center Leica-red witness mark,
/// travelling focus index needle with center hairline, and engraved focal limits (∞/0.3m or W/T).
final class CameraLensDialView: UIView {
    enum Axis {
        case vertical
        case horizontal
    }

    let axis: Axis
    private let notchesLayer = CAShapeLayer()
    private let centerWitnessMark = UIView()
    private let indexNeedle = UIView()
    private let needleHairline = UIView()
    private let startLabel = UILabel()
    private let endLabel = UILabel()

    var normalizedPosition: CGFloat = 0.5 {
        didSet {
            updateNeedlePosition()
        }
    }

    var isActive: Bool = false {
        didSet {
            updateActiveState()
        }
    }

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: .zero)
        setupDial()
    }

    required init?(coder: NSCoder) {
        self.axis = .vertical
        super.init(coder: coder)
        setupDial()
    }

    private func setupDial() {
        isUserInteractionEnabled = false
        backgroundColor = UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 0.85)
        layer.cornerRadius = 9
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        layer.masksToBounds = true

        // Center witness mark (Precision Leica Red index line)
        centerWitnessMark.backgroundColor = UIColor(red: 0.95, green: 0.28, blue: 0.22, alpha: 0.95)
        centerWitnessMark.layer.cornerRadius = 0.75
        addSubview(centerWitnessMark)

        // Precision travelling needle / focus thumb
        indexNeedle.backgroundColor = UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.92)
        indexNeedle.layer.cornerRadius = 2
        indexNeedle.layer.borderWidth = 0.5
        indexNeedle.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor

        needleHairline.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        indexNeedle.addSubview(needleHairline)
        addSubview(indexNeedle)

        // Focal engravings: ∞ and 0.3m for vertical; W and T for horizontal
        startLabel.font = .monospacedSystemFont(ofSize: 8, weight: .bold)
        startLabel.textColor = UIColor.white.withAlphaComponent(0.50)
        startLabel.textAlignment = .center
        startLabel.text = (axis == .vertical) ? "∞" : "W"
        addSubview(startLabel)

        endLabel.font = .monospacedSystemFont(ofSize: 7.5, weight: .bold)
        endLabel.textColor = UIColor.white.withAlphaComponent(0.50)
        endLabel.textAlignment = .center
        endLabel.text = (axis == .vertical) ? "0.3m" : "T"
        addSubview(endLabel)

        layer.insertSublayer(notchesLayer, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        drawMechanicalNotches()

        if axis == .vertical {
            startLabel.frame = CGRect(x: 0, y: 2, width: bounds.width, height: 14)
            endLabel.frame = CGRect(x: 0, y: bounds.height - 15, width: bounds.width, height: 14)
            centerWitnessMark.frame = CGRect(
                x: (bounds.width - 12) / 2,
                y: (bounds.height - 1.5) / 2,
                width: 12,
                height: 1.5
            )
        } else {
            startLabel.frame = CGRect(x: 3, y: (bounds.height - 14) / 2, width: 14, height: 14)
            endLabel.frame = CGRect(x: bounds.width - 17, y: (bounds.height - 14) / 2, width: 14, height: 14)
            centerWitnessMark.frame = CGRect(
                x: (bounds.width - 1.5) / 2,
                y: (bounds.height - 12) / 2,
                width: 1.5,
                height: 12
            )
        }

        updateNeedlePosition()
    }

    private func drawMechanicalNotches() {
        let path = UIBezierPath()
        let notchSpacing: CGFloat = 6.0

        if axis == .vertical {
            let startY: CGFloat = 17.0
            let endY: CGFloat = bounds.height - 17.0
            guard endY > startY else { return }

            var currentY = startY
            var idx = 0
            while currentY <= endY {
                let isMajor = (idx % 4 == 0)
                let notchWidth: CGFloat = isMajor ? 10.0 : 5.0
                let startX = (bounds.width - notchWidth) / 2
                path.move(to: CGPoint(x: startX, y: currentY))
                path.addLine(to: CGPoint(x: startX + notchWidth, y: currentY))
                currentY += notchSpacing
                idx += 1
            }
        } else {
            let startX: CGFloat = 19.0
            let endX: CGFloat = bounds.width - 19.0
            guard endX > startX else { return }

            var currentX = startX
            var idx = 0
            while currentX <= endX {
                let isMajor = (idx % 4 == 0)
                let notchHeight: CGFloat = isMajor ? 10.0 : 5.0
                let startY = (bounds.height - notchHeight) / 2
                path.move(to: CGPoint(x: currentX, y: startY))
                path.addLine(to: CGPoint(x: currentX, y: startY + notchHeight))
                currentX += notchSpacing
                idx += 1
            }
        }

        notchesLayer.path = path.cgPath
        notchesLayer.strokeColor = UIColor.white.withAlphaComponent(0.28).cgColor
        notchesLayer.lineWidth = 1.0
        notchesLayer.lineCap = .round
    }

    private func updateNeedlePosition() {
        let clamped = min(max(normalizedPosition, 0), 1)

        if axis == .vertical {
            let startY: CGFloat = 17.0
            let endY: CGFloat = bounds.height - 17.0
            let travel = max(endY - startY, 1)
            let needleHeight: CGFloat = 20.0
            let needleWidth: CGFloat = bounds.width - 6.0
            let currentY = startY + (travel - needleHeight) * clamped
            indexNeedle.frame = CGRect(
                x: 3.0,
                y: currentY,
                width: needleWidth,
                height: needleHeight
            )
            needleHairline.frame = CGRect(x: 2, y: (needleHeight - 1) / 2, width: needleWidth - 4, height: 1)
        } else {
            let startX: CGFloat = 19.0
            let endX: CGFloat = bounds.width - 19.0
            let travel = max(endX - startX, 1)
            let needleWidth: CGFloat = 20.0
            let needleHeight: CGFloat = bounds.height - 6.0
            let currentX = startX + (travel - needleWidth) * clamped
            indexNeedle.frame = CGRect(
                x: currentX,
                y: 3.0,
                width: needleWidth,
                height: needleHeight
            )
            needleHairline.frame = CGRect(x: (needleWidth - 1) / 2, y: 2, width: 1, height: needleHeight - 4)
        }
    }

    private func updateActiveState() {
        UIView.animate(withDuration: isActive ? 0.12 : 0.35) {
            if self.isActive {
                self.backgroundColor = UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 0.95)
                self.layer.borderColor = UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.70).cgColor
                self.indexNeedle.backgroundColor = UIColor(red: 0.488, green: 0.500, blue: 1.0, alpha: 1.0)
                self.centerWitnessMark.backgroundColor = UIColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1.0)
                self.notchesLayer.strokeColor = UIColor.white.withAlphaComponent(0.55).cgColor
                self.startLabel.textColor = UIColor.white.withAlphaComponent(0.90)
                self.endLabel.textColor = UIColor.white.withAlphaComponent(0.90)
            } else {
                self.backgroundColor = UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 0.85)
                self.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
                self.indexNeedle.backgroundColor = UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.92)
                self.centerWitnessMark.backgroundColor = UIColor(red: 0.95, green: 0.28, blue: 0.22, alpha: 0.95)
                self.notchesLayer.strokeColor = UIColor.white.withAlphaComponent(0.28).cgColor
                self.startLabel.textColor = UIColor.white.withAlphaComponent(0.50)
                self.endLabel.textColor = UIColor.white.withAlphaComponent(0.50)
            }
        }
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
    private var threeFingerReleaseWorkItem: DispatchWorkItem?
    private let threeFingerDragReleaseGracePeriod: TimeInterval = 0.40

    // Camera Lens Dial Scrollbars (Mechanical focal ring aesthetic)
    private let verticalLensDial = CameraLensDialView(axis: .vertical)
    private let horizontalLensDial = CameraLensDialView(axis: .horizontal)
    private var dialFadeWorkItem: DispatchWorkItem?
    private var activeDialTracking: CameraLensDialView.Axis? = nil
    private let scrollZoneThickness: CGFloat = 48

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
        threeFingerReleaseWorkItem?.cancel()
        dialFadeWorkItem?.cancel()
    }

    private func commonInit() {
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        isUserInteractionEnabled = true
        backgroundColor = UIColor(red: 0.105, green: 0.115, blue: 0.14, alpha: 1)
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        // Camera Lens Dial Scrollbars
        addSubview(verticalLensDial)
        addSubview(horizontalLensDial)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let vWidth: CGFloat = 18
        let vHeight: CGFloat = min(bounds.height * 0.65, 230)
        let vMargin: CGFloat = 8
        verticalLensDial.frame = CGRect(
            x: vMargin,
            y: (bounds.height - vHeight) / 2,
            width: vWidth,
            height: vHeight
        )

        let hHeight: CGFloat = 18
        let hWidth: CGFloat = min(bounds.width * 0.48, 240)
        let hMargin: CGFloat = 8
        let hLeftOffset: CGFloat = vMargin + vWidth + 8
        horizontalLensDial.frame = CGRect(
            x: hLeftOffset,
            y: hMargin,
            width: hWidth,
            height: hHeight
        )
    }

    private func isPointInVerticalScrollZone(_ point: CGPoint) -> Bool {
        point.x <= scrollZoneThickness
    }

    private func isPointInHorizontalScrollZone(_ point: CGPoint) -> Bool {
        let hMaxX = horizontalLensDial.frame.maxX + 16
        return point.y <= scrollZoneThickness && point.x > scrollZoneThickness && point.x <= hMaxX
    }

    private func updateDialNeedleFromTouch(_ touch: UITouch, axis: CameraLensDialView.Axis) {
        let loc = touch.location(in: self)
        if axis == .vertical {
            let dialFrame = verticalLensDial.frame
            let relY = loc.y - dialFrame.origin.y
            let norm = dialFrame.height > 0 ? (relY / dialFrame.height) : 0.5
            verticalLensDial.normalizedPosition = norm
        } else {
            let dialFrame = horizontalLensDial.frame
            let relX = loc.x - dialFrame.origin.x
            let norm = dialFrame.width > 0 ? (relX / dialFrame.width) : 0.5
            horizontalLensDial.normalizedPosition = norm
        }
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
        // If 3-finger drag is in grace period (user repositioning fingers), restore drag
        if isDragging, threeFingerReleaseWorkItem != nil {
            threeFingerReleaseWorkItem?.cancel()
            threeFingerReleaseWorkItem = nil
            onStatus?("3-finger drag dilanjutkan")
        }

        let isNewGesture = activeTouches.isEmpty && !isDragging
        if isNewGesture {
            resetGestureState()
        }

        for touch in touches {
            activeTouches[ObjectIdentifier(touch)] = touch.location(in: self)
        }

        maximumTouchCount = max(maximumTouchCount, activeTouches.count)

        if activeTouches.count == 1, isNewGesture, let touch = touches.first {
            let loc = touch.location(in: self)
            if isPointInVerticalScrollZone(loc) {
                gestureMode = .scrolling
                activeDialTracking = .vertical
                verticalLensDial.isActive = true
                updateDialNeedleFromTouch(touch, axis: .vertical)
                UISelectionFeedbackGenerator().selectionChanged()
                onStatus?("Dial fokal vertikal aktif — geser untuk scroll vertikal")
                return
            } else if isPointInHorizontalScrollZone(loc) {
                gestureMode = .scrolling
                activeDialTracking = .horizontal
                horizontalLensDial.isActive = true
                updateDialNeedleFromTouch(touch, axis: .horizontal)
                UISelectionFeedbackGenerator().selectionChanged()
                onStatus?("Dial fokal horizontal aktif — geser untuk scroll horizontal")
                return
            }
        }

        updateModeForTouchCount(isNewGesture: isNewGesture)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !activeTouches.isEmpty else { return }

        if let activeAxis = activeDialTracking, let touch = touches.first {
            let current = touch.location(in: self)
            let previous = touch.previousLocation(in: self)
            if activeAxis == .vertical {
                let dy = current.y - previous.y
                queueMotion(CGPoint(x: 0, y: dy * 2.2), kind: .scroll)
                verticalLensDial.isActive = true
                updateDialNeedleFromTouch(touch, axis: .vertical)
            } else {
                let dx = current.x - previous.x
                queueMotion(CGPoint(x: dx * 2.2, y: 0), kind: .scroll)
                horizontalLensDial.isActive = true
                updateDialNeedleFromTouch(touch, axis: .horizontal)
            }
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

        if let axis = activeDialTracking {
            activeDialTracking = nil
            if axis == .vertical {
                verticalLensDial.isActive = false
            } else {
                horizontalLensDial.isActive = false
            }
        }

        // When finger count drops below 3 during drag, debounce mouse-up
        // so user can lift and reposition fingers to continue a long drag.
        if activeTouches.count < 3 {
            switch gestureMode {
            case .threeFingerDragPending:
                flushFrameMotion()
                gestureMode = .ignored
                dragWorkItem?.cancel()
            case .threeFingerDragging:
                flushFrameMotion()
                dragWorkItem?.cancel()
                if isDragging && threeFingerReleaseWorkItem == nil {
                    let releaseWork = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.flushFrameMotion()
                        if self.isDragging {
                            self.onCommand?(.buttonUp(.left))
                            self.isDragging = false
                            self.onStatus?("3-finger drag selesai — tombol mouse dilepas")
                        }
                        self.gestureMode = .ignored
                        self.threeFingerReleaseWorkItem = nil
                    }
                    threeFingerReleaseWorkItem = releaseWork
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + threeFingerDragReleaseGracePeriod,
                        execute: releaseWork
                    )
                }
            default:
                break
            }
        }

        if activeTouches.isEmpty && threeFingerReleaseWorkItem == nil {
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
        if let axis = activeDialTracking {
            activeDialTracking = nil
            if axis == .vertical {
                verticalLensDial.isActive = false
            } else {
                horizontalLensDial.isActive = false
            }
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
            if isDragging {
                // Drag already active from previous 3-finger session within grace period: continue dragging
                threeFingerReleaseWorkItem?.cancel()
                threeFingerReleaseWorkItem = nil
                gestureMode = .threeFingerDragging
                onStatus?("3-finger drag dilanjutkan")
                return
            }
            if case .threeFingerDragPending = gestureMode { return }
            if case .threeFingerDragging = gestureMode { return }
            flushFrameMotion()
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
        threeFingerReleaseWorkItem?.cancel()
        threeFingerReleaseWorkItem = nil
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
                highlightDials(delta: delta)
            }

        case .scrolling:
            queueMotion(delta, kind: .scroll)
            highlightDials(delta: delta)

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

    private func highlightDials(delta: CGPoint) {
        dialFadeWorkItem?.cancel()
        if abs(delta.y) > 0.3 {
            verticalLensDial.isActive = true
            verticalLensDial.normalizedPosition = min(max(verticalLensDial.normalizedPosition + (delta.y * 0.008), 0), 1)
        }
        if abs(delta.x) > 0.3 {
            horizontalLensDial.isActive = true
            horizontalLensDial.normalizedPosition = min(max(horizontalLensDial.normalizedPosition + (delta.x * 0.008), 0), 1)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.verticalLensDial.isActive = false
            self.horizontalLensDial.isActive = false
        }
        dialFadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
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
        threeFingerReleaseWorkItem?.cancel()
        threeFingerReleaseWorkItem = nil

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
        activeDialTracking = nil
        verticalLensDial.isActive = false
        horizontalLensDial.isActive = false
        dialFadeWorkItem?.cancel()
        dialFadeWorkItem = nil
        dragWorkItem?.cancel()
        dragWorkItem = nil
        threeFingerReleaseWorkItem?.cancel()
        threeFingerReleaseWorkItem = nil
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
