import Foundation

/// A damped spring that chases `target`, parameterized like SwiftUI's `.spring(response:dampingFraction:)`.
/// It steps with the exact solution of the spring equation, so a long or uneven frame never makes
/// it unstable, and it snaps onto the target once the motion is too small to see.
public struct Spring: Equatable, Sendable {
    public var value: Double
    public var velocity: Double = 0
    public var target: Double
    /// Seconds per oscillation of the undamped spring; smaller is snappier.
    public var response: Double
    /// 1 settles without overshoot, lower values bounce. Values above 1 behave like 1.
    public var dampingFraction: Double
    /// Distance from the target, and speed per second, below which the spring is at rest.
    public var tolerance: Double

    public init(_ value: Double, response: Double, dampingFraction: Double, tolerance: Double = 0.001) {
        self.value = value
        target = value
        self.response = response
        self.dampingFraction = dampingFraction
        self.tolerance = tolerance
    }

    public var isSettled: Bool {
        value == target && velocity == 0
    }

    /// Jumps to `value` with no motion.
    public mutating func snap(to value: Double) {
        self.value = value
        target = value
        velocity = 0
    }

    public mutating func step(_ dt: Double) {
        guard !isSettled, dt > 0 else { return }
        let omega = 2 * .pi / max(response, 0.001)
        let zeta = min(max(dampingFraction, 0), 1)
        let x0 = value - target
        let v0 = velocity
        let decay = exp(-zeta * omega * dt)
        let x: Double
        let v: Double
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let a = zeta * omega
            let b = (v0 + a * x0) / damped
            let (sine, cosine) = (sin(damped * dt), cos(damped * dt))
            x = decay * (x0 * cosine + b * sine)
            v = decay * (v0 * cosine - (a * b + damped * x0) * sine)
        } else {
            let b = v0 + omega * x0
            x = decay * (x0 + b * dt)
            v = decay * (v0 - omega * b * dt)
        }
        if abs(x) < tolerance && abs(v) < tolerance * 10 {
            value = target
            velocity = 0
        } else {
            value = target + x
            velocity = v
        }
    }
}
