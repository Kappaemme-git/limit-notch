import Foundation
import XCTest
@testable import LimitNotchCore

final class UsageStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_160_000)

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    func testFinalWatcherSchemaParsesEveryFieldAndMoodOverridesLevel() throws {
        let updated = iso(now.addingTimeInterval(-30))
        let json = """
        {
          "claude_5h": 49.9,
          "claude_7d": 81.2,
          "codex_7d": 2.0,
          "claude_5h_resets_at": 1792169100,
          "claude_7d_resets_at": 1792255500,
          "codex_7d_resets_at": 1792655962,
          "claude_data_at": 1792159950,
          "codex_data_at": 1792159940,
          "claude_app": {"fh": 41.5, "sd": 62.3, "at": 1792159930},
          "level": "crit",
          "mood": "happy",
          "note": "  All systems normal  ",
          "updated_at": "\(updated)"
        }
        """
        let data = Data(json.utf8)
        let status = try UsageStatusParser.parse(data)
        XCTAssertEqual(status.claude5h, 49.9)
        XCTAssertEqual(status.claude7d, 81.2)
        XCTAssertEqual(status.codex7d, 2.0)
        XCTAssertEqual(status.claude5hResetsAt, Date(timeIntervalSince1970: 1_792_169_100))
        XCTAssertEqual(status.claude7dResetsAt, Date(timeIntervalSince1970: 1_792_255_500))
        XCTAssertEqual(status.codex7dResetsAt, Date(timeIntervalSince1970: 1_792_655_962))
        XCTAssertEqual(status.claudeDataAt, Date(timeIntervalSince1970: 1_792_159_950))
        XCTAssertEqual(status.codexDataAt, Date(timeIntervalSince1970: 1_792_159_940))
        XCTAssertEqual(status.claudeApp?.fh, 41.5)
        XCTAssertEqual(status.claudeApp?.sd, 62.3)
        XCTAssertEqual(status.claudeApp?.at, Date(timeIntervalSince1970: 1_792_159_930))
        XCTAssertEqual(status.note, "All systems normal")
        XCTAssertEqual(status.level, .crit)
        XCTAssertEqual(status.mood, .happy)
        XCTAssertEqual(StatusSnapshot.from(data: data, at: now), .current(status))
        XCTAssertEqual(StatusSnapshot.from(data: data, at: now).creatureState, .happy)
    }

    func testMoodPrecedenceAndLevelFallbackForEveryState() {
        let updated = iso(now)
        let cases: [(String?, String, CreatureState)] = [
            ("happy", "crit", .happy),
            ("worried", "ok", .worried),
            ("panic", "warn", .panic),
            (nil, "ok", .happy),
            (nil, "warn", .worried),
            (nil, "crit", .panic)
        ]
        for (mood, level, expected) in cases {
            let moodField = mood.map { "\"mood\":\"\($0)\"," } ?? ""
            let json = "{\(moodField)\"level\":\"\(level)\",\"updated_at\":\"\(updated)\"}"
            XCTAssertEqual(StatusSnapshot.from(data: Data(json.utf8), at: now).creatureState, expected)
        }
    }

    func testNullMissingAndInvalidOptionalValuesStayEmpty() throws {
        let updated = iso(now)
        let json = """
        {
          "claude_5h": null,
          "claude_7d": "n/a",
          "codex_7d": 130,
          "claude_5h_resets_at": null,
          "codex_7d_resets_at": null,
          "reset": {"claude_5h": 1792169100},
          "claude_data_at": null,
          "claude_app": {"fh": null, "sd": 12.0, "at": null},
          "note": null,
          "mood": null,
          "level": "ok",
          "updated_at": "\(updated)"
        }
        """
        let data = Data(json.utf8)
        let status = try UsageStatusParser.parse(data)
        XCTAssertNil(status.claude5h)
        XCTAssertNil(status.claude7d)
        XCTAssertNil(status.codex7d)
        XCTAssertNil(status.claude5hResetsAt)
        XCTAssertNil(status.claude7dResetsAt)
        XCTAssertNil(status.codex7dResetsAt)
        XCTAssertNil(status.claudeDataAt)
        XCTAssertNil(status.codexDataAt)
        XCTAssertNil(status.claudeApp?.fh)
        XCTAssertEqual(status.claudeApp?.sd, 12)
        XCTAssertNil(status.claudeApp?.at)
        XCTAssertNil(status.note)
        XCTAssertNil(status.mood)
        XCTAssertEqual(StatusSnapshot.from(data: data, at: now), .current(status))
    }

    func testOlderThanOneHourSleepsButRetainsValues() throws {
        let updated = iso(now.addingTimeInterval(-3_601))
        let json = "{\"claude_5h\":50,\"updated_at\":\"\(updated)\",\"level\":\"crit\",\"mood\":\"panic\"}"
        let data = Data(json.utf8)
        let status = try UsageStatusParser.parse(data)
        XCTAssertEqual(StatusSnapshot.from(data: data, at: now), .stale(status))
        XCTAssertEqual(StatusSnapshot.from(data: data, at: now).creatureState, .sleeping)
        XCTAssertEqual(StatusSnapshot.from(data: data, at: now).status?.claude5h, 50)

        let boundary = "{\"updated_at\":\"\(iso(now.addingTimeInterval(-3_600)))\",\"level\":\"ok\"}"
        XCTAssertEqual(StatusSnapshot.from(data: Data(boundary.utf8), at: now).creatureState, .happy)
    }

    func testMissingOrInvalidUpdateSleepsAndKeepsParsableValues() throws {
        let missing = Data(#"{"claude_5h":23,"mood":"happy"}"#.utf8)
        let status = try UsageStatusParser.parse(missing)
        XCTAssertNil(status.updatedAt)
        XCTAssertEqual(StatusSnapshot.from(data: missing, at: now), .unavailable(status))
        XCTAssertEqual(StatusSnapshot.from(data: missing, at: now).creatureState, .sleeping)
        XCTAssertEqual(StatusSnapshot.from(data: missing, at: now).status?.claude5h, 23)

        let invalid = Data(#"{"updated_at":"bad","level":"ok"}"#.utf8)
        XCTAssertEqual(StatusSnapshot.from(data: invalid, at: now).creatureState, .sleeping)
    }

    func testInvalidFileStateAndFutureUpdateSleep() {
        XCTAssertEqual(StatusSnapshot.from(data: nil, at: now), .unavailable(nil))
        XCTAssertEqual(StatusSnapshot.from(data: Data("broken".utf8), at: now), .unavailable(nil))
        XCTAssertEqual(StatusSnapshot.from(data: Data(#"{"level":"bad","updated_at":"2026-10-16T13:41:00Z"}"#.utf8), at: now), .unavailable(nil))
        XCTAssertEqual(StatusSnapshot.from(data: Data(#"{"mood":"unknown","level":"ok"}"#.utf8), at: now), .unavailable(nil))

        let noState = "{\"updated_at\":\"\(iso(now))\",\"level\":null,\"mood\":null}"
        XCTAssertEqual(StatusSnapshot.from(data: Data(noState.utf8), at: now).creatureState, .sleeping)

        let future = "{\"updated_at\":\"\(iso(now.addingTimeInterval(301)))\",\"level\":\"ok\"}"
        XCTAssertEqual(StatusSnapshot.from(data: Data(future.utf8), at: now).creatureState, .sleeping)
    }

    // MARK: - Live Claude data (claude_live.json)

    private func liveData(fiveHour: Double, dataAt: Date, source: String = "claude-code-oauth-usage") -> Data {
        Data("""
        {"reading": {"claude_5h": \(fiveHour), "claude_7d": 15, "claude_5h_resets_at": 1792174200,
                     "claude_7d_resets_at": 1792576800, "claude_data_at": \(Int(dataAt.timeIntervalSince1970)),
                     "claude_source": "\(source)"},
         "error": null, "failures": 0}
        """.utf8)
    }

    private func staleDesktopStatus() -> Data {
        Data("""
        {"claude_5h": 15, "claude_7d": 13, "codex_7d": 3, "codex_7d_resets_at": 1792655962,
         "claude_source": "claude-desktop-app", "claude_data_at": "\(iso(now.addingTimeInterval(-1500)))",
         "level": "ok", "mood": "happy", "note": "All good: Claude 5h 15%",
         "updated_at": "\(iso(now.addingTimeInterval(-600)))"}
        """.utf8)
    }

    func testNewerLiveReadingReplacesStaleClaudeValues() {
        let snapshot = StatusSnapshot.from(data: staleDesktopStatus(),
                                           liveData: liveData(fiveHour: 43, dataAt: now.addingTimeInterval(-20)), at: now)
        guard case .current(let status) = snapshot else { return XCTFail("expected current, got \(snapshot)") }
        XCTAssertEqual(status.claude5h, 43)
        XCTAssertEqual(status.claude7d, 15)
        XCTAssertEqual(status.claude5hResetsAt, Date(timeIntervalSince1970: 1_792_174_200))
        XCTAssertEqual(status.claudeSource, "claude-code-oauth-usage")
        XCTAssertEqual(status.claudeDataAt, now.addingTimeInterval(-20))
        // Codex data is kept; the stale note is dropped.
        XCTAssertEqual(status.codex7d, 3)
        XCTAssertEqual(status.codex7dResetsAt, Date(timeIntervalSince1970: 1_792_655_962))
        XCTAssertNil(status.note)
        XCTAssertEqual(status.updatedAt, now.addingTimeInterval(-20))
    }

    func testLiveReadingRecomputesTheMood() {
        let worried = StatusSnapshot.from(data: staleDesktopStatus(),
                                          liveData: liveData(fiveHour: 75, dataAt: now), at: now)
        XCTAssertEqual(worried.creatureState, .worried)
        let panic = StatusSnapshot.from(data: staleDesktopStatus(),
                                        liveData: liveData(fiveHour: 95, dataAt: now), at: now)
        XCTAssertEqual(panic.creatureState, .panic)
    }

    func testOlderLiveReadingIsIgnored() throws {
        let status = try UsageStatusParser.parse(staleDesktopStatus())
        let snapshot = StatusSnapshot.from(data: staleDesktopStatus(),
                                           liveData: liveData(fiveHour: 43, dataAt: now.addingTimeInterval(-3000)), at: now)
        XCTAssertEqual(snapshot, .current(status))
        XCTAssertEqual(snapshot.status?.claude5h, 15)
    }

    func testLiveReadingWorksWithoutStatusFile() {
        let snapshot = StatusSnapshot.from(data: nil, liveData: liveData(fiveHour: 43, dataAt: now), at: now)
        XCTAssertEqual(snapshot.status?.claude5h, 43)
        XCTAssertNil(snapshot.status?.codex7d)
        XCTAssertEqual(snapshot.creatureState, .happy)
    }

    func testInvalidLiveFileFallsBackToStatusFile() {
        for junk in ["broken", #"{"reading": null}"#, #"{"reading": {"claude_5h": 43}}"#] {
            let snapshot = StatusSnapshot.from(data: staleDesktopStatus(), liveData: Data(junk.utf8), at: now)
            XCTAssertEqual(snapshot.status?.claude5h, 15, junk)
        }
    }

    func testSourceLabels() {
        XCTAssertEqual(UsageFormatting.sourceLabel("claude-code-oauth-usage"), "Claude live")
        XCTAssertEqual(UsageFormatting.sourceLabel("claude-desktop-app"), "Claude app")
        XCTAssertNil(UsageFormatting.sourceLabel(nil))
    }
}
