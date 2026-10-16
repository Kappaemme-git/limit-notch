import LimitNotchCore
import SwiftUI

/// The mascot reduced to a status light: a disc in the mood color with its two vertical eyes
/// slightly left of center. It blinks now and then; asleep, the eyes close into short lines.
/// Nothing animates between blinks, so it costs no frames at rest.
struct MoodGlyph: View {
    let mood: CreatureState
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            let asleep = mood == .sleeping
            let eye = asleep ? CGSize(width: 0.17 * d, height: 0.08 * d) : CGSize(width: 0.15 * d, height: 0.3 * d)
            ZStack {
                Circle()
                    .fill(Palette.mood(mood))
                    .shadow(color: Palette.mood(mood).opacity(glowOpacity), radius: mood == .panic ? 4 : 2.5)
                // Closed eyes sit further apart so they never merge into one bar.
                let eyeX: [CGFloat] = asleep ? [0.32, 0.64] : [0.38, 0.6]
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: eye.width, height: eye.height)
                        .scaleEffect(x: 1, y: blinking && !asleep ? 0.12 : 1)
                        .position(x: eyeX[index] * d, y: (asleep ? 0.54 : 0.46) * d)
                }
            }
            .frame(width: d, height: d)
        }
        .animation(.easeInOut(duration: 0.4), value: mood)
        .task(id: isAnimating && !reduceMotion && mood != .sleeping) { await blinkLoop() }
    }

    private var glowOpacity: Double {
        switch mood {
        case .happy, .worried: return 0.45
        case .panic: return 0.85
        case .sleeping: return 0
        }
    }

    private func blinkLoop() async {
        guard isAnimating, !reduceMotion, mood != .sleeping else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3...7)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.07)) { blinking = true }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.12)) { blinking = false }
        }
    }
}
