import XCTest
@testable import LimitNotchCore

final class EyeExpressionTests: XCTestCase {
    func testHappyEyesAreSoftAndRound() {
        let eye = EyeExpression.for(.happy)
        XCTAssertLessThan(eye.height / eye.width, 1.3)
        XCTAssertEqual(eye.outerLid + eye.innerLid, 0)
        XCTAssertEqual(eye.closed, 0)
    }

    func testWorriedEyesDroopAtTheOuterCorner() {
        let eye = EyeExpression.for(.worried)
        XCTAssertGreaterThan(eye.outerLid, eye.innerLid + 0.2)
    }

    func testPanicEyesAreTheWidestAndGlowMost() {
        let panic = EyeExpression.for(.panic)
        for mood in [CreatureState.happy, .worried, .sleeping] {
            let other = EyeExpression.for(mood)
            XCTAssertGreaterThan(panic.height, other.height, "\(mood)")
            XCTAssertGreaterThan(panic.glow, other.glow, "\(mood)")
        }
        XCTAssertEqual(panic.outerLid + panic.innerLid, 0)
    }

    func testSleepingEyesAreClosedLines() {
        let eye = EyeExpression.for(.sleeping)
        XCTAssertEqual(eye.closed, 1)
        XCTAssertLessThan(eye.height, 4)
        XCTAssertEqual(eye.glow, 0)
        for mood in [CreatureState.happy, .worried, .panic] {
            XCTAssertEqual(EyeExpression.for(mood).closed, 0, "\(mood)")
        }
    }
}
