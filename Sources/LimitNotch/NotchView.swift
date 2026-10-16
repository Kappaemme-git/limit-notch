import AppKit
import LimitNotchCore
import SwiftUI

/// The notch is the bot's face: collapsed, the black shape is the camera housing with an eye in
/// each ear. Hovering opens the mouth, which shows the number, its reset time and the service
/// switch. The fixed-size drawing surface prevents layout work during the silhouette spring; the
/// panel window clips it to the collapsed face or to the open mouth.
struct NotchView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var notch: NotchState
    @AppStorage("serviceSelection") private var selection: ServiceSelection = .auto
    @Namespace private var pill

    /// Heights inside the mouth, from the bottom of the notch band down.
    private enum Metrics {
        static let numberTop: CGFloat = 4
        static let numberHeight: CGFloat = 42
        static let subtitleHeight: CGFloat = 14
        static let switchGap: CGFloat = 10
    }

    private var geometry: NotchGeometry { notch.geometry }
    private var expanded: Bool { notch.isExpanded }
    private var surface: CGSize { geometry.expandedSize }
    private var bar: CGFloat { geometry.barHeight }
    /// Left edge of the collapsed panel within the drawing surface.
    private var collapsedOrigin: CGFloat { (surface.width - geometry.collapsedSize.width) / 2 }

    var body: some View {
        let glance = UsageGlance(store.snapshot, selection: selection)
        ZStack(alignment: .topLeading) {
            NotchBody(geometry: geometry, progress: expanded ? 1 : 0)
                .fill(Color.black)

            if expanded {
                mouth(glance)
                    .transition(.asymmetric(
                        insertion: .modifier(active: Reveal(hidden: true), identity: Reveal(hidden: false))
                            .animation(.spring(response: 0.34, dampingFraction: 0.86).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
            }

            BotEyes(mood: glance.mood,
                    left: offsetByOrigin(geometry.leftEarCenter),
                    right: offsetByOrigin(geometry.rightEarCenter),
                    isAnimating: notch.isAnimating,
                    isLookingDown: expanded)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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

    private func offsetByOrigin(_ point: CGPoint) -> CGPoint {
        CGPoint(x: collapsedOrigin + point.x, y: point.y)
    }

    // MARK: - Mouth

    /// The number, its window and reset time, and the service switch, centered under the eyes.
    private func mouth(_ glance: UsageGlance) -> some View {
        VStack(spacing: 0) {
            PercentText(value: glance.hero?.percent, size: 38, unitSize: 20)
                .foregroundStyle(numberColor(glance))
                .frame(height: Metrics.numberHeight)
            TimelineView(.periodic(from: .now, by: 15)) { timeline in
                Text(subtitle(glance, now: timeline.date))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .frame(height: Metrics.subtitleHeight)
            }
            serviceSwitch
                .padding(.top, Metrics.switchGap)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: glance.hero)
        .frame(width: surface.width)
        .offset(y: bar + Metrics.numberTop)
    }

    private var serviceSwitch: some View {
        HStack(spacing: 0) {
            ForEach(ServiceSelection.allCases, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Palette.primaryText : Palette.switchText)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
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
        .background(Palette.switchTrack, in: Capsule(style: .continuous))
    }

    /// "Claude · Resets in 1h 52m"; just the status when there is no number to label.
    private func subtitle(_ glance: UsageGlance, now: Date) -> String {
        let message = glance.message(now: now)
        return glance.hero.map { "\($0.title) · \(message)" } ?? message
    }

    /// White while there is room, yellow from 60%, red from 85%, grey when the data is old.
    private func numberColor(_ glance: UsageGlance) -> Color {
        guard glance.isCurrent, let hero = glance.hero else { return Palette.stale }
        return Palette.color(for: hero.tone)
    }

    private func accessibilitySummary(_ glance: UsageGlance) -> String {
        let line = { (window: UsageWindow) in "\(window.title) \(UsageFormatting.percent(window.percent))" }
        let parts = [glance.hero.map(line) ?? "No data", glance.message(now: Date())] + glance.others.map(line)
        return "LimitNotch: " + parts.joined(separator: ". ")
    }
}

/// "70%" with a smaller, dimmer percent sign; "—" without a value.
private struct PercentText: View {
    let value: Double?
    let size: CGFloat
    let unitSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size / 36) {
            Text(value.map { String(UsageFormatting.percent($0).dropLast()) } ?? "—")
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .kerning(size > 20 ? -0.5 : 0)
                .numericTransition(value)
            if value != nil {
                Text("%")
                    .font(.system(size: unitSize, weight: .semibold, design: .rounded))
                    .opacity(0.6)
            }
        }
        .lineLimit(1)
    }
}

/// Apple's dark-mode system colors and grays.
enum Palette {
    static let eyeBlue = Color(hex: 0x409CFF)
    static let yellow = Color(hex: 0xFFD60A)
    static let red = Color(hex: 0xFF453A)
    static let stale = Color(hex: 0x8E8E93)
    static let primaryText = Color(hex: 0xF5F5F7)
    static let secondaryText = Color(hex: 0x98989D)
    static let switchTrack = Color(hex: 0x1C1C1E)
    static let switchThumb = Color(hex: 0x3A3A3C)
    static let switchText = Color(hex: 0x8E8E93)

    /// Color of a number: plain white while there is room, so color always means "look".
    static func color(for tone: UsageTone) -> Color {
        switch tone {
        case .normal: return primaryText
        case .high: return yellow
        case .critical: return red
        }
    }

    /// Color of the eyes; the blue is the brighter high-contrast variant so it reads on black.
    static func mood(_ mood: CreatureState) -> Color {
        switch mood {
        case .happy: return eyeBlue
        case .worried: return yellow
        case .panic: return red
        case .sleeping: return stale
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// How the mouth's content arrives: it fades in, drops 4 pt, grows from 97% and sharpens.
private struct Reveal: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? -4 : 0)
            .scaleEffect(hidden ? 0.97 : 1, anchor: .top)
            .blur(radius: hidden ? 3 : 0)
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
