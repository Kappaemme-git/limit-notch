import Foundation
import XCTest
@testable import LimitNotchCore

final class UsageGlanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_160_000)

    private func glance(_ fields: String, updatedAgo: TimeInterval = 60) -> UsageGlance {
        let updated = ISO8601DateFormatter().string(from: now.addingTimeInterval(-updatedAgo))
        let json = #"{"updated_at":"\#(updated)","mood":"happy"\#(fields.isEmpty ? "" : ",")\#(fields)}"#
        return UsageGlance(StatusSnapshot.from(data: Data(json.utf8), at: now))
    }

    func testHeroIsTheHighestWindowAndTheRestAreSecondary() {
        let result = glance(#""claude_5h":69,"claude_7d":34,"codex_7d":12,"claude_5h_resets_at":\#(Int(now.timeIntervalSince1970) + 3 * 3600 + 10 * 60)"#)
        XCTAssertEqual(result.hero?.title, "Claude")
        XCTAssertEqual(result.hero?.percent, 69)
        XCTAssertEqual(result.others.map(\.title), ["Claude weekly", "Codex weekly"])
        XCTAssertEqual(result.message(now: now), "Resets in 3h 10m")
    }

    func testTiesKeepTheShorterClaudeWindow() {
        let result = glance(#""claude_5h":40,"claude_7d":40,"codex_7d":40"#)
        XCTAssertEqual(result.hero?.title, "Claude")
        XCTAssertEqual(result.others.map(\.title), ["Claude weekly", "Codex weekly"])
    }

    func testCriticalWindowSuggestsTheOtherServiceWhenItHasRoom() {
        XCTAssertEqual(glance(#""claude_5h":88,"codex_7d":12"#).message(now: now), "Switch to Codex soon")
        XCTAssertEqual(glance(#""codex_7d":90,"claude_5h":20,"claude_7d":30"#).message(now: now), "Switch to Claude soon")
        // Codex is busy too, so fall back to the reset time.
        let reset = Int(now.timeIntervalSince1970) + 42 * 60
        XCTAssertEqual(glance(#""claude_5h":88,"codex_7d":70,"claude_5h_resets_at":\#(reset)"#).message(now: now),
                       "Resets in 42m")
        XCTAssertEqual(glance(#""claude_5h":88"#).message(now: now), "Getting close")
    }

    func testLimitReached() {
        let reset = Int(now.timeIntervalSince1970) + 2 * 3600
        XCTAssertEqual(glance(#""claude_5h":100,"codex_7d":10"#).message(now: now), "Limit reached · use Codex")
        XCTAssertEqual(glance(#""claude_5h":100,"claude_5h_resets_at":\#(reset)"#).message(now: now),
                       "Limit reached · resets in 2h 0m")
        XCTAssertEqual(glance(#""claude_5h":100"#).message(now: now), "Limit reached")
    }

    func testQuietAndPassedResets() {
        XCTAssertEqual(glance(#""claude_5h":12"#).message(now: now), "Plenty of room")
        let passed = Int(now.timeIntervalSince1970) - 30
        XCTAssertEqual(glance(#""claude_5h":12,"claude_5h_resets_at":\#(passed)"#).message(now: now), "Resetting now")
        XCTAssertEqual(glance("").message(now: now), "No usage reported yet")
        XCTAssertNil(glance("").hero)
    }

    func testStaleAndUnavailableData() {
        let stale = glance(#""claude_5h":50"#, updatedAgo: 2 * 3600)
        XCTAssertFalse(stale.isCurrent)
        XCTAssertEqual(stale.hero?.percent, 50)
        XCTAssertEqual(stale.message(now: now), "Last updated 2h ago")

        let missing = UsageGlance(.unavailable(nil))
        XCTAssertNil(missing.hero)
        XCTAssertEqual(missing.message(now: now), "Waiting for usage data")

        let incomplete = UsageGlance(StatusSnapshot.from(data: Data(#"{"claude_5h":40}"#.utf8), at: now))
        XCTAssertEqual(incomplete.freshness, .incomplete)
        XCTAssertNil(incomplete.hero)
        XCTAssertEqual(incomplete.message(now: now), "Usage data is incomplete")
    }
}
