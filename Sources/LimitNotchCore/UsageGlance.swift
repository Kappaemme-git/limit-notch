import Foundation

/// One reported usage window, such as Claude's 5-hour limit.
public struct UsageWindow: Equatable, Sendable {
    public enum Service: Equatable, Sendable {
        case claude
        case codex

        public var name: String { self == .claude ? "Claude" : "Codex" }
    }

    public let service: Service
    public let isWeekly: Bool
    public let percent: Double
    public let resetsAt: Date?

    public init(service: Service, isWeekly: Bool, percent: Double, resetsAt: Date?) {
        self.service = service
        self.isWeekly = isWeekly
        self.percent = percent
        self.resetsAt = resetsAt
    }

    /// "Claude", "Claude weekly", "Codex" or "Codex weekly".
    public var title: String { isWeekly ? "\(service.name) weekly" : service.name }
    public var tone: UsageTone { UsageTone(percent: percent) }

    /// Every window with a value, in display order: Claude 5h, Claude weekly, Codex 5h, Codex weekly.
    public static func all(in status: UsageStatus?) -> [UsageWindow] {
        guard let status else { return [] }
        let candidates: [(Service, Bool, Double?, Date?)] = [
            (.claude, false, status.claude5h, status.claude5hResetsAt),
            (.claude, true, status.claude7d, status.claude7dResetsAt),
            (.codex, false, status.codex5h, status.codex5hResetsAt),
            (.codex, true, status.codex7d, status.codex7dResetsAt)
        ]
        return candidates.compactMap { service, weekly, percent, resetsAt in
            percent.map { UsageWindow(service: service, isWeekly: weekly, percent: $0, resetsAt: resetsAt) }
        }
    }
}

/// What the expanded notch says: the most critical window, one plain-English line about it, and
/// the remaining windows.
public struct UsageGlance: Equatable, Sendable {
    public enum Freshness: Equatable, Sendable {
        case current
        case stale(updatedAt: Date?)
        /// No status.json yet.
        case missing
        /// status.json exists but has no usable timestamp or mood.
        case incomplete
    }

    public let freshness: Freshness
    /// The highest window; the earliest in display order wins a tie.
    public let hero: UsageWindow?
    public let others: [UsageWindow]

    public init(_ snapshot: StatusSnapshot) {
        let windows: [UsageWindow]
        switch snapshot {
        case .current(let status):
            freshness = .current
            windows = UsageWindow.all(in: status)
        case .stale(let status):
            freshness = .stale(updatedAt: status.updatedAt)
            windows = UsageWindow.all(in: status)
        case .unavailable(let status):
            freshness = status == nil ? .missing : .incomplete
            windows = []
        }
        let hero = windows.reduce(nil) { best, window in
            best.map { window.percent > $0.percent ? window : $0 } ?? window
        }
        self.hero = hero
        others = windows.filter { $0 != hero }
    }

    public var isCurrent: Bool { freshness == .current }

    /// "Resets in 3h 10m", "Switch to Codex soon", "Last updated 2h ago" and so on.
    public func message(now: Date) -> String {
        switch freshness {
        case .missing: return "Waiting for usage data"
        case .incomplete: return "Usage data is incomplete"
        case .stale(let updatedAt): return "Last updated \(UsageFormatting.age(updatedAt, now: now))"
        case .current: break
        }
        guard let hero else { return "No usage reported yet" }

        let reset = hero.resetsAt.map { date -> String in
            let time = UsageFormatting.reset(date, now: now)
            return time == "now" ? "resetting now" : "resets \(time)"
        }
        if hero.percent >= 100 {
            if let fallback = fallbackService { return "Limit reached · use \(fallback.name)" }
            return reset.map { "Limit reached · \($0)" } ?? "Limit reached"
        }
        if hero.tone == .critical, let fallback = fallbackService {
            return "Switch to \(fallback.name) soon"
        }
        if let reset { return reset.prefix(1).uppercased() + reset.dropFirst() }
        return hero.tone == .normal ? "Plenty of room" : "Getting close"
    }

    /// The other service, when it reports usage and every one of its windows is comfortably low.
    private var fallbackService: UsageWindow.Service? {
        guard let hero else { return nil }
        let other = others.filter { $0.service != hero.service }
        guard !other.isEmpty, other.allSatisfy({ $0.tone == .normal }) else { return nil }
        return other[0].service
    }
}
