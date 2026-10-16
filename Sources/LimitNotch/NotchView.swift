import AppKit
import LimitNotchCore
import SwiftUI

/// The fixed-size drawing surface prevents layout work during the silhouette spring. The panel
/// window clips it to the hardware camera housing while collapsed.
struct NotchView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var notch: NotchState

    private enum Metrics {
        static let inset: CGFloat = 20
        static let mascot: CGFloat = 44
        static let mascotGap: CGFloat = 14
        static let ring: CGFloat = 40
        /// The row holding the mascot, the hero text and the ring, just below the notch band.
        static let heroRow: CGFloat = 44
        static let topPadding: CGFloat = 8
    }

    private var geometry: NotchGeometry { notch.geometry }
    private var expanded: Bool { notch.isExpanded }
    private var glance: UsageGlance { UsageGlance(store.snapshot) }

    private var mascotCenter: CGPoint {
        CGPoint(x: Metrics.inset + Metrics.mascot / 2,
                y: geometry.barHeight + Metrics.topPadding + Metrics.heroRow / 2)
    }

    var body: some View {
        drawingSurface
        .contextMenu {
            Button("Refresh Now") { store.refresh() }
            Divider()
            Button("Quit LimitNotch") { NSApp.terminate(nil) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Hover to view usage and reset times")
    }

    private var drawingSurface: some View {
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

            if expanded {
                MascotView(state: store.snapshot.creatureState, diameter: Metrics.mascot,
                           isAnimating: notch.isAnimating)
                    .frame(width: Metrics.mascot * 2, height: Metrics.mascot * 2)
                    .position(mascotCenter)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.1)))
            }
        }
        .frame(width: geometry.expandedSize.width, height: geometry.expandedSize.height)
        .contentShape(NotchBody(geometry: geometry, progress: expanded ? 1 : 0))
    }

    // MARK: - Expanded glance

    /// Mascot on the left, one hero line with a plain-English status in the middle, a single ring
    /// on the right, and the other windows in a quiet row underneath.
    private var expandedContent: some View {
        let glance = self.glance
        let full = geometry.expandedSize
        return TimelineView(.periodic(from: .now, by: 15)) { timeline in
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        heroLine(glance)
                        Text(glance.message(now: timeline.date))
                            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    UsageRing(value: glance.hero?.percent, color: levelColor(glance))
                        .frame(width: Metrics.ring, height: Metrics.ring)
                }
                .frame(height: Metrics.heroRow)

                if !glance.others.isEmpty {
                    secondaryRow(glance.others)
                }
            }
            .lineLimit(1)
            .padding(.top, geometry.barHeight + Metrics.topPadding)
            .padding(.leading, Metrics.inset + Metrics.mascot + Metrics.mascotGap)
            .padding(.trailing, Metrics.inset)
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
    }

    private func heroLine(_ glance: UsageGlance) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(glance.hero?.title ?? "No data")
            if let hero = glance.hero {
                Text(UsageFormatting.percent(hero.percent))
                    .monospacedDigit()
                    .numericTransition(hero.percent)
            }
        }
        .font(.system(size: 20, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(glance.isCurrent ? 0.95 : 0.6))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: glance.hero)
    }

    private func secondaryRow(_ windows: [UsageWindow]) -> some View {
        HStack(spacing: 14) {
            ForEach(windows, id: \.title) { window in
                HStack(spacing: 4) {
                    Text(window.title)
                    Text(UsageFormatting.percent(window.percent))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.36))
    }

    /// Color is reserved for the level of the hero window; old data is grey.
    private func levelColor(_ glance: UsageGlance) -> Color {
        guard glance.isCurrent, let hero = glance.hero else { return Color(white: 0.5) }
        return Palette.color(for: hero.tone)
    }

    private var accessibilitySummary: String {
        let glance = self.glance
        let line = { (window: UsageWindow) in "\(window.title) \(UsageFormatting.percent(window.percent))" }
        let parts = [glance.hero.map(line) ?? "No data", glance.message(now: Date())] + glance.others.map(line)
        return "LimitNotch: " + parts.joined(separator: ". ")
    }
}

/// Apple's dark-mode system colors, so the ring reads like native UI.
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
        let t = min(max(progress, 0), 1)
        let collapsed = geometry.collapsedSize
        let expanded = geometry.expandedSize
        let width = collapsed.width + (expanded.width - collapsed.width) * t
        let height = collapsed.height + (expanded.height - collapsed.height) * t
        let bodyRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        return Path(geometry.outline(progress: t).path(in: bodyRect))
    }
}

/// A single progress ring for the hero window. It sweeps in from empty each time the notch opens.
private struct UsageRing: View {
    let value: Double?
    let color: Color
    @State private var appeared = false

    private static let lineWidth: CGFloat = 5

    var body: some View {
        let fraction = appeared ? min(max(value ?? 0, 0), 100) / 100 : 0
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(Self.lineWidth / 2)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: fraction)
        .animation(.easeInOut(duration: 0.3), value: color)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(0.1)) { appeared = true }
        }
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
