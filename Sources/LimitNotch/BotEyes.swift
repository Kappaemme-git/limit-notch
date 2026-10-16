import LimitNotchCore
import SwiftUI

/// The bot's two eyes, one in each ear, so the notch reads as a face. Each mood has its own shape
/// and color and a small habit: happy blinks slowly, worried glances around, panic trembles, and
/// asleep the eyes close into lines. Between those moments nothing redraws, except the trembling.
struct BotEyes: View {
    let mood: CreatureState
    /// Eye centers within the drawing surface.
    let left: CGPoint
    let right: CGPoint
    let isAnimating: Bool
    /// While the mouth is open, the eyes look down at the number.
    let isLookingDown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 1 open, near 0 mid-blink.
    @State private var openness: CGFloat = 1
    /// -1 looking left, 1 looking right.
    @State private var glance: CGFloat = 0

    private var isLive: Bool { isAnimating && !reduceMotion }
    private var isTrembling: Bool { isLive && mood == .panic }

    var body: some View {
        let expression = EyeExpression.for(mood)
        let color = Palette.mood(mood)
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isTrembling)) { context in
            ZStack(alignment: .topLeading) {
                eye(expression, color, mirrored: false).position(left)
                eye(expression, color, mirrored: true).position(right)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(isTrembling ? Self.tremble(at: context.date) : .zero)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: mood)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isLookingDown)
        .task(id: Habit(mood: mood, isLive: isLive)) { await habit() }
    }

    private func eye(_ expression: EyeExpression, _ color: Color, mirrored: Bool) -> some View {
        BotEye(expression: expression, color: color, mirrored: mirrored, openness: openness,
               gaze: CGSize(width: glance * 2.2, height: isLookingDown ? 1.5 : 0))
            .frame(width: NotchGeometry.eyeBox.width, height: NotchGeometry.eyeBox.height)
    }

    /// A fast, irregular shiver well under a point, so the eyes stay crisp.
    private static func tremble(at date: Date) -> CGSize {
        let t = date.timeIntervalSinceReferenceDate
        return CGSize(width: 0.5 * sin(t * 53) + 0.25 * sin(t * 97), height: 0.35 * sin(t * 71))
    }

    // MARK: - Habits

    private struct Habit: Equatable {
        let mood: CreatureState
        let isLive: Bool
    }

    private func habit() async {
        withAnimation(.easeOut(duration: 0.2)) {
            openness = 1
            glance = 0
        }
        guard isLive else { return }
        while !Task.isCancelled {
            switch mood {
            case .happy:
                await pause(3.5...7)
                await blink(close: 0.11, hold: 0.05, open: 0.22)
                if Double.random(in: 0...1) < 0.25 {
                    await pause(0.12...0.18)
                    await blink(close: 0.09, hold: 0.04, open: 0.18)
                }
            case .worried:
                await pause(1.4...2.6)
                let side: CGFloat = Bool.random() ? 1 : -1
                look(side)
                await pause(0.5...1)
                if Bool.random() {
                    look(-side)
                    await pause(0.4...0.8)
                }
                look(0)
                if Bool.random() {
                    await pause(0.3...0.6)
                    await blink(close: 0.07, hold: 0.04, open: 0.12)
                }
            case .panic:
                await pause(2.5...5)
                await blink(close: 0.05, hold: 0.03, open: 0.08)
            case .sleeping:
                return
            }
        }
    }

    private func look(_ side: CGFloat) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) { glance = side }
    }

    private func blink(close: Double, hold: Double, open: Double) async {
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: close)) { openness = 0.08 }
        try? await Task.sleep(for: .seconds(close + hold))
        withAnimation(.easeOut(duration: open)) { openness = 1 }
        try? await Task.sleep(for: .seconds(open))
    }

    private func pause(_ range: ClosedRange<Double>) async {
        try? await Task.sleep(for: .seconds(Double.random(in: range)))
    }
}

/// One eye: an oval in the mood color with a small catchlight toward the camera, trimmed by the
/// upper lid. Closing, the oval flattens while a curved line fades in.
private struct BotEye: View {
    let expression: EyeExpression
    let color: Color
    /// The right eye; its inner corner is on the left.
    let mirrored: Bool
    let openness: CGFloat
    let gaze: CGSize

    var body: some View {
        let e = expression
        let catchlight = e.width * 0.3
        ZStack {
            ZStack {
                Ellipse().fill(color)
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: catchlight, height: catchlight)
                    .offset(x: (mirrored ? -0.17 : 0.17) * e.width, y: -0.18 * e.height)
            }
            .frame(width: e.width, height: e.height)
            .mask(UpperLid(outer: e.outerLid, inner: e.innerLid, mirrored: mirrored))
            .scaleEffect(x: 1, y: openness)
            .opacity(1 - e.closed)

            ClosedEye()
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: e.width - 2, height: 4)
                .opacity(e.closed)
        }
        .shadow(color: color.opacity(e.glow), radius: 3)
        .offset(gaze)
    }
}

/// The part of an eye below the upper lid, a straight edge that can tilt. It overhangs the eye so
/// the oval's sides and bottom are never trimmed.
private struct UpperLid: Shape {
    var outer: CGFloat
    var inner: CGFloat
    let mirrored: Bool

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(outer, inner) }
        set {
            outer = newValue.first
            inner = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let overhang: CGFloat = 4
        let leftLid = mirrored ? inner : outer
        let rightLid = mirrored ? outer : inner
        let slope = (rightLid - leftLid) * rect.height / max(rect.width, 1)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - overhang, y: rect.minY + leftLid * rect.height - slope * overhang))
        path.addLine(to: CGPoint(x: rect.maxX + overhang, y: rect.minY + rightLid * rect.height + slope * overhang))
        path.addLine(to: CGPoint(x: rect.maxX + overhang, y: rect.maxY + overhang))
        path.addLine(to: CGPoint(x: rect.minX - overhang, y: rect.maxY + overhang))
        path.closeSubpath()
        return path
    }
}

/// A closed eye: a shallow downward curve.
private struct ClosedEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 1))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 1),
                          control: CGPoint(x: rect.midX, y: rect.maxY + 1.5))
        return path
    }
}
