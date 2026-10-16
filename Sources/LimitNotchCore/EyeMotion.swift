import CoreGraphics

/// Where an eye looks for a pointer somewhere on screen.
public enum EyeGaze {
    /// Pointer distance at which an eye has turned halfway to its limit.
    public static let falloff: CGFloat = 140

    /// The gaze for a pointer `offset` points from the eye (x to the right, y down): a vector in the
    /// unit circle that turns fully toward the pointer and saturates smoothly as it gets farther.
    /// Each eye uses its own offset, so a pointer right under the notch makes them converge.
    public static func direction(toward offset: CGVector, falloff: CGFloat = falloff) -> CGVector {
        let distance = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot()
        guard distance > 0.5 else { return .zero }
        let reach = distance / (distance * distance + falloff * falloff).squareRoot()
        return CGVector(dx: offset.dx / distance * reach, dy: offset.dy / distance * reach)
    }

    /// Distance from `point` to the nearest edge of `rect`, 0 inside it.
    public static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Fires once when the pointer comes close to the face, then waits for it to move well away
/// before it can fire again, so hovering at the edge does not make the eyes flutter.
public struct ApproachDetector: Equatable, Sendable {
    public static let near: CGFloat = 70
    public static let far: CGFloat = 160

    public private(set) var isArmed = true

    public init() {}

    /// Returns true when the pointer just came within `near` points.
    public mutating func update(distance: CGFloat) -> Bool {
        if isArmed, distance < Self.near {
            isArmed = false
            return true
        }
        if distance > Self.far { isArmed = true }
        return false
    }
}

/// One blink: the lid drops with an accelerating ease-in, rests shut for `hold`, and lifts with a
/// slower ease-out, the way real lids move.
public struct Blink: Equatable, Sendable {
    public var close: Double
    public var hold: Double
    public var open: Double

    public init(close: Double, hold: Double, open: Double) {
        self.close = close
        self.hold = hold
        self.open = open
    }

    public static let quick = Blink(close: 0.07, hold: 0.04, open: 0.16)
    public static let nervous = Blink(close: 0.05, hold: 0.02, open: 0.09)
    /// Dozing off: a slow fall, a few seconds asleep, then lids heavy on the way back up.
    public static func doze(hold: Double) -> Blink { Blink(close: 0.9, hold: hold, open: 0.7) }

    public var duration: Double { close + hold + open }

    /// 0 open, 1 shut, `elapsed` seconds after the blink began.
    public func closure(at elapsed: Double) -> CGFloat {
        // The tolerance absorbs rounding in `duration`, so a blink always ends fully open.
        if elapsed <= 0 || elapsed >= duration - 1e-9 { return 0 }
        if elapsed < close {
            let t = elapsed / close
            return CGFloat(t * t)
        }
        if elapsed < close + hold { return 1 }
        let t = (elapsed - close - hold) / open
        return CGFloat((1 - t) * (1 - t))
    }
}

/// The eyes' small celebration when a limit resets: stars for a 5-hour window, hearts for a weekly
/// one, which is rarer and better news.
public enum ResetCelebration: String, Equatable, Sendable {
    case star
    case heart

    /// A window must fall by at least this many points, to at most half its value, to count as reset.
    public static let minimumDrop: Double = 15

    /// The celebration for usage going from `old` to `new`, matching windows by service and length.
    public static func between(_ old: [UsageWindow], _ new: [UsageWindow]) -> ResetCelebration? {
        let reset = new.filter { window in
            guard let before = old.first(where: { $0.service == window.service && $0.isWeekly == window.isWeekly })
            else { return false }
            return before.percent - window.percent >= minimumDrop && window.percent <= before.percent / 2
        }
        if reset.isEmpty { return nil }
        return reset.contains(where: \.isWeekly) ? .heart : .star
    }
}
