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

/// The "Auto | Claude | Codex" switch in the expanded notch. Raw values are stored in UserDefaults.
public enum ServiceSelection: String, CaseIterable, Sendable {
    case auto
    case claude
    case codex

    public var label: String {
        switch self {
        case .auto: return "Auto"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    public var service: UsageWindow.Service? {
        switch self {
        case .auto: return nil
        case .claude: return .claude
        case .codex: return .codex
        }
    }
}

/// What the notch shows: the hero window for the selected service, one plain-English line about
/// it, the mascot's mood, and a quiet row with the other service.
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
    public let selection: ServiceSelection
    /// Every window of the selected service (of both on Auto), in display order.
    public let windows: [UsageWindow]
    /// The highest window of the selected service (of both on Auto); the earliest in display
    /// order wins a tie.
    public let hero: UsageWindow?
    /// The hero service's other window and the other service's weekly window, in display order.
    public let others: [UsageWindow]
    public let mood: CreatureState
    /// The other service, when it reports usage and all of it is comfortably low.
    private let fallbackService: UsageWindow.Service?

    public init(_ snapshot: StatusSnapshot, selection: ServiceSelection = .auto) {
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
        self.selection = selection

        let candidates = windows.filter { selection.service == nil || $0.service == selection.service }
        self.windows = candidates
        let hero = Self.highest(candidates)
        self.hero = hero

        let heroService = hero?.service ?? selection.service
        let sibling = windows.first { $0.service == heroService && $0 != hero }
        let rest = windows.filter { $0.service != heroService }
        let other = rest.first(where: \.isWeekly) ?? rest.first
        others = windows.filter { $0 == sibling || $0 == other }
        // Suggest the other service only when every one of its windows is comfortably low.
        fallbackService = !rest.isEmpty && rest.allSatisfy { $0.tone == .normal } ? rest[0].service : nil

        if freshness != .current {
            mood = .sleeping
        } else if selection == .auto {
            // Auto also honors the forecast and the writer's own mood.
            mood = snapshot.creatureState
        } else if let hero {
            switch hero.tone {
            case .normal: mood = .happy
            case .high: mood = .worried
            case .critical: mood = .panic
            }
        } else {
            mood = .sleeping
        }
    }

    public var isCurrent: Bool { freshness == .current }

    /// "Resets in 3h 10m", "Switch to Codex soon", "Last synced 47m ago" and so on.
    public func message(now: Date) -> String {
        switch freshness {
        case .missing: return "Waiting for usage data"
        case .incomplete: return "Usage data is incomplete"
        case .stale(let updatedAt): return "Last synced \(UsageFormatting.age(updatedAt, now: now))"
        case .current: break
        }
        guard let hero else {
            return selection.service.map { "No \($0.name) usage reported yet" } ?? "No usage reported yet"
        }

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

    private static func highest(_ windows: [UsageWindow]) -> UsageWindow? {
        windows.reduce(nil) { best, window in
            best.map { window.percent > $0.percent ? window : $0 } ?? window
        }
    }
}
