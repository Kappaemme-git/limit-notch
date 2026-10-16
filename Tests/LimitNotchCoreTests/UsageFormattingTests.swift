import Foundation
import XCTest
@testable import LimitNotchCore

final class UsageFormattingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_160_000)

    func testResetHandlesNullPastAndFutureTimes() {
        XCTAssertEqual(UsageFormatting.reset(nil, now: now), "—")
        XCTAssertEqual(UsageFormatting.reset(now.addingTimeInterval(-10), now: now), "now")
        XCTAssertEqual(UsageFormatting.reset(now.addingTimeInterval(42 * 60), now: now), "in 42m")
        XCTAssertEqual(UsageFormatting.reset(now.addingTimeInterval(3 * 3600 + 12 * 60), now: now), "in 3h 12m")
        XCTAssertEqual(UsageFormatting.reset(now.addingTimeInterval(2 * 86_400 + 4 * 3600 + 30), now: now), "in 2d 4h")
    }

    func testPercentRoundsWithoutFakingAFullLimit() {
        XCTAssertEqual(UsageFormatting.percent(nil), "—")
        XCTAssertEqual(UsageFormatting.percent(0), "0%")
        XCTAssertEqual(UsageFormatting.percent(49.6), "50%")
        XCTAssertEqual(UsageFormatting.percent(99.7), "99%")
        XCTAssertEqual(UsageFormatting.percent(100), "100%")
    }

    func testAgeAndPeak() {
        XCTAssertEqual(UsageFormatting.age(nil, now: now), "—")
        XCTAssertEqual(UsageFormatting.age(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(UsageFormatting.age(now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(UsageFormatting.age(now.addingTimeInterval(-3 * 3600), now: now), "3h ago")

        let status = try? UsageStatusParser.parse(Data(#"{"claude_5h":12,"claude_7d":null,"codex_7d":40}"#.utf8))
        XCTAssertEqual(UsageFormatting.peak(status), 40)
        XCTAssertNil(UsageFormatting.peak(nil))
    }

    func testToneThresholds() {
        XCTAssertEqual(UsageTone(percent: 10), .normal)
        XCTAssertEqual(UsageTone(percent: 70), .high)
        XCTAssertEqual(UsageTone(percent: 95), .critical)
    }
}
