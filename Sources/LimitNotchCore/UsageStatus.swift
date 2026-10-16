import Foundation
import CoreFoundation

public enum UsageLevel: String, Equatable, Sendable {
    case ok
    case warn
    case crit
}

public enum UsageMood: String, Equatable, Sendable {
    case happy
    case worried
    case panic
}

public enum CreatureState: Equatable, Sendable {
    case happy
    case worried
    case panic
    case sleeping
}

public struct ClaudeAppUsage: Equatable, Sendable {
    public let fh: Double?
    public let sd: Double?
    public let at: Date?
}

public struct UsageStatus: Equatable, Sendable {
    public let claude5h: Double?
    public let claude7d: Double?
    public let codex5h: Double?
    public let codex7d: Double?
    public let claude5hResetsAt: Date?
    public let claude7dResetsAt: Date?
    public let codex5hResetsAt: Date?
    public let codex7dResetsAt: Date?
    public let claudeDataAt: Date?
    public let claudeSource: String?
    public let codexDataAt: Date?
    public let claudeApp: ClaudeAppUsage?
    public let level: UsageLevel?
    public let mood: UsageMood?
    public let note: String?
    public let updatedAt: Date?
    public let forecastWillHitLimit: Bool

    public var creatureState: CreatureState? {
        if let peak = [claude5h, claude7d, codex5h, codex7d].compactMap({ $0 }).max() {
            if peak >= 85 { return .panic }
            if peak >= 60 || forecastWillHitLimit { return .worried }
            return .happy
        }
        if let mood {
            switch mood {
            case .happy: return .happy
            case .worried: return .worried
            case .panic: return .panic
            }
        }
        if let level {
            switch level {
            case .ok: return .happy
            case .warn: return .worried
            case .crit: return .panic
            }
        }
        return nil
    }

    /// With the helpers syncing every 60 s, half an hour without a sync means they stopped.
    public static let staleAfter: TimeInterval = 30 * 60

    public func isFresh(at date: Date) -> Bool {
        guard let updatedAt else { return false }
        let age = date.timeIntervalSince(updatedAt)
        return age >= -300 && age <= Self.staleAfter
    }
}

public enum StatusSnapshot: Equatable, Sendable {
    case current(UsageStatus)
    case stale(UsageStatus)
    case unavailable(UsageStatus?)

    public var status: UsageStatus? {
        switch self {
        case .current(let status), .stale(let status): return status
        case .unavailable(let status): return status
        }
    }

    public var creatureState: CreatureState {
        if case .current(let status) = self {
            return status.creatureState ?? .sleeping
        }
        return .sleeping
    }

    /// Builds the snapshot from status.json and, when it holds newer Claude data, the
    /// claude_live.json written by the live helper.
    public static func from(data: Data?, liveData: Data? = nil, at date: Date) -> StatusSnapshot {
        let live = liveData.flatMap(LiveClaudeReading.parse)
        let parsed = data.flatMap { try? UsageStatusParser.parse($0) }
        guard let status = UsageStatus.merging(parsed, live: live) else {
            return .unavailable(nil)
        }
        guard status.creatureState != nil, let updatedAt = status.updatedAt,
              updatedAt.timeIntervalSince(date) <= 300 else {
            return .unavailable(status)
        }
        return status.isFresh(at: date) ? .current(status) : .stale(status)
    }
}

/// The latest reading from claude_live.json: `{"reading": {claude_5h, claude_7d, ...}}`.
public struct LiveClaudeReading: Equatable, Sendable {
    public let fiveHour: Double?
    public let sevenDay: Double?
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?
    public let dataAt: Date
    public let source: String?

    public static func parse(_ data: Data) -> LiveClaudeReading? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reading = object["reading"] as? [String: Any],
              let status = try? UsageStatusParser.parse(JSONSerialization.data(withJSONObject: reading)),
              let dataAt = status.claudeDataAt,
              status.claude5h != nil || status.claude7d != nil
        else { return nil }
        return LiveClaudeReading(
            fiveHour: status.claude5h,
            sevenDay: status.claude7d,
            fiveHourResetsAt: status.claude5hResetsAt,
            sevenDayResetsAt: status.claude7dResetsAt,
            dataAt: dataAt,
            source: status.claudeSource
        )
    }
}

extension UsageStatus {
    /// Applies a live Claude reading when it is newer than the Claude data in status.json. The
    /// mood is then recomputed from the highest window, as the file's mood describes older data.
    public static func merging(_ status: UsageStatus?, live: LiveClaudeReading?) -> UsageStatus? {
        guard let live else { return status }
        if let existing = status?.claudeDataAt, existing >= live.dataAt { return status }
        let codex = status?.codex7d
        let peak = [live.fiveHour, live.sevenDay, status?.codex5h, codex].compactMap { $0 }.max() ?? 0
        let level: UsageLevel
        switch UsageTone(percent: peak) {
        case .normal: level = status?.forecastWillHitLimit == true ? .warn : .ok
        case .high: level = .warn
        case .critical: level = .crit
        }
        let updatedAt = [status?.updatedAt, live.dataAt].compactMap { $0 }.max()
        return UsageStatus(
            claude5h: live.fiveHour,
            claude7d: live.sevenDay,
            codex5h: status?.codex5h,
            codex7d: codex,
            claude5hResetsAt: live.fiveHourResetsAt,
            claude7dResetsAt: live.sevenDayResetsAt,
            codex5hResetsAt: status?.codex5hResetsAt,
            codex7dResetsAt: status?.codex7dResetsAt,
            claudeDataAt: live.dataAt,
            claudeSource: live.source,
            codexDataAt: status?.codexDataAt,
            claudeApp: status?.claudeApp,
            level: level,
            mood: nil,
            note: nil,
            updatedAt: updatedAt,
            forecastWillHitLimit: status?.forecastWillHitLimit ?? false
        )
    }
}

public enum UsageStatusParser {
    public enum ParseError: Error, Equatable {
        case invalidJSON
        case invalidLevel
        case invalidMood
    }

    public static func parse(_ data: Data) throws -> UsageStatus {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        let level: UsageLevel?
        if let raw = object["level"], !(raw is NSNull) {
            guard let value = raw as? String, let parsed = UsageLevel(rawValue: value) else {
                throw ParseError.invalidLevel
            }
            level = parsed
        } else {
            level = nil
        }

        let mood: UsageMood?
        if let raw = object["mood"], !(raw is NSNull) {
            guard let value = raw as? String, let parsed = UsageMood(rawValue: value) else {
                throw ParseError.invalidMood
            }
            mood = parsed
        } else {
            mood = nil
        }

        let app = object["claude_app"] as? [String: Any]
        return UsageStatus(
            claude5h: percentage(from: object["claude_5h"]),
            claude7d: percentage(from: object["claude_7d"]),
            codex5h: percentage(from: object["codex_5h"]),
            codex7d: percentage(from: object["codex_7d"]),
            claude5hResetsAt: unixSeconds(from: object["claude_5h_resets_at"]),
            claude7dResetsAt: unixSeconds(from: object["claude_7d_resets_at"]),
            codex5hResetsAt: unixSeconds(from: object["codex_5h_resets_at"]),
            codex7dResetsAt: unixSeconds(from: object["codex_7d_resets_at"]),
            claudeDataAt: date(from: object["claude_data_at"]),
            claudeSource: (object["claude_source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            codexDataAt: date(from: object["codex_data_at"]),
            claudeApp: app.map {
                ClaudeAppUsage(
                    fh: percentage(from: $0["fh"]),
                    sd: percentage(from: $0["sd"]),
                    at: date(from: $0["at"])
                )
            },
            level: level,
            mood: mood,
            note: (object["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            updatedAt: isoDate(from: object["updated_at"]),
            forecastWillHitLimit: ["claude_5h_forecast_100", "claude_7d_forecast_100",
                                   "codex_5h_forecast_100", "codex_7d_forecast_100"]
                .contains { object[$0] as? Bool == true }
        )
    }

    private static func percentage(from raw: Any?) -> Double? {
        let number: Double
        if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            number = value.doubleValue
        } else if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(trimmed) else { return nil }
            number = parsed
        } else {
            return nil
        }
        return number.isFinite && (0...100).contains(number) ? number : nil
    }

    private static func unixSeconds(from raw: Any?) -> Date? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
            return nil
        }
        let seconds = value.doubleValue
        guard seconds.isFinite, seconds > 0, seconds < 100_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func date(from raw: Any?) -> Date? {
        unixSeconds(from: raw) ?? isoDate(from: raw)
    }

    private static func isoDate(from raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
