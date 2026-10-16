import XCTest
@testable import LimitNotchCore

final class EyeExpressionTests: XCTestCase {
    private let moods: [CreatureState] = [.happy, .worried, .panic, .sleeping]

    func testHappyEyesAreOpenSoftCapsules() {
        let eye = EyeExpression.for(.happy)
        XCTAssertGreaterThan(eye.height / eye.width, 1.3, "taller than wide")
        XCTAssertEqual(eye.outerLid + eye.innerLid, 0)
        XCTAssertEqual(eye.tilt, 0)
        XCTAssertEqual(eye.brow, 0)
        XCTAssertGreaterThan(eye.roundness, 2, "a touch squarer than an ellipse")
    }

    func testWorriedEyesDroopAtTheOuterCornerUnderASlantedBrow() {
        let eye = EyeExpression.for(.worried)
        XCTAssertGreaterThan(eye.outerLid, eye.innerLid + 0.15)
        XCTAssertGreaterThan(eye.tilt, 0, "the inner corner is raised")
        XCTAssertEqual(eye.brow, 1)
        XCTAssertGreaterThan(eye.browTilt, 0, "the inner end is raised")
        XCTAssertLessThan(eye.height, EyeExpression.for(.happy).height)
    }

    func testPanicEyesAreBiggestRoundestAndBrightestUnderHighBrows() {
        let panic = EyeExpression.for(.panic)
        for mood in [CreatureState.happy, .worried, .sleeping] {
            let other = EyeExpression.for(mood)
            XCTAssertGreaterThan(panic.height, other.height, "\(mood)")
            XCTAssertGreaterThan(panic.width, other.width, "\(mood)")
            XCTAssertGreaterThan(panic.glow, other.glow, "\(mood)")
            XCTAssertLessThanOrEqual(panic.roundness, other.roundness, "\(mood)")
        }
        XCTAssertEqual(panic.outerLid + panic.innerLid, 0)
        XCTAssertEqual(panic.brow, 1)
        XCTAssertGreaterThan(panic.browLift, EyeExpression.for(.worried).browLift)
    }

    func testSleepingEyesAreHalfLiddedAndDim() {
        let eye = EyeExpression.for(.sleeping)
        XCTAssertEqual(eye.outerLid, 0.5, accuracy: 0.1)
        XCTAssertEqual(eye.innerLid, 0.5, accuracy: 0.1)
        XCTAssertEqual(eye.brow, 0)
        XCTAssertLessThan(eye.glow, 0.2)
    }

    func testBrowsAndEyeFitInTheBand() {
        // A 32 pt band with the eye centered: the eye drops to leave the brow room at the top.
        let center: CGFloat = 16
        for mood in moods {
            let eye = EyeExpression.for(mood)
            let top = center + eye.drop - eye.height / 2
            XCTAssertGreaterThanOrEqual(top - (eye.browLift + eye.browTilt / 2 + 1) * eye.brow, 3, "\(mood)")
            XCTAssertLessThanOrEqual(center + eye.drop + eye.height / 2, 28, "\(mood)")
        }
    }

    func testMixingInterpolatesAndExtrapolates() {
        let happy = EyeExpression.for(.happy)
        let panic = EyeExpression.for(.panic)
        XCTAssertEqual(happy.mixed(with: panic, by: 0), happy)
        XCTAssertEqual(happy.mixed(with: panic, by: 1), panic)
        let half = happy.mixed(with: panic, by: 0.5)
        XCTAssertEqual(half.height, (happy.height + panic.height) / 2, accuracy: 0.0001)
        XCTAssertEqual(half.roundness, (happy.roundness + panic.roundness) / 2, accuracy: 0.0001)
        XCTAssertEqual(half.brow, 0.5, accuracy: 0.0001)
        // A spring's overshoot pushes past the target instead of clamping to it.
        XCTAssertGreaterThan(happy.mixed(with: panic, by: 1.1).height, panic.height)
    }
}
