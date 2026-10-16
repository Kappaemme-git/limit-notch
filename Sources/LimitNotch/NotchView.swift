import AppKit
import LimitNotchCore
import SwiftUI

/// Black notch extension. Collapsed it is the camera housing plus two thin ears, the mascot on
/// the left and a usage ring on the right; on hover it springs open into a Dynamic Island-style
/// panel whose outline morphs continuously from the notch shape.
struct NotchView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var notch: NotchState

    private enum Metrics {
        static let expandedMascot: CGFloat = 40
        static let inset: CGFloat = 20
        static let mascotGap: CGFloat = 14
        static let rowSpacing: CGFloat = 8
    }

    private var geometry: NotchGeometry { notch.geometry }
    private var expanded: Bool { notch.isExpanded }
    private var size: CGSize { expanded ? geometry.expandedSize : geometry.collapsedSize }
    private var status: UsageStatus? { store.snapshot.status }
    private var isCurrent: Bool {
        if case .current = store.snapshot { return true }
        return false
    }

    private var mascotDiameter: CGFloat {
        expanded ? Metrics.expandedMascot : geometry.earContentSize
    }

    private var mascotCenter: CGPoint {
        guard expanded else { return geometry.leftEarCenter }
        return CGPoint(
            x: Metrics.inset + Metrics.expandedMascot / 2,
            y: geometry.barHeight + (NotchGeometry.expandedContentHeight - 12) / 2
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            NotchBody(geometry: geometry, progress: expanded ? 1 : 0)
                .fill(Color.black.shadow(.inner(color: .white.opacity(expanded ? 0.11 : 0), radius: 5, y: -1.5)))

            if expanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -6))
                            .animation(.easeOut(duration: 0.24).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            }

            UsageRing(value: UsageFormatting.peak(status), dimmed: !isCurrent)
                .frame(width: geometry.earContentSize - 2, height: geometry.earContentSize - 2)
                .position(x: size.width - geometry.leftEarCenter.x, y: geometry.barHeight / 2)
                .opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 0.6 : 1)

            MascotView(state: store.snapshot.creatureState, diameter: mascotDiameter, isAnimating: notch.isAnimating)
                .position(mascotCenter)
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .contentShape(NotchBody(geometry: geometry, progress: expanded ? 1 : 0))
        .contextMenu {
            Button("Refresh Now") { store.refresh() }
            Divider()
            Button("Quit LimitNotch") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Hover to view usage and reset times")
    }

    // MARK: - Expanded panel

    private var expandedContent: some View {
        let full = geometry.expandedSize
        let sideWidth = (full.width - geometry.bodyWidth) / 2
        return TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(alignment: .leading, spacing: 0) {
                header(sideWidth: sideWidth)
                    .frame(height: geometry.barHeight)

                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    UsageRow(label: "Claude · 5h", value: status?.claude5h, resetsAt: status?.claude5hResetsAt,
                             dimmed: !isCurrent, now: timeline.date)
                    UsageRow(label: "Claude · week", value: status?.claude7d, resetsAt: status?.claude7dResetsAt,
                             dimmed: !isCurrent, now: timeline.date)
                    UsageRow(label: "Codex · week", value: status?.codex7d, resetsAt: status?.codex7dResetsAt,
                             dimmed: !isCurrent, now: timeline.date)
                    Text(footerText(now: timeline.date))
                        .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, -1)
                }
                .padding(.top, 9)
                .padding(.leading, Metrics.inset + Metrics.expandedMascot + Metrics.mascotGap)
                .padding(.trailing, Metrics.inset)
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
    }

    /// Title and mood on either side of the camera housing.
    private func header(sideWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("LimitNotch")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.leading, Metrics.inset)
                .frame(width: sideWidth, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(moodColor).frame(width: 6, height: 6)
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(moodColor)
            }
            .padding(.trailing, Metrics.inset)
            .frame(width: sideWidth, alignment: .trailing)
        }
        .lineLimit(1)
    }

    // MARK: - Text

    private var statusTitle: String {
        switch store.snapshot {
        case .current:
            switch store.snapshot.creatureState {
            case .happy: return "All good"
            case .worried: return "Getting close"
            case .panic: return "Near limit"
            case .sleeping: return "Asleep"
            }
        case .stale: return "Asleep"
        case .unavailable: return "No data"
        }
    }

    private func footerText(now: Date) -> String {
        switch store.snapshot {
        case .current(let status):
            let age = UsageFormatting.age(status.claudeDataAt ?? status.updatedAt, now: now)
            let updated = "Updated \(age)"
            return UsageFormatting.sourceLabel(status.claudeSource).map { "\(updated) · \($0)" } ?? updated
        case .stale(let status):
            return "Data is over 1h old · updated \(UsageFormatting.age(status.updatedAt, now: now))"
        case .unavailable(nil):
            return "Waiting for ~/.usage-watcher/status.json"
        case .unavailable:
            return "status.json has no valid updated_at, mood or level"
        }
    }

    private var moodColor: Color {
        guard isCurrent else { return Color(white: 0.6) }
        switch store.snapshot.creatureState {
        case .happy: return Palette.green
        case .worried: return Palette.yellow
        case .panic: return Palette.red
        case .sleeping: return Color(white: 0.6)
        }
    }

    private var accessibilitySummary: String {
        let usage = [
            "Claude 5 hours \(UsageFormatting.percent(status?.claude5h))",
            "Claude week \(UsageFormatting.percent(status?.claude7d))",
            "Codex week \(UsageFormatting.percent(status?.codex7d))"
        ].joined(separator: ", ")
        return "LimitNotch: \(statusTitle). \(usage)"
    }
}

/// Apple's dark-mode system colors, so the bars read like native UI.
enum Palette {
    static let green = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let yellow = Color(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255)
    static let red = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)

    static func color(for tone: UsageTone) -> Color {
        switch tone {
        case .normal: return green
        case .high: return yellow
        case .critical: return red
        }
    }
}

/// The black silhouette. `progress` animates, so the outline morphs continuously with the frame.
private struct NotchBody: Shape {
    let geometry: NotchGeometry
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(geometry.outline(progress: progress).path(in: rect))
    }
}

private struct UsageRow: View {
    let label: String
    let value: Double?
    let resetsAt: Date?
    let dimmed: Bool
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 4)
                Text(resetsAt == nil ? "" : "resets \(UsageFormatting.reset(resetsAt, now: now))")
                    .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                    .help(resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
                Text(UsageFormatting.percent(value))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(value == nil ? 0.35 : 0.95))
                    .numericTransition(value)
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .lineLimit(1)
            UsageBar(value: value, dimmed: dimmed)
                .frame(height: 5)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

private struct UsageBar: View {
    let value: Double?
    let dimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                if let value {
                    let color = dimmed ? Color(white: 0.55) : Palette.color(for: UsageTone(percent: value))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(proxy.size.width * min(value, 100) / 100, value > 0 ? 5 : 0))
                }
            }
        }
    }
}

private struct UsageRing: View {
    let value: Double?
    let dimmed: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: 2.2)
            if let value {
                Circle()
                    .trim(from: 0, to: max(min(value, 100) / 100, 0.02))
                    .stroke(
                        dimmed ? Color(white: 0.55) : Palette.color(for: UsageTone(percent: value)),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

private extension View {
    /// Rolls digits when a percentage changes (macOS 14+); a plain cross-fade on macOS 13.
    @ViewBuilder
    func numericTransition(_ value: Double?) -> some View {
        if #available(macOS 14, *) {
            contentTransition(.numericText(value: value ?? 0))
        } else {
            self
        }
    }
}
