import AppKit
import LimitNotchCore
import SwiftUI

enum NotchLayout {
    static let compact: CGFloat = 32
    static let expandedWidth: CGFloat = 354
    static let expandedHeight: CGFloat = 460
}

struct IndicatorView: View {
    @ObservedObject var store: StatusStore

    private var status: UsageStatus? { store.snapshot.status }
    private var creatureState: CreatureState { store.snapshot.creatureState }

    private var statusText: String {
        switch store.snapshot {
        case .current:
            return creatureState.title
        case .stale:
            return "Stale data"
        case .unavailable:
            return "Data unavailable"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.isExpanded {
                expandedCard
            } else {
                NotchCreature(state: creatureState)
                    .id(creatureState)
                    .frame(width: NotchLayout.compact, height: NotchLayout.compact)
            }
        }
        .frame(
            width: store.isExpanded ? NotchLayout.expandedWidth : NotchLayout.compact,
            height: store.isExpanded ? NotchLayout.expandedHeight : NotchLayout.compact
        )
        .contentShape(Rectangle())
        .onHover { store.setHovered($0) }
        .onTapGesture { store.toggleExpanded() }
        .contextMenu {
            Button("Quit LimitNotch") { NSApp.terminate(nil) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("LimitNotch: \(statusText)")
        .accessibilityHint("Hover or click to view usage and reset times")
    }

    private var expandedCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NotchCreature(state: creatureState)
                        .id(creatureState)
                        .frame(width: 30, height: 30)
                    Text("LimitNotch")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(creatureState.color)
                }

                divider

                section("USAGE") {
                    metric("Claude · 5h", value: status?.claude5h)
                    metric("Claude · 7d", value: status?.claude7d)
                    metric("Codex · 7d", value: status?.codex7d)
                }

                divider

                section("CLAUDE APP") {
                    metric("5h", value: status?.claudeApp?.fh)
                    metric("7d", value: status?.claudeApp?.sd)
                    infoRow("Captured", value: dateText(status?.claudeApp?.at))
                }

                divider

                section("RESETS") {
                    infoRow("Claude · 5h", value: dateText(status?.claude5hResetsAt))
                    infoRow("Claude · 7d", value: dateText(status?.claude7dResetsAt))
                    infoRow("Codex · 7d", value: dateText(status?.codex7dResetsAt))
                }

                divider

                section("DATA") {
                    infoRow("Claude data", value: dateText(status?.claudeDataAt))
                    infoRow("Codex data", value: dateText(status?.codexDataAt))
                    infoRow("Updated", value: dateText(status?.updatedAt))
                    infoRow("Mood", value: status?.mood?.rawValue ?? "—")
                    infoRow("Level", value: status?.level?.rawValue ?? "—")
                }

                divider

                section("NOTE") {
                    Text(status?.note ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(status?.note == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .frame(width: NotchLayout.expandedWidth, height: NotchLayout.expandedHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
            .strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func metric(_ label: String, value: Double?) -> some View {
        infoRow(label, value: value.map { String(format: "%.1f%%", $0) } ?? "—")
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11))
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension CreatureState {
    var color: Color {
        switch self {
        case .happy: return Color(red: 0.20, green: 0.83, blue: 0.53)
        case .worried: return Color(red: 1.00, green: 0.76, blue: 0.24)
        case .panic: return Color(red: 0.96, green: 0.31, blue: 0.32)
        case .sleeping: return Color(red: 0.57, green: 0.61, blue: 0.66)
        }
    }

    var title: String {
        switch self {
        case .happy: return "Happy"
        case .worried: return "Worried"
        case .panic: return "Panicking"
        case .sleeping: return "Asleep"
        }
    }
}

private struct NotchCreature: View {
    let state: CreatureState
    @State private var moving = false

    private var motion: Animation {
        switch state {
        case .happy: return .easeInOut(duration: 0.38).repeatForever(autoreverses: true)
        case .worried: return .easeInOut(duration: 0.13).repeatForever(autoreverses: true)
        case .panic: return .easeInOut(duration: 0.09).repeatForever(autoreverses: true)
        case .sleeping: return .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        }
    }

    private var horizontalOffset: CGFloat {
        switch state {
        case .worried: return moving ? 0.8 : -0.8
        case .panic: return moving ? 1.3 : -1.3
        default: return 0
        }
    }

    private var verticalOffset: CGFloat {
        switch state {
        case .happy: return moving ? -3 : 1
        case .worried: return moving ? -0.5 : 0.5
        case .panic: return moving ? -2 : 0
        case .sleeping: return moving ? 0.4 : 1.3
        }
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.22))
                .frame(width: 17, height: 3)
                .offset(y: 12)

            ZStack {
                Capsule().fill(state.color)
                    .frame(width: 4, height: 7)
                    .rotationEffect(.degrees(-20))
                    .offset(x: -5, y: -11)
                Circle().fill(state.color)
                    .frame(width: 4, height: 4)
                    .offset(x: -6, y: -14)

                Capsule().fill(state.color)
                    .frame(width: 8, height: 3)
                    .rotationEffect(.degrees(-25))
                    .offset(x: -11, y: 2)
                Capsule().fill(state.color)
                    .frame(width: 8, height: 3)
                    .rotationEffect(.degrees(25))
                    .offset(x: 11, y: 2)

                Capsule().fill(state.color.opacity(0.85))
                    .frame(width: 7, height: 4)
                    .offset(x: -6, y: 10)
                Capsule().fill(state.color.opacity(0.85))
                    .frame(width: 7, height: 4)
                    .offset(x: 6, y: 10)

                Ellipse()
                    .fill(LinearGradient(
                        colors: [state.color.opacity(0.9), state.color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 21, height: 20)
                    .overlay(Ellipse().strokeBorder(.black.opacity(0.35), lineWidth: 1))

                face
            }
            .frame(width: 30, height: 30)
            .offset(x: horizontalOffset, y: verticalOffset)
            .rotationEffect(.degrees(state == .panic && moving ? 5 : 0))

            if state == .sleeping {
                Text("z")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(state.color)
                    .offset(x: 11, y: -10)
                    .opacity(moving ? 0.9 : 0.3)
            }
        }
        .frame(width: 30, height: 30)
        .animation(motion, value: moving)
        .onAppear { moving = true }
    }

    @ViewBuilder
    private var face: some View {
        switch state {
        case .happy:
            eye(x: -4, y: -2)
            eye(x: 4, y: -2)
            Path { path in
                path.move(to: CGPoint(x: 11, y: 17))
                path.addQuadCurve(to: CGPoint(x: 19, y: 17), control: CGPoint(x: 15, y: 23))
            }
            .stroke(.black.opacity(0.72), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .frame(width: 30, height: 30)

        case .worried:
            eye(x: -4, y: -2)
            eye(x: 4, y: -2)
            Path { path in
                path.move(to: CGPoint(x: 9, y: 10))
                path.addLine(to: CGPoint(x: 13, y: 11))
                path.move(to: CGPoint(x: 17, y: 11))
                path.addLine(to: CGPoint(x: 21, y: 10))
            }
            .stroke(.black.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(width: 30, height: 30)
            Ellipse().fill(.black.opacity(0.72))
                .frame(width: 3, height: 4)
                .offset(y: 4)

        case .panic:
            panicEye(x: -4)
            panicEye(x: 4)
            Ellipse().fill(.black.opacity(0.8))
                .frame(width: 5, height: 7)
                .offset(y: 4)

        case .sleeping:
            Capsule().fill(.black.opacity(0.6))
                .frame(width: 4, height: 1.2)
                .offset(x: -4, y: -1)
            Capsule().fill(.black.opacity(0.6))
                .frame(width: 4, height: 1.2)
                .offset(x: 4, y: -1)
            Capsule().fill(.black.opacity(0.55))
                .frame(width: 3, height: 1.1)
                .offset(y: 4)
        }
    }

    private func eye(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(.black.opacity(0.76))
            .frame(width: 2.5, height: 2.5)
            .offset(x: x, y: y)
    }

    private func panicEye(x: CGFloat) -> some View {
        Ellipse().fill(.white)
            .frame(width: 5, height: 6)
            .overlay(Circle().fill(.black.opacity(0.85)).frame(width: 1.7, height: 1.7))
            .offset(x: x, y: -2)
    }
}
