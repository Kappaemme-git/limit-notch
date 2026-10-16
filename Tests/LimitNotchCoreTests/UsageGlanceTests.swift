import Foundation
import XCTest
@testable import LimitNotchCore

final class UsageGlanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_160_000)

    private func glance(_ fields: String, updatedAgo: TimeInterval = 60,
                        selection: ServiceSelection = .auto) -> UsageGlance {
        let updated = ISO8601DateFormatter().string(from: now.addingTimeInterval(-updatedAgo))
        let json = #"{"updated_at":"\#(updated)","mood":"happy"\#(fields.isEmpty ? "" : ",")\#(fields)}"#
        return UsageGlance(StatusSnapshot.from(data: Data(json.utf8), at: now), selection: selection)
    }

    private let design = #""claude_5h":70,"claude_7d":17,"codex_5h":8,"codex_7d":3"#

    func testMutedRowShowsBothWeeklyWindowsLikeTheDesign() {
        let auto = glance(design)
        XCTAssertEqual(auto.hero?.title, "Claude")
        XCTAssertEqual(auto.others.map(\.title), ["Claude weekly", "Codex weekly"])
        // Picking Codex makes its highest window the hero; the row stays the same.
        let codex = glance(design, selection: .codex)
        XCTAssertEqual(codex.hero?.title, "Codex")
        XCTAssertEqual(codex.hero?.percent, 8)
        XCTAssertEqual(codex.others.map(\.title), ["Claude weekly", "Codex weekly"])
    }

    func testSelectionDrivesTheHeroAndTheMood() {
        let fields = #""claude_5h":30,"claude_7d":17,"codex_7d":90"#
        let auto = glance(fields)
        XCTAssertEqual(auto.hero?.title, "Codex weekly")
        XCTAssertEqual(auto.mood, .panic)
        let claude = glance(fields, selection: .claude)
        XCTAssertEqual(claude.hero?.title, "Claude")
        XCTAssertEqual(claude.hero?.percent, 30)
        XCTAssertEqual(claude.others.map(\.title), ["Claude weekly", "Codex weekly"])
        XCTAssertEqual(claude.mood, .happy)
        XCTAssertEqual(glance(#""claude_5h":70"#, selection: .claude).mood, .worried)
    }

    func testSelectedServiceWithoutData() {
        let codex = glance(#""claude_5h":30,"claude_7d":17"#, selection: .codex)
        XCTAssertNil(codex.hero)
        XCTAssertEqual(codex.others.map(\.title), ["Claude weekly"])
        XCTAssertEqual(codex.message(now: now), "No Codex usage reported yet")
        XCTAssertEqual(codex.mood, .sleeping)
    }

    func testSelectionRawValuesArePersistable() {
        XCTAssertEqual(ServiceSelection.allCases.map(\.label), ["Auto", "Claude", "Codex"])
        for selection in ServiceSelection.allCases {
            XCTAssertEqual(ServiceSelection(rawValue: selection.rawValue), selection)
        }
    }

    func testDebugScenariosMatchTheDesignColumns() {
        XCTAssertNil(DebugScenario(environment: [:]))
        XCTAssertEqual(DebugScenario(environment: ["LIMITNOTCH_DEBUG_MOOD": "Sleeping"]), .sleep)
        let expected: [(DebugScenario, CreatureState, String, String)] = [
            (.happy, .happy, "30%", "Resets in 3h 48m"),
            (.worried, .worried, "70%", "Resets in 1h 52m"),
            // Codex has room, so panic suggests switching instead of the design's "Resets in 41m".
            (.panic, .panic, "95%", "Switch to Codex soon"),
            (.sleep, .sleeping, "42%", "Last synced 47m ago")
        ]
        for (scenario, mood, percent, message) in expected {
            let glance = UsageGlance(scenario.snapshot(at: now))
            XCTAssertEqual(glance.mood, mood, "\(scenario)")
            XCTAssertEqual(UsageFormatting.percent(glance.hero?.percent), percent, "\(scenario)")
            XCTAssertEqual(glance.message(now: now), message, "\(scenario)")
            XCTAssertEqual(glance.others.map { "\($0.title) \(UsageFormatting.percent($0.percent))" },
                           ["Claude weekly 17%", "Codex weekly 3%"])
        }
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
        XCTAssertEqual(stale.message(now: now), "Last synced 2h ago")
        XCTAssertEqual(stale.mood, .sleeping)

        let missing = UsageGlance(.unavailable(nil))
        XCTAssertNil(missing.hero)
        XCTAssertEqual(missing.message(now: now), "Waiting for usage data")

        let incomplete = UsageGlance(StatusSnapshot.from(data: Data(#"{"claude_5h":40}"#.utf8), at: now))
        XCTAssertEqual(incomplete.freshness, .incomplete)
        XCTAssertNil(incomplete.hero)
        XCTAssertEqual(incomplete.message(now: now), "Usage data is incomplete")
    }
}
