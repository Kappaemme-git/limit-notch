import AppKit
import LimitNotchCore
import SwiftUI

/// Black notch extension. Collapsed it hugs the camera housing with the mascot in the left ear and
/// a usage gauge in the right one; on hover it springs open into a Dynamic Island-style panel.
struct NotchView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var notch: NotchState

    private enum Metrics {
        static let collapsedTopRadius: CGFloat = 6
        static let collapsedBottomRadius: CGFloat = 10
        static let expandedTopRadius: CGFloat = 10
        static let expandedBottomRadius: CGFloat = 24
        static let expandedMascot: CGFloat = 44
        static let contentInset: CGFloat = 16
    }

    private var geometry: NotchGeometry { notch.geometry }
    private var expanded: Bool { notch.isExpanded }
    private var size: CGSize { geometry.panelFrame(expanded: expanded).size }
    private var status: UsageStatus? { store.snapshot.status }
    private var isCurrent: Bool {
        if case .current = store.snapshot { return true }
        return false
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: expanded ? Metrics.expandedTopRadius : Metrics.collapsedTopRadius,
            bottomRadius: expanded ? Metrics.expandedBottomRadius : Metrics.collapsedBottomRadius
        )
    }

    /// Width of each side of the top band that the camera housing does not cover.
    private var bandSideWidth: CGFloat {
        (size.width - geometry.notchSize.width) / 2
    }

    private var mascotDiameter: CGFloat {
        expanded ? Metrics.expandedMascot : geometry.mascotDiameter
    }

    private var mascotCenter: CGPoint {
        if expanded {
            return CGPoint(
                x: Metrics.expandedTopRadius + Metrics.contentInset + Metrics.expandedMascot / 2,
                y: geometry.barHeight + 50
            )
        }
        return CGPoint(x: earCenterX, y: geometry.barHeight / 2)
    }

    private var earCenterX: CGFloat {
        Metrics.collapsedTopRadius + (NotchGeometry.earWidth - Metrics.collapsedTopRadius) / 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape.fill(Color.black)

            if expanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            }

            UsageRing(value: UsageFormatting.peak(status), dimmed: !isCurrent)
                .frame(width: 13, height: 13)
                .position(x: size.width - earCenterX, y: geometry.barHeight / 2)
                .opacity(expanded ? 0 : 1)

            MascotView(state: store.snapshot.creatureState, diameter: mascotDiameter, isAnimating: notch.isAnimating)
                .position(mascotCenter)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onTapGesture { notch.toggleExpanded() }
        .contextMenu {
            Button("Refresh Now") { store.refresh() }
            Divider()
            Button("Quit LimitNotch") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Hover or click to view usage and reset times")
    }

    // MARK: - Expanded panel

    private var expandedContent: some View {
        let full = geometry.panelFrame(expanded: true).size
        return VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: geometry.barHeight)

            VStack(alignment: .leading, spacing: 9) {
                usageRow("Claude · 5h", value: status?.claude5h, resetsAt: status?.claude5hResetsAt)
                usageRow("Claude · 7d", value: status?.claude7d, resetsAt: status?.claude7dResetsAt)
                usageRow("Codex · 7d", value: status?.codex7d, resetsAt: status?.codex7dResetsAt)
                footer
                    .padding(.top, 3)
            }
            .padding(.top, 14)
            .padding(.leading, Metrics.expandedTopRadius + Metrics.contentInset * 2 + Metrics.expandedMascot)
            .padding(.trailing, Metrics.expandedTopRadius + Metrics.contentInset)
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        .clipShape(shape)
    }

    /// Title and mood on either side of the camera housing.
    private var header: some View {
        HStack(spacing: 0) {
            Text("LimitNotch")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, Metrics.expandedTopRadius + Metrics.contentInset)
                .frame(width: bandSideWidth, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(moodColor).frame(width: 6, height: 6)
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(moodColor)
            }
            .padding(.trailing, Metrics.expandedTopRadius + Metrics.contentInset)
            .frame(width: bandSideWidth, alignment: .trailing)
        }
        .lineLimit(1)
    }

    private func usageRow(_ label: String, value: Double?, resetsAt: Date?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 74, alignment: .leading)
            UsageBar(value: value, dimmed: !isCurrent)
                .frame(height: 6)
            Text(UsageFormatting.percent(value))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(value == nil ? 0.4 : 0.95))
                .frame(width: 36, alignment: .trailing)
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8, weight: .semibold))
                Text(UsageFormatting.reset(resetsAt, now: Date()))
                    .font(.system(size: 10).monospacedDigit())
            }
            .foregroundStyle(.white.opacity(resetsAt == nil ? 0.32 : 0.55))
            .frame(width: 74, alignment: .leading)
            .help(resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Reset time unknown")
        }
        .lineLimit(1)
    }

    private var footer: some View {
        Text(footerText)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Text

    private var statusTitle: String {
        switch store.snapshot {
        case .current:
            switch store.snapshot.creatureState {
            case .happy: return "All good"
            case .worried: return "Getting close"
            case .panic: return "Near the limit"
            case .sleeping: return "Asleep"
            }
        case .stale: return "Asleep"
        case .unavailable: return "No data"
        }
    }

    private var footerText: String {
        switch store.snapshot {
        case .current(let status):
            let updated = "Updated \(UsageFormatting.age(status.updatedAt, now: Date()))"
            return status.note.map { "\(updated) · \($0)" } ?? updated
        case .stale(let status):
            return "Data is over 1h old · updated \(UsageFormatting.age(status.updatedAt, now: Date()))"
        case .unavailable(nil):
            return "Waiting for ~/.usage-watcher/status.json"
        case .unavailable:
            return "status.json has no valid updated_at, mood or level"
        }
    }

    private var moodColor: Color {
        guard isCurrent else { return Color(white: 0.6) }
        switch store.snapshot.creatureState {
        case .happy: return Color(red: 0.29, green: 0.85, blue: 0.55)
        case .worried: return Palette.amber
        case .panic: return Palette.red
        case .sleeping: return Color(white: 0.6)
        }
    }

    private var accessibilitySummary: String {
        let usage = [
            "Claude 5 hours \(UsageFormatting.percent(status?.claude5h))",
            "Claude 7 days \(UsageFormatting.percent(status?.claude7d))",
            "Codex 7 days \(UsageFormatting.percent(status?.codex7d))"
        ].joined(separator: ", ")
        return "LimitNotch: \(statusTitle). \(usage)"
    }
}

enum Palette {
    static let blue = MascotRenderer.lightBlue
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let red = Color(red: 0.94, green: 0.27, blue: 0.27)

    static func color(for tone: UsageTone) -> Color {
        switch tone {
        case .normal: return blue
        case .high: return amber
        case .critical: return red
        }
    }
}

private struct UsageBar: View {
    let value: Double?
    let dimmed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if let value {
                    Capsule()
                        .fill(Palette.color(for: UsageTone(percent: value)))
                        .frame(width: max(proxy.size.width * value / 100, value > 0 ? 6 : 0))
                        .opacity(dimmed ? 0.45 : 1)
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
            Circle().stroke(.white.opacity(0.18), lineWidth: 2.4)
            if let value {
                Circle()
                    .trim(from: 0, to: max(value / 100, 0.02))
                    .stroke(
                        dimmed ? Color(white: 0.55) : Palette.color(for: UsageTone(percent: value)),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// The notch silhouette: flat top flush with the screen edge, small concave shoulders where it
/// meets the bezel, and rounded bottom corners. Both radii animate.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
