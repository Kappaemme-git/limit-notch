import Foundation

/// Fixed usage for screenshots and design review, chosen with `LIMITNOTCH_DEBUG_MOOD`. The values
/// match the four columns of design/Main.dc.html.
public enum DebugScenario: String, CaseIterable, Sendable {
    case happy
    case worried
    case panic
    case sleep

    public init?(environment: [String: String]) {
        guard let raw = environment["LIMITNOTCH_DEBUG_MOOD"]?.lowercased() else { return nil }
        self.init(rawValue: raw == "sleeping" ? "sleep" : raw)
    }

    public func snapshot(at now: Date) -> StatusSnapshot {
        let claude: Int
        let resetMinutes: Int
        var updatedAgo: TimeInterval = 20
        switch self {
        case .happy: (claude, resetMinutes) = (30, 3 * 60 + 48)
        case .worried: (claude, resetMinutes) = (70, 60 + 52)
        case .panic: (claude, resetMinutes) = (95, 41)
        case .sleep: (claude, resetMinutes, updatedAgo) = (42, 60, 47 * 60 + 5)
        }
        // Half a minute early, so the minute-rounded countdown reads exactly as in the design.
        let unix = { (minutes: Int) in Int(now.timeIntervalSince1970) + minutes * 60 - 30 }
        let updated = ISO8601DateFormatter().string(from: now.addingTimeInterval(-updatedAgo))
        let json = """
        {"claude_5h": \(claude), "claude_7d": 17, "codex_5h": 8, "codex_7d": 3,
         "claude_5h_resets_at": \(unix(resetMinutes)), "claude_7d_resets_at": \(unix(4 * 24 * 60)),
         "codex_5h_resets_at": \(unix(4 * 60 + 10)), "codex_7d_resets_at": \(unix(6 * 24 * 60)),
         "updated_at": "\(updated)"}
        """
        return StatusSnapshot.from(data: Data(json.utf8), at: now)
    }
}
