import AppKit
import LimitNotchCore
import QuartzCore

/// Screen positions the eyes care about, in AppKit screen coordinates (origin bottom left).
struct EyeLayout: Equatable {
    var left: CGPoint
    var right: CGPoint
    /// The collapsed face; the eyes widen when the pointer comes near it.
    var face: CGRect
    /// The top center of the notch, the origin of LIMITNOTCH_DEBUG_POINTER.
    var top: CGPoint

    init(_ geometry: NotchGeometry) {
        let frame = geometry.panelFrame(expanded: false)
        left = CGPoint(x: frame.minX + geometry.leftEarCenter.x, y: frame.maxY - geometry.leftEarCenter.y)
        right = CGPoint(x: frame.minX + geometry.rightEarCenter.x, y: frame.maxY - geometry.rightEarCenter.y)
        face = frame
        top = CGPoint(x: geometry.centerX, y: geometry.screenFrame.maxY)
    }
}

/// Everything one frame of the eyes needs. Both eyes share it except for where they look.
struct EyeFrame {
    var expression: EyeExpression
    var color: RGB
    /// Gaze of each eye, inside the unit circle; y points down.
    var leftGaze: CGVector
    var rightGaze: CGVector
    /// 0 open, 1 shut.
    var closure: CGFloat
    /// Positive while a blink squashes the eye, negative as it stretches back.
    var squash: CGFloat
    /// 0 relaxed, 1 wide open with interest.
    var widen: CGFloat
    var tremble: CGSize
    /// 0 eyes, 1 the reset celebration's shapes.
    var flash: CGFloat
    var celebration: ResetCelebration
}

/// The eyes' muscles: springs for mood, gaze, blink squash, widening and the reset flash, plus the
/// habits that make them feel alive. The view's timeline samples `frame(at:)` on every display
/// refresh while `isRunning`; once everything has settled the rig stops it, so a still face costs
/// no frames at all. Pointer tracking runs only while the face is visible.
@MainActor
final class EyeRig: ObservableObject {
    /// True while anything moves. The eyes' timeline is paused otherwise.
    @Published private(set) var isRunning = false

    private var mood: CreatureState = .happy
    private var hasMood = false
    private var isVisible = true
    private var isExpanded = false
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    // Mood: one spring carries the face from the previous expression to the new one, overshoot included.
    private var morph = Spring(1, response: 0.55, dampingFraction: 0.68)
    private var fromExpression = EyeExpression.for(.happy)
    private var toExpression = EyeExpression.for(.happy)
    private var fromColor = Palette.mood(.happy)
    private var toColor = Palette.mood(.happy)

    private var gaze = [Spring](repeating: Spring(0, response: 0.3, dampingFraction: 0.8), count: 4)
    private var squash = Spring(0, response: 0.2, dampingFraction: 0.42)
    private var widen = Spring(0, response: 0.26, dampingFraction: 0.5)
    private var flash = Spring(0, response: 0.42, dampingFraction: 0.5)

    private var blinks: [(blink: Blink, start: Double)] = []
    private var tremble: (start: Double, end: Double)?
    private var widenRelease: Double?
    private var flashRelease: Double?
    private var celebration = ResetCelebration.star

    private enum GazeSource { case idle, pointer, mouth }
    private var gazeSource = GazeSource.idle
    private var idleGaze = CGVector.zero
    private var pointerGaze: (left: CGVector, right: CGVector)?
    /// The eyes follow the pointer until it has been still this long, then get bored.
    private static let attentionSpan: Double = 6
    private var attentionUntil: Double = 0
    private var approach = ApproachDetector()
    private var monitors: [Any] = []
    private var habits: Task<Void, Never>?
    private var lastStep: Double?
    private var sleepPending = false
    private var windows: [UsageWindow] = []

    /// A fixed pointer for screenshots: "dx,dy" points from the top center of the notch (y down).
    private let debugPointer: CGVector?
    private let debugFlash: ResetCelebration?

    var layout: EyeLayout? {
        didSet {
            guard layout != oldValue else { return }
            if let debugPointer, let layout { point(at: layout.top + debugPointer, now: CACurrentMediaTime()) }
        }
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        debugPointer = environment["LIMITNOTCH_DEBUG_POINTER"].flatMap { raw in
            let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return parts.count == 2 ? CGVector(dx: parts[0], dy: parts[1]) : nil
        }
        debugFlash = environment["LIMITNOTCH_DEBUG_FLASH"].flatMap { ResetCelebration(rawValue: $0.lowercased()) }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reduceMotionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if let debugFlash {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.celebrate(debugFlash, hold: nil)
            }
        }
    }

    private var isLive: Bool { isVisible && !reduceMotion }

    // MARK: - Inputs

    func setMood(_ mood: CreatureState) {
        guard !hasMood || mood != self.mood else { return }
        let now = CACurrentMediaTime()
        let current = currentLook()
        fromExpression = current.expression
        fromColor = current.color
        toExpression = EyeExpression.for(mood)
        toColor = Palette.mood(mood)
        if hasMood && isLive {
            morph.snap(to: 0)
            morph.target = 1
            // Animators hide a change of expression behind a blink.
            blink(.quick, at: now)
        } else {
            morph.snap(to: 1)
        }
        self.mood = mood
        hasMood = true
        idleGaze = Self.restingGaze(mood)
        restartHabits()
        wake()
    }

    /// Feeds the latest usage of the selected service; a window that just reset sets off a flash.
    func observe(_ windows: [UsageWindow]) {
        guard !windows.isEmpty else { return }
        if let kind = ResetCelebration.between(self.windows, windows) {
            celebrate(kind, hold: 1.6)
        }
        self.windows = windows
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        wake()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        updateLiveness()
    }

    @objc private func reduceMotionChanged(_ notification: Notification) {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        updateLiveness()
    }

    private func updateLiveness() {
        restartHabits()
        updateTracking()
        if isLive {
            wake()
        } else {
            // Freeze on a calm pose; the next visible frame starts from there.
            blinks.removeAll()
            tremble = nil
            isRunning = false
            lastStep = nil
        }
    }

    // MARK: - Pointer

    private func updateTracking() {
        let shouldTrack = isLive && debugPointer == nil
        if shouldTrack, monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            }) {
                monitors.append(local)
            }
        } else if !shouldTrack, !monitors.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            pointerGaze = nil
        }
    }

    private func pointerMoved() {
        point(at: NSEvent.mouseLocation, now: CACurrentMediaTime())
    }

    private func point(at pointer: CGPoint, now: Double) {
        guard let layout else { return }
        let look = { (eye: CGPoint) in
            EyeGaze.direction(toward: CGVector(dx: pointer.x - eye.x, dy: eye.y - pointer.y))
        }
        let next = (left: look(layout.left), right: look(layout.right))
        let wasAttending = now < attentionUntil
        attentionUntil = debugPointer == nil ? now + Self.attentionSpan : .infinity
        if approach.update(distance: EyeGaze.distance(from: pointer, to: layout.face)) {
            widen.target = 1
            // A parked debug pointer keeps them wide for the screenshot.
            widenRelease = debugPointer == nil ? now + 0.5 : nil
            wake()
        }
        // Ignore motion too small to move a pupil by a pixel.
        if let previous = pointerGaze, wasAttending,
           max(abs(previous.left.dx - next.left.dx), abs(previous.left.dy - next.left.dy),
               abs(previous.right.dx - next.right.dx), abs(previous.right.dy - next.right.dy)) < 0.01 {
            return
        }
        pointerGaze = next
        wake()
    }

    // MARK: - Frames

    /// Advances every spring to `now` and returns the pose to draw.
    func frame(at now: Double) -> EyeFrame {
        let dt = min(max(now - (lastStep ?? now), 0), 1.0 / 15)
        lastStep = now
        updateTargets(now)
        morph.step(dt)
        for index in gaze.indices { gaze[index].step(dt) }
        widen.step(dt)
        flash.step(dt)

        blinks.removeAll { now - $0.start >= $0.blink.duration }
        let closure = blinks.map { $0.blink.closure(at: now - $0.start) }.max() ?? 0
        squash.target = Double(closure)
        squash.step(dt)

        var shiver = CGSize.zero
        if let tremble, now < tremble.end {
            let envelope = sin(.pi * (now - tremble.start) / (tremble.end - tremble.start))
            shiver = CGSize(width: envelope * (0.5 * sin(now * 53) + 0.25 * sin(now * 97)),
                            height: envelope * 0.35 * sin(now * 71))
        } else {
            tremble = nil
        }

        let look = currentLook()
        if isRunning, isSettled(now) { scheduleSleep() }
        return EyeFrame(
            expression: look.expression, color: look.color,
            leftGaze: CGVector(dx: gaze[0].value, dy: gaze[1].value),
            rightGaze: CGVector(dx: gaze[2].value, dy: gaze[3].value),
            closure: closure, squash: squash.value, widen: widen.value, tremble: shiver,
            flash: flash.value, celebration: celebration
        )
    }

    private func currentLook() -> (expression: EyeExpression, color: RGB) {
        let t = CGFloat(morph.value)
        return (fromExpression.mixed(with: toExpression, by: t), fromColor.mixed(with: toColor, by: min(max(t, 0), 1)))
    }

    private func updateTargets(_ now: Double) {
        if let release = widenRelease, now >= release {
            widen.target = 0
            widenRelease = nil
        }
        if let release = flashRelease, now >= release {
            flash.target = 0
            flashRelease = nil
        }

        let source: GazeSource
        let targets: (left: CGVector, right: CGVector)
        if isExpanded {
            // The mouth is open: both eyes read the number below them.
            source = .mouth
            targets = (CGVector(dx: 0.12, dy: 0.8), CGVector(dx: -0.12, dy: 0.8))
        } else if let pointerGaze, now < attentionUntil {
            source = .pointer
            targets = pointerGaze
        } else {
            source = .idle
            targets = (idleGaze, idleGaze)
        }
        if source != gazeSource {
            gazeSource = source
            // Pointer and mouth: a smooth pursuit. Idle: quick darting saccades.
            let (response, damping) = source == .idle ? (0.13, 0.86) : (0.3, 0.78)
            for index in gaze.indices {
                gaze[index].response = response
                gaze[index].dampingFraction = damping
            }
        }
        gaze[0].target = targets.left.dx
        gaze[1].target = targets.left.dy
        gaze[2].target = targets.right.dx
        gaze[3].target = targets.right.dy
    }

    private func isSettled(_ now: Double) -> Bool {
        morph.isSettled && squash.isSettled && widen.isSettled && flash.isSettled
            && gaze.allSatisfy(\.isSettled) && blinks.isEmpty && tremble == nil
            && widenRelease == nil && flashRelease == nil
    }

    private func wake() {
        guard isVisible, !isRunning else { return }
        lastStep = nil
        isRunning = true
    }

    /// Pauses the timeline after the current frame; publishing from inside a frame is not allowed.
    private func scheduleSleep() {
        guard !sleepPending else { return }
        sleepPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            sleepPending = false
            if isRunning, isSettled(CACurrentMediaTime()) {
                isRunning = false
                lastStep = nil
            }
        }
    }

    // MARK: - Habits

    private func blink(_ blink: Blink, at start: Double) {
        guard isLive else { return }
        blinks.append((blink, start))
        wake()
    }

    private func celebrate(_ kind: ResetCelebration, hold: Double?) {
        celebration = kind
        flash.target = 1
        flashRelease = hold.map { CACurrentMediaTime() + $0 }
        if !isLive { flash.snap(to: hold == nil ? 1 : 0) }
        wake()
    }

    /// Where each mood's eyes rest when nothing holds their attention.
    private static func restingGaze(_ mood: CreatureState) -> CGVector {
        mood == .sleeping ? CGVector(dx: 0, dy: 0.45) : CGVector(dx: 0, dy: 0.12)
    }

    private func restartHabits() {
        habits?.cancel()
        guard isLive, hasMood else { return }
        habits = Task { @MainActor [weak self] in
            var pause = Double.random(in: 1.5...3)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled, let self else { return }
                pause = performHabit(now: CACurrentMediaTime())
            }
        }
    }

    /// Does one small thing in character and returns the seconds until the next one.
    private func performHabit(now: Double) -> Double {
        let attending = now < attentionUntil || isExpanded
        let rest = Self.restingGaze(mood)
        // Wakes the timeline anyway, so drifting back from a still pointer happens here too.
        wake()
        switch mood {
        case .happy:
            if !attending, Double.random(in: 0...1) < 0.45 {
                idleGaze = rest + Self.randomVector(radius: 0.22)
                return .random(in: 1.2...2.8)
            }
            blink(.quick, at: now)
            if Double.random(in: 0...1) < 0.2 { blink(.quick, at: now + Blink.quick.duration + 0.1) }
            return .random(in: 2.5...5.5)
        case .worried:
            if !attending, Bool.random() {
                idleGaze = abs(idleGaze.dx) > 0.3
                    ? rest
                    : CGVector(dx: Bool.random() ? 0.7 : -0.7, dy: 0.1)
            }
            if Double.random(in: 0...1) < 0.45 { blink(.quick, at: now) }
            return .random(in: 0.9...2.2)
        case .panic:
            if Double.random(in: 0...1) < 0.6 {
                tremble = (now, now + .random(in: 0.5...0.9))
            }
            if !attending { idleGaze = Self.randomVector(radius: 0.5) }
            if Bool.random() { blink(.nervous, at: now) }
            return .random(in: 0.8...2)
        case .sleeping:
            idleGaze = rest
            if Bool.random() {
                blink(.doze(hold: .random(in: 1.5...4)), at: now)
            } else {
                blink(Blink(close: 0.28, hold: 0.12, open: 0.5), at: now)
            }
            return .random(in: 5...10)
        }
    }

    private static func randomVector(radius: Double) -> CGVector {
        let angle = Double.random(in: 0..<(2 * .pi))
        let length = radius * Double.random(in: 0.4...1)
        return CGVector(dx: cos(angle) * length, dy: sin(angle) * length)
    }
}

private func + (point: CGPoint, offset: CGVector) -> CGPoint {
    // The debug offset's y points down; AppKit's screen y points up.
    CGPoint(x: point.x + offset.dx, y: point.y - offset.dy)
}

private func + (lhs: CGVector, rhs: CGVector) -> CGVector {
    CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
}
