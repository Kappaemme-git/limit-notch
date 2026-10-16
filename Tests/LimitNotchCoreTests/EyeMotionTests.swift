import XCTest
@testable import LimitNotchCore

final class SpringTests: XCTestCase {
    private func run(_ spring: inout Spring, seconds: Double, dt: Double = 1.0 / 120) -> [Double] {
        var values: [Double] = []
        for _ in 0..<Int(seconds / dt) {
            spring.step(dt)
            values.append(spring.value)
        }
        return values
    }

    func testSettlesExactlyOnTarget() {
        var spring = Spring(0, response: 0.4, dampingFraction: 0.7)
        spring.target = 1
        XCTAssertFalse(spring.isSettled)
        _ = run(&spring, seconds: 3)
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.value, 1)
    }

    func testUnderdampedOvershootsAndCriticalDoesNot() {
        var bouncy = Spring(0, response: 0.4, dampingFraction: 0.5)
        bouncy.target = 1
        XCTAssertGreaterThan(run(&bouncy, seconds: 1).max() ?? 0, 1.05)
        var critical = Spring(0, response: 0.4, dampingFraction: 1)
        critical.target = 1
        XCTAssertLessThanOrEqual(run(&critical, seconds: 2).max() ?? 2, 1)
    }

    func testLongFramesStayStableAndMatchShortOnes() {
        var coarse = Spring(0, response: 0.3, dampingFraction: 0.6)
        var fine = coarse
        coarse.target = 1
        fine.target = 1
        _ = run(&coarse, seconds: 0.25, dt: 1.0 / 20)
        _ = run(&fine, seconds: 0.25, dt: 1.0 / 240)
        XCTAssertEqual(coarse.value, fine.value, accuracy: 0.001)
        var stalled = Spring(0, response: 0.3, dampingFraction: 0.6)
        stalled.target = 1
        stalled.step(5)
        XCTAssertEqual(stalled.value, 1)
    }

    func testSnapStopsMotion() {
        var spring = Spring(0, response: 0.3, dampingFraction: 0.6)
        spring.target = 1
        spring.step(0.05)
        spring.snap(to: 0.3)
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.value, 0.3)
    }
}

final class EyeGazeTests: XCTestCase {
    func testLooksTowardThePointerInsideTheUnitCircle() {
        let right = EyeGaze.direction(toward: CGVector(dx: 500, dy: 0))
        XCTAssertGreaterThan(right.dx, 0.9)
        XCTAssertEqual(right.dy, 0, accuracy: 0.0001)
        let below = EyeGaze.direction(toward: CGVector(dx: 0, dy: 300))
        XCTAssertGreaterThan(below.dy, 0.8)
        for offset in [CGVector(dx: 10_000, dy: 10_000), CGVector(dx: -3, dy: 2), CGVector(dx: 0, dy: -900)] {
            let gaze = EyeGaze.direction(toward: offset)
            XCTAssertLessThan((gaze.dx * gaze.dx + gaze.dy * gaze.dy).squareRoot(), 1)
        }
        XCTAssertEqual(EyeGaze.direction(toward: .zero), .zero)
    }

    func testNearPointerTurnsTheEyesLessThanAFarOne() {
        let near = EyeGaze.direction(toward: CGVector(dx: 40, dy: 0))
        let far = EyeGaze.direction(toward: CGVector(dx: 400, dy: 0))
        XCTAssertLessThan(near.dx, far.dx)
        XCTAssertEqual(EyeGaze.direction(toward: CGVector(dx: EyeGaze.falloff, dy: 0)).dx, 0.5.squareRoot(),
                       accuracy: 0.0001)
    }

    func testEyesConvergeOnAPointerBetweenThem() {
        // A pointer just below the middle of the notch: each eye turns inward.
        let pointer = CGPoint(x: 0, y: 60)
        let left = EyeGaze.direction(toward: CGVector(dx: pointer.x + 120, dy: pointer.y))
        let right = EyeGaze.direction(toward: CGVector(dx: pointer.x - 120, dy: pointer.y))
        XCTAssertGreaterThan(left.dx, 0)
        XCTAssertLessThan(right.dx, 0)
    }

    func testDistanceToTheFace() {
        let face = CGRect(x: 100, y: 0, width: 200, height: 32)
        XCTAssertEqual(EyeGaze.distance(from: CGPoint(x: 150, y: 10), to: face), 0)
        XCTAssertEqual(EyeGaze.distance(from: CGPoint(x: 150, y: 72), to: face), 40)
        XCTAssertEqual(EyeGaze.distance(from: CGPoint(x: 330, y: 72), to: face), 50)
    }
}

final class ApproachDetectorTests: XCTestCase {
    func testFiresOnceUntilThePointerLeaves() {
        var detector = ApproachDetector()
        XCTAssertFalse(detector.update(distance: 300))
        XCTAssertTrue(detector.update(distance: 50))
        XCTAssertFalse(detector.update(distance: 20))
        // Hovering around the near edge does not re-arm it.
        XCTAssertFalse(detector.update(distance: 100))
        XCTAssertFalse(detector.update(distance: 60))
        XCTAssertFalse(detector.update(distance: 200))
        XCTAssertTrue(detector.update(distance: 30))
    }
}

final class BlinkTests: XCTestCase {
    func testClosesHoldsAndReopens() {
        let blink = Blink(close: 0.1, hold: 0.05, open: 0.2)
        XCTAssertEqual(blink.duration, 0.35, accuracy: 0.0001)
        XCTAssertEqual(blink.closure(at: 0), 0)
        XCTAssertEqual(blink.closure(at: 0.12), 1)
        XCTAssertEqual(blink.closure(at: 0.35), 0)
        XCTAssertEqual(blink.closure(at: -1), 0)
        // Lids accelerate shut and decelerate open.
        XCTAssertLessThan(blink.closure(at: 0.05), 0.5)
        XCTAssertGreaterThan(blink.closure(at: 0.25), 0.2)
        var previous: CGFloat = 0
        for step in 0...10 {
            let value = blink.closure(at: 0.01 * Double(step))
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testDozeStaysShutForItsHold() {
        let doze = Blink.doze(hold: 3)
        XCTAssertEqual(doze.closure(at: doze.close + 2.5), 1)
        XCTAssertGreaterThan(doze.duration, 4)
    }
}

final class ResetCelebrationTests: XCTestCase {
    private func window(_ service: UsageWindow.Service, weekly: Bool = false, _ percent: Double) -> UsageWindow {
        UsageWindow(service: service, isWeekly: weekly, percent: percent, resetsAt: nil)
    }

    func testFiveHourResetShowsStars() {
        let before = [window(.claude, 72), window(.claude, weekly: true, 40)]
        let after = [window(.claude, 3), window(.claude, weekly: true, 41)]
        XCTAssertEqual(ResetCelebration.between(before, after), .star)
    }

    func testWeeklyResetShowsHearts() {
        let before = [window(.claude, 72), window(.codex, weekly: true, 60)]
        let after = [window(.claude, 2), window(.codex, weekly: true, 0)]
        XCTAssertEqual(ResetCelebration.between(before, after), .heart)
    }

    func testSmallOrPartialDropsAreIgnored() {
        XCTAssertNil(ResetCelebration.between([window(.claude, 12)], [window(.claude, 0)]))
        XCTAssertNil(ResetCelebration.between([window(.claude, 80)], [window(.claude, 60)]))
        XCTAssertNil(ResetCelebration.between([window(.claude, 30)], [window(.claude, 34)]))
    }

    func testNeedsTheSameWindowOnBothSides() {
        // First load, or switching from Claude to Codex, is not a reset.
        XCTAssertNil(ResetCelebration.between([], [window(.claude, 3)]))
        XCTAssertNil(ResetCelebration.between([window(.claude, 70)], [window(.codex, 3)]))
        XCTAssertNil(ResetCelebration.between([window(.claude, 70)], [window(.claude, weekly: true, 3)]))
    }
}
