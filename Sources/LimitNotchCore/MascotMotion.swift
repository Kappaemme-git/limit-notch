import Foundation

/// Everything the renderer needs for one frame. Lengths are fractions of the body diameter.
public struct MascotPose: Equatable, Sendable {
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    /// Squash and stretch, applied around the bottom of the body.
    public var scaleX: Double = 1
    public var scaleY: Double = 1
    /// Body tilt in radians; positive leans right.
    public var rotation: Double = 0
    /// Eye direction, -1...1 on each axis; negative `gazeY` looks up.
    public var gazeX: Double = 0
    public var gazeY: Double = 0
    /// 1 is fully open; 0 is a closed line.
    public var eyeOpenness: Double = 1
    public var eyeScale: Double = 1
    /// Vertical eye shift; negative moves the eyes up.
    public var eyeLift: Double = 0
    /// Strength of the red alarm glow, 0...1.
    public var glow: Double = 0
    /// Opacity of the floating Zzz and the phase (0..<1) of its first letter.
    public var zzzOpacity: Double = 0
    public var zzzPhase: Double = 0
    /// The worried sweat drop: vertical slide (fraction of the diameter) and opacity.
    public var dropOffset: Double = 0
    public var dropOpacity: Double = 0

    public init() {}

    public static func blend(_ a: MascotPose, _ b: MascotPose, _ fraction: Double) -> MascotPose {
        let f = min(max(fraction, 0), 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        var pose = MascotPose()
        pose.offsetX = mix(a.offsetX, b.offsetX)
        pose.offsetY = mix(a.offsetY, b.offsetY)
        pose.scaleX = mix(a.scaleX, b.scaleX)
        pose.scaleY = mix(a.scaleY, b.scaleY)
        pose.rotation = mix(a.rotation, b.rotation)
        pose.gazeX = mix(a.gazeX, b.gazeX)
        pose.gazeY = mix(a.gazeY, b.gazeY)
        pose.eyeOpenness = mix(a.eyeOpenness, b.eyeOpenness)
        pose.eyeScale = mix(a.eyeScale, b.eyeScale)
        pose.eyeLift = mix(a.eyeLift, b.eyeLift)
        pose.glow = mix(a.glow, b.glow)
        pose.zzzOpacity = mix(a.zzzOpacity, b.zzzOpacity)
        pose.zzzPhase = b.zzzPhase
        pose.dropOffset = mix(a.dropOffset, b.dropOffset)
        pose.dropOpacity = mix(a.dropOpacity, b.dropOpacity)
        return pose
    }
}

/// Procedural animation for the mascot. `pose(at:state:seed:)` is a pure function of time, so a
/// TimelineView can draw any frame without stored state. Random-looking events (blinks and
/// glances) come from a hash of the seed and the time slot, so they are irregular but deterministic.
/// The mood loops (bounce, sway, shake, breath) follow the keyframes of the design prototype.
public enum MascotMotion {
    public static let blinkDuration: TimeInterval = 0.12
    public static let breathingAmount = 0.03

    struct Tuning {
        var breathPeriod: Double = 3
        var breathAmount: Double = MascotMotion.breathingAmount
        /// Blinks start once per `blinkPeriod`, shifted by up to `blinkJitter`, so the gap
        /// between two blinks stays within `blinkPeriod ± blinkJitter`.
        var blinkPeriod: Double? = 4
        var blinkJitter: Double = 1
        var blinkDuration: Double = MascotMotion.blinkDuration
        var doubleBlinkChance: Double = 0.15
        var glancePeriod: Double? = 5.5
        var glanceChance: Double = 0.6
        var glanceHold: ClosedRange<Double> = 0.7...1.4
        var eyeRamp: Double = 0.1
        var leanRamp: Double = 0.32
    }

    static func tuning(for state: CreatureState) -> Tuning {
        var t = Tuning()
        switch state {
        case .happy:
            t.blinkPeriod = 4.1
            t.blinkJitter = 0.9
        case .worried:
            t.blinkPeriod = 3.4
            t.blinkJitter = 1
            t.glancePeriod = 2
            t.glanceChance = 0.85
            t.glanceHold = 0.3...0.7
            t.eyeRamp = 0.07
        case .panic:
            t.blinkPeriod = 0.9
            t.blinkJitter = 0.4
            t.blinkDuration = 0.09
            t.doubleBlinkChance = 0
            t.glancePeriod = 0.9
            t.glanceChance = 0.7
            t.glanceHold = 0.18...0.35
            t.eyeRamp = 0.05
            t.leanRamp = 0.12
            t.breathPeriod = 1.2
        case .sleeping:
            t.blinkPeriod = nil
            t.glancePeriod = nil
            t.breathAmount = 0
        }
        return t
    }

    // The mood loops of design/Prototype.dc.html (lcBounce, lcSway, lcShake, lcGlow, lcBreath,
    // lcDrop and lcZ), as (fraction of the period, value) keyframes.
    static let bouncePeriod = 2.4
    static let bounceLift: [(Double, Double)] = [(0, 0), (0.14, -0.14), (0.28, 0), (0.38, -0.05), (0.48, 0), (1, 0)]
    static let bounceScaleX: [(Double, Double)] = [(0, 1), (0.14, 0.97), (0.28, 1.07), (0.38, 1), (0.48, 1.02), (0.62, 1), (1, 1)]
    static let bounceScaleY: [(Double, Double)] = [(0, 1), (0.14, 1.03), (0.28, 0.93), (0.38, 1), (0.48, 0.98), (0.62, 1), (1, 1)]
    static let swayPeriod = 3.2
    static let swayAngle = 3 * Double.pi / 180
    static let shakePeriod = 2.0
    static let shakeX: [(Double, Double)] = [(0, 0), (0.03, -0.07), (0.07, 0.07), (0.11, -0.07), (0.15, 0.07),
                                             (0.19, -0.07), (0.23, 0.07), (0.27, -0.02), (0.30, 0), (1, 0)]
    static let shakeAngle: [(Double, Double)] = [(0, 0), (0.03, -4), (0.07, 4), (0.11, -4), (0.15, 4),
                                                 (0.19, -4), (0.23, 4), (0.27, -1), (0.30, 0), (1, 0)]
    static let glowPeriod = 1.2
    static let sleepBreathPeriod = 4.0
    static let dropPeriod = 2.2
    static let dropSlide: [(Double, Double)] = [(0, -0.012), (0.75, 0.024), (1, 0.036)]
    static let dropFade: [(Double, Double)] = [(0, 0), (0.2, 1), (0.75, 1), (1, 0)]
    public static let zzzPeriod = 2.4
    /// The second "z" starts this far (as a fraction of the period) behind the first.
    public static let zzzStagger = 0.8 / 2.4

    public static func pose(at time: TimeInterval, state: CreatureState, seed: UInt64) -> MascotPose {
        let tuning = tuning(for: state)
        var pose = MascotPose()

        // Breathing: a slow cosine swell, uniform scale 1.0 ... 1.0 + amount.
        let breath = (1 - cos(2 * .pi * time / tuning.breathPeriod)) / 2
        let breathScale = 1 + tuning.breathAmount * breath
        pose.scaleX = breathScale
        pose.scaleY = breathScale

        pose.eyeOpenness = state == .sleeping ? 0 : blinkOpenness(at: time, tuning: tuning, seed: seed)

        // Looking around: eyes move quickly, the body leans after them more slowly.
        if let glance = glance(at: time, tuning: tuning, seed: seed) {
            pose.gazeX = glance.x * glance.eyes
            pose.gazeY = glance.y * glance.eyes
            pose.rotation += glance.x * glance.lean * 0.11
            pose.offsetY -= max(0, -glance.y) * glance.lean * 0.02
        }

        switch state {
        case .happy:
            // A soft bounce every 2.4 s: hop, squash on landing, a small rebound.
            let phase = cycle(time, bouncePeriod)
            pose.offsetY += keyframes(phase, bounceLift)
            pose.scaleX *= keyframes(phase, bounceScaleX)
            pose.scaleY *= keyframes(phase, bounceScaleY)
        case .worried:
            // Sways ±3° while bobbing; the eyes shrink and lift under slanted brows.
            let sway = -cos(2 * .pi * time / swayPeriod)
            pose.rotation += sway * swayAngle
            pose.offsetY += sway * 0.02
            pose.eyeScale = 0.78
            pose.eyeLift = -0.04
            let drop = cycle(time, dropPeriod)
            pose.dropOffset = keyframes(drop, dropSlide)
            pose.dropOpacity = keyframes(drop, dropFade)
        case .panic:
            // A short shake burst every 2 s and a red glow pulsing at 1.2 s.
            let phase = cycle(time, shakePeriod)
            pose.offsetX += keyframes(phase, shakeX, eased: false)
            pose.rotation += keyframes(phase, shakeAngle, eased: false) * .pi / 180
            pose.glow = 0.55 + 0.45 * (1 - cos(2 * .pi * time / glowPeriod)) / 2
        case .sleeping:
            let breath = (1 - cos(2 * .pi * time / sleepBreathPeriod)) / 2
            pose.scaleX = 1 + 0.03 * breath
            pose.scaleY = 1 - 0.03 * breath
            pose.offsetY += 0.02 * breath
            pose.zzzOpacity = 1
            pose.zzzPhase = cycle(time, zzzPeriod)
        }
        return pose
    }

    /// Position within a repeating period, 0..<1.
    static func cycle(_ time: Double, _ period: Double) -> Double {
        let phase = (time / period).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }

    /// Value at `phase` between sorted keyframes, eased in and out per segment like CSS.
    static func keyframes(_ phase: Double, _ frames: [(Double, Double)], eased: Bool = true) -> Double {
        guard var previous = frames.first else { return 0 }
        for frame in frames.dropFirst() {
            if phase <= frame.0 {
                let span = frame.0 - previous.0
                let x = span > 0 ? (phase - previous.0) / span : 1
                return previous.1 + (frame.1 - previous.1) * (eased ? smoothstep(x) : min(max(x, 0), 1))
            }
            previous = frame
        }
        return previous.1
    }

    // MARK: - Blinking

    /// Start times of the scheduled blinks within `range` (the quick second blink of a double blink is not listed).
    static func blinkStarts(in range: ClosedRange<Double>, state: CreatureState, seed: UInt64) -> [Double] {
        let tuning = tuning(for: state)
        guard let period = tuning.blinkPeriod else { return [] }
        var starts: [Double] = []
        var slot = Int64((range.lowerBound / period).rounded(.down)) - 1
        while Double(slot) * period <= range.upperBound {
            let start = Double(slot) * period + random(seed, 1, slot) * tuning.blinkJitter
            if range.contains(start) { starts.append(start) }
            slot += 1
        }
        return starts
    }

    static func blinkOpenness(at time: Double, tuning: Tuning, seed: UInt64) -> Double {
        guard let period = tuning.blinkPeriod else { return 1 }
        let slot = Int64((time / period).rounded(.down))
        let start = Double(slot) * period + random(seed, 1, slot) * tuning.blinkJitter
        var closure = blinkClosure((time - start) / tuning.blinkDuration)
        if random(seed, 2, slot) < tuning.doubleBlinkChance {
            closure = max(closure, blinkClosure((time - start - 0.26) / tuning.blinkDuration))
        }
        return 1 - closure
    }

    /// 0 → 1 → 0 over x in 0...1: a fast close and a slightly slower open.
    static func blinkClosure(_ x: Double) -> Double {
        guard x > 0, x < 1 else { return 0 }
        return x < 0.4 ? smoothstep(x / 0.4) : 1 - smoothstep((x - 0.4) / 0.6)
    }

    // MARK: - Glancing

    static func glance(at time: Double, tuning: Tuning, seed: UInt64) -> (x: Double, y: Double, eyes: Double, lean: Double)? {
        guard let period = tuning.glancePeriod else { return nil }
        let slot = Int64((time / period).rounded(.down))
        guard random(seed, 3, slot) < tuning.glanceChance else { return nil }
        let hold = tuning.glanceHold.lowerBound
            + random(seed, 4, slot) * (tuning.glanceHold.upperBound - tuning.glanceHold.lowerBound)
        let duration = min(hold + 2 * tuning.leanRamp, period)
        let start = Double(slot) * period + random(seed, 5, slot) * (period - duration)
        let local = time - start
        guard local >= 0, local <= duration else { return nil }

        let pick = random(seed, 6, slot)
        let jitter = random(seed, 7, slot) - 0.5
        let direction: (Double, Double)
        if pick < 0.4 {
            direction = (-1, jitter * 0.4)
        } else if pick < 0.8 {
            direction = (1, jitter * 0.4)
        } else {
            direction = (jitter * 0.6, -1)
        }
        let eyes = smoothstep(local / tuning.eyeRamp) * smoothstep((duration - local) / tuning.eyeRamp)
        let lean = smoothstep(local / tuning.leanRamp) * smoothstep((duration - local) / tuning.leanRamp)
        return (direction.0, direction.1, eyes, lean)
    }

    // MARK: - Helpers

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Deterministic value in 0..<1 for a seed, an event channel, and a time slot (SplitMix64).
    static func random(_ seed: UInt64, _ channel: UInt64, _ slot: Int64) -> Double {
        var z = seed &+ channel &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: slot) &* 0xD1B5_4A32_D192_ED03
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
