import XCTest
@testable import LimitNotchCore

final class MascotMotionTests: XCTestCase {
    private let seeds: [UInt64] = [0, 1, 42, 0xDEAD_BEEF, .max]
    private let states: [CreatureState] = [.happy, .worried, .panic, .sleeping]

    private func samples(_ range: ClosedRange<Double>, step: Double = 1.0 / 60) -> [Double] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
    }

    func testIdleBlinksEveryThreeToFiveSeconds() {
        for seed in seeds {
            let starts = MascotMotion.blinkStarts(in: 0...600, state: .happy, seed: seed)
            XCTAssertGreaterThan(starts.count, 100)
            for (a, b) in zip(starts, starts.dropFirst()) {
                XCTAssertTrue((3...5).contains(b - a), "gap \(b - a) for seed \(seed)")
            }
        }
    }

    func testBlinkClosesToALineAndReopensWithinItsDuration() {
        let seed: UInt64 = 7
        let start = MascotMotion.blinkStarts(in: 10...20, state: .happy, seed: seed)[0]
        let mid = MascotMotion.pose(at: start + MascotMotion.blinkDuration * 0.4, state: .happy, seed: seed)
        XCTAssertLessThan(mid.eyeOpenness, 0.05)
        let after = MascotMotion.pose(at: start + MascotMotion.blinkDuration + 0.01, state: .happy, seed: seed)
        let before = MascotMotion.pose(at: start - 0.01, state: .happy, seed: seed)
        XCTAssertEqual(before.eyeOpenness, 1)
        XCTAssertEqual(after.eyeOpenness, 1)
    }

    func testPanicBlinksMuchMoreOftenThanIdle() {
        let idle = MascotMotion.blinkStarts(in: 0...120, state: .happy, seed: 3).count
        let panic = MascotMotion.blinkStarts(in: 0...120, state: .panic, seed: 3).count
        XCTAssertGreaterThan(panic, idle * 3)
    }

    func testIdleBreathingStaysWithinThreePercent() {
        // Sample the worried state: it has no hops, so scale is breathing alone.
        let scales = samples(0...6).map { MascotMotion.pose(at: $0, state: .worried, seed: 1).scaleY }
        XCTAssertEqual(scales.min()!, 1, accuracy: 0.001)
        XCTAssertEqual(scales.max()!, 1 + MascotMotion.breathingAmount, accuracy: 0.001)
    }

    func testSleepKeepsEyesClosedWithZzzAndNoGlow() {
        for t in samples(0...20, step: 0.37) {
            let pose = MascotMotion.pose(at: t, state: .sleeping, seed: 9)
            XCTAssertEqual(pose.eyeOpenness, 0)
            XCTAssertEqual(pose.zzzOpacity, 1)
            XCTAssertTrue((0..<1).contains(pose.zzzPhase))
            XCTAssertEqual(pose.glow, 0)
            XCTAssertEqual(pose.gazeX, 0)
        }
    }

    func testPanicGlowsRedAndShakes() {
        let poses = samples(0...3).map { MascotMotion.pose(at: $0, state: .panic, seed: 5) }
        XCTAssertGreaterThan(poses.map(\.glow).min()!, 0.4)
        XCTAssertGreaterThan(poses.map { abs($0.offsetX) }.max()!, 0.03)
        XCTAssertTrue(MascotMotion.pose(at: 1, state: .happy, seed: 5).glow == 0)
    }

    func testWorriedEyesAreSmallerAndHigher() {
        let pose = MascotMotion.pose(at: 12.3, state: .worried, seed: 2)
        XCTAssertLessThan(pose.eyeScale, 1)
        XCTAssertLessThan(pose.eyeLift, 0)
    }

    func testHappyHopsAndLooksAroundWithTilt() {
        let poses = samples(0...120, step: 1.0 / 30).map { MascotMotion.pose(at: $0, state: .happy, seed: 11) }
        XCTAssertLessThan(poses.map(\.offsetY).min()!, -0.08, "should leave the ground")
        XCTAssertGreaterThan(poses.map(\.scaleX).max()!, 1.05, "should squash on landing")
        XCTAssertTrue(poses.contains { $0.gazeX < -0.9 } && poses.contains { $0.gazeX > 0.9 })
        // The body leans toward where the eyes look.
        for pose in poses where abs(pose.gazeX) > 0.9 && pose.offsetY == 0 {
            XCTAssertEqual(pose.rotation.sign, pose.gazeX.sign)
        }
    }

    func testMotionHasNoJumpsAtSixtyFramesPerSecond() {
        // The panic shake and the hop's landing impact are fast but still spread over several frames.
        for state in states {
            let poses = samples(0...60).map { MascotMotion.pose(at: $0, state: state, seed: 21) }
            for (a, b) in zip(poses, poses.dropFirst()) {
                XCTAssertLessThan(abs(a.offsetY - b.offsetY), 0.05, "\(state)")
                XCTAssertLessThan(abs(a.scaleY - b.scaleY), 0.1, "\(state)")
                XCTAssertLessThan(abs(a.rotation - b.rotation), 0.1, "\(state)")
            }
        }
    }

    func testPoseIsDeterministicForASeed() {
        for state in states {
            XCTAssertEqual(MascotMotion.pose(at: 33.3, state: state, seed: 4),
                           MascotMotion.pose(at: 33.3, state: state, seed: 4))
        }
    }

    func testBlendInterpolatesAndClamps() {
        let a = MascotMotion.pose(at: 1, state: .panic, seed: 1)
        let b = MascotMotion.pose(at: 1, state: .sleeping, seed: 1)
        XCTAssertEqual(MascotPose.blend(a, b, 0).glow, a.glow)
        XCTAssertEqual(MascotPose.blend(a, b, 2), MascotPose.blend(a, b, 1))
        XCTAssertEqual(MascotPose.blend(a, b, 0.5).glow, a.glow / 2, accuracy: 1e-9)
    }
}
