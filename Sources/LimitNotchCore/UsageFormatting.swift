import Foundation

public enum UsageTone: Equatable, Sendable {
    case normal
    case high
    case critical

    public init(percent: Double) {
        switch percent {
        case ..<60: self = .normal
        case ..<85: self = .high
        default: self = .critical
        }
    }
}

public enum UsageFormatting {
    /// "42%", or "—" when the value is missing. Values just under 100 never round up to 100%.
    public static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        let rounded = value < 100 ? min(value.rounded(), 99) : 100
        return "\(Int(rounded))%"
    }

    /// Time until a reset: "in 42m", "in 3h 12m", "in 2d 4h", "now" once passed, or "—" when unknown.
    public static func reset(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "in \(hours)h \(minutes % 60)m" }
        return "in \(hours / 24)d \(hours % 24)h"
    }

    /// Age of the data: "just now", "4m ago", "3h ago", "2d ago", or "—" when unknown.
    public static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 24 * 60 { return "\(minutes / 60)h ago" }
        return "\(minutes / (24 * 60))d ago"
    }

    /// Short name for `claude_source`, shown in the expanded footer.
    public static func sourceLabel(_ source: String?) -> String? {
        switch source {
        case "claude-code-oauth-usage": return "Claude live"
        case "claude-code-statusline": return "Claude Code"
        case "claude-desktop-app": return "Claude app"
        default: return nil
        }
    }

    /// The highest reported usage window.
    public static func peak(_ status: UsageStatus?) -> Double? {
        [status?.claude5h, status?.claude7d, status?.codex5h, status?.codex7d].compactMap { $0 }.max()
    }
}
