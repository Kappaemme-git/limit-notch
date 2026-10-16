import AppKit
import LimitNotchCore
import SwiftUI

/// The fixed-size drawing surface prevents layout work during the silhouette spring. The panel
/// window clips it to the collapsed notch and ears, or to the expanded island.
struct NotchView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var notch: NotchState
    @AppStorage("serviceSelection") private var selection: ServiceSelection = .auto
    @Namespace private var pill

    /// Offsets inside the expanded body, from design/Main.dc.html; vertical ones are measured
    /// from the bottom of the notch band.
    private enum Metrics {
        static let pillTop: CGFloat = 6
        static let mascot: CGFloat = 44
        static let mascotLeading: CGFloat = 20
        static let mascotTop: CGFloat = 36
        static let textLeading: CGFloat = 78
        static let textTop: CGFloat = 32
        static let ring: CGFloat = 44
        static let ringTrailing: CGFloat = 20
        static let ringTop: CGFloat = 34
    }

    private var geometry: NotchGeometry { notch.geometry }
    private var expanded: Bool { notch.isExpanded }
    private var surface: CGSize { geometry.expandedSize }
    private var bar: CGFloat { geometry.barHeight }
    /// Left edges of the collapsed and expanded bodies within the drawing surface.
    private var collapsedLeft: CGFloat { (surface.width - geometry.collapsedBodyWidth) / 2 }
    private var expandedLeft: CGFloat { NotchGeometry.expandedShoulder }

    var body: some View {
        let glance = UsageGlance(store.snapshot, selection: selection)
        ZStack(alignment: .topLeading) {
            NotchBody(geometry: geometry, progress: expanded ? 1 : 0)
                .fill(Color.black)
            if expanded && glance.mood == .panic {
                NotchBody(geometry: geometry, progress: 1)
                    .stroke(Palette.red.opacity(0.22), lineWidth: 2)
                    .transition(.opacity)
            }

            earPercent(glance)

            if expanded {
                expandedContent(glance)
                    .transition(.asymmetric(
                        insertion: .modifier(active: Reveal(hidden: true), identity: Reveal(hidden: false))
                            .animation(.spring(response: 0.32, dampingFraction: 0.8).delay(0.14)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
            }

            mascot(glance)
        }
        .frame(width: surface.width, height: surface.height, alignment: .topLeading)
        .contentShape(NotchBody(geometry: geometry, progress: expanded ? 1 : 0))
        .contextMenu {
            Button("Refresh Now") { store.refresh() }
            Divider()
            Button("Quit LimitNotch") { NSApp.terminate(nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(glance))
        .accessibilityHint("Hover to view usage and reset times")
    }

    // MARK: - Collapsed ears

    /// The hero percentage in the right ear, colored by level; it fades out as the island opens.
    private func earPercent(_ glance: UsageGlance) -> some View {
        let trailing = (surface.width + geometry.collapsedBodyWidth) / 2 - NotchGeometry.earTextInset
        let width = NotchGeometry.earWidth - NotchGeometry.earTextInset
        return Text(glance.hero.map { UsageFormatting.percent($0.percent) } ?? "—")
            .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(levelColor(glance))
            .numericTransition(glance.hero?.percent)
            .lineLimit(1)
            .fixedSize()
            .frame(width: width, height: bar, alignment: .trailing)
            .offset(x: trailing - width)
            .opacity(expanded ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: expanded)
            .animation(.easeInOut(duration: 0.4), value: glance.hero)
            .allowsHitTesting(false)
    }

    /// One mascot that springs between the left ear and the island, changing size on the way.
    private func mascot(_ glance: UsageGlance) -> some View {
        let diameter = expanded ? Metrics.mascot : NotchGeometry.earMascotDiameter
        let center = expanded
            ? CGPoint(x: expandedLeft + Metrics.mascotLeading + Metrics.mascot / 2,
                      y: bar + Metrics.mascotTop + Metrics.mascot / 2)
            : CGPoint(x: collapsedLeft + NotchGeometry.earMascotInset + NotchGeometry.earMascotDiameter / 2,
                      y: bar / 2)
        return MascotView(state: glance.mood, isAnimating: notch.isAnimating, popTrigger: selection.rawValue)
            .frame(width: diameter * MascotDrawingView.canvasScale, height: diameter * MascotDrawingView.canvasScale)
            .position(center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Expanded island

    /// The service switch on top, the hero line with its status and the quiet row on the left,
    /// and one ring on the right.
    private func expandedContent(_ glance: UsageGlance) -> some View {
        let ringLeft = surface.width - expandedLeft - Metrics.ringTrailing - Metrics.ring
        let textLeft = expandedLeft + Metrics.textLeading
        return ZStack(alignment: .topLeading) {
            serviceSwitch
                .frame(width: surface.width)
                .offset(y: bar + Metrics.pillTop)

            TimelineView(.periodic(from: .now, by: 15)) { timeline in
                heroText(glance, now: timeline.date)
            }
            .frame(width: ringLeft - 8 - textLeft, alignment: .leading)
            .offset(x: textLeft, y: bar + Metrics.textTop)

            UsageRing(value: glance.hero?.percent, color: ringColor(glance),
                      textColor: glance.isCurrent ? Palette.primaryText : Palette.stale)
                .frame(width: Metrics.ring, height: Metrics.ring)
                .offset(x: ringLeft, y: bar + Metrics.ringTop)
        }
        .frame(width: surface.width, height: surface.height, alignment: .topLeading)
    }

    private var serviceSwitch: some View {
        HStack(spacing: 2) {
            ForEach(ServiceSelection.allCases, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Palette.switchText)
                        .padding(.horizontal, 11)
                        .frame(height: 20)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Palette.switchThumb)
                                    .matchedGeometryEffect(id: "thumb", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(option.label)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.switchTrack, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func heroText(_ glance: UsageGlance, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(glance.hero?.title ?? glance.selection.service?.name ?? "No data")
                    .foregroundStyle(glance.isCurrent ? Palette.primaryText : Palette.secondaryText)
                if glance.hero != nil || glance.selection != .auto {
                    Text(UsageFormatting.percent(glance.hero?.percent))
                        .monospacedDigit()
                        .foregroundStyle(levelColor(glance))
                        .numericTransition(glance.hero?.percent)
                }
            }
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .kerning(-0.2)
            .frame(height: 24)

            Text(glance.message(now: now))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .frame(height: 16)

            if !glance.others.isEmpty {
                Text(glance.others.map { "\($0.title) \(UsageFormatting.percent($0.percent))" }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.stale)
                    .frame(height: 14)
                    .padding(.top, 4)
            }
        }
        .lineLimit(1)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: glance.hero)
    }

    /// Color is reserved for the level of the hero window; old data is grey.
    private func levelColor(_ glance: UsageGlance) -> Color {
        guard glance.isCurrent, let hero = glance.hero else { return Palette.stale }
        return Palette.color(for: hero.tone)
    }

    private func ringColor(_ glance: UsageGlance) -> Color {
        glance.isCurrent ? levelColor(glance) : Palette.ringStale
    }

    private func accessibilitySummary(_ glance: UsageGlance) -> String {
        let line = { (window: UsageWindow) in "\(window.title) \(UsageFormatting.percent(window.percent))" }
        let parts = [glance.hero.map(line) ?? "No data", glance.message(now: Date())] + glance.others.map(line)
        return "LimitNotch: " + parts.joined(separator: ". ")
    }
}

/// Apple's dark-mode system colors and grays, as used in the design.
enum Palette {
    static let green = Color(hex: 0x30D158)
    static let yellow = Color(hex: 0xFFD60A)
    static let red = Color(hex: 0xFF453A)
    static let stale = Color(hex: 0x8E8E93)
    static let ringStale = Color(hex: 0x636366)
    static let ringTrack = Color(hex: 0x2C2C2E)
    static let primaryText = Color(hex: 0xF5F5F7)
    static let secondaryText = Color(hex: 0xAEAEB2)
    static let switchTrack = Color(hex: 0x1C1C1E)
    static let switchThumb = Color(hex: 0x3A3A3C)
    static let switchText = Color(hex: 0x98989D)

    static func color(for tone: UsageTone) -> Color {
        switch tone {
        case .normal: return green
        case .high: return yellow
        case .critical: return red
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// How the island's content arrives: it fades in, drops 6 pt, grows from 96% and sharpens.
private struct Reveal: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? -6 : 0)
            .scaleEffect(hidden ? 0.96 : 1, anchor: .top)
            .blur(radius: hidden ? 4 : 0)
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

/// A single progress ring with the number inside. It sweeps in from empty each time the notch opens.
private struct UsageRing: View {
    let value: Double?
    let color: Color
    let textColor: Color
    @State private var appeared = false

    private static let lineWidth: CGFloat = 4.5
    /// The ring's radius is 18.5 pt in a 44 pt box.
    private static let inset: CGFloat = 22 - 18.5

    var body: some View {
        let fraction = appeared ? min(max(value ?? 0, 0), 100) / 100 : 0
        ZStack {
            Circle().stroke(Palette.ringTrack, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(Self.inset)
        .overlay {
            Text(value.map { String(UsageFormatting.percent($0).dropLast()) } ?? "—")
                .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(textColor)
                .numericTransition(value)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.86), value: fraction)
        .animation(.easeInOut(duration: 0.4), value: color)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(0.1)) { appeared = true }
        }
        .accessibilityElement()
        .accessibilityLabel(value.map { "\(UsageFormatting.percent($0)) used" } ?? "No data")
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
