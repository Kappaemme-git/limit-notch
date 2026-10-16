import LimitNotchCore
import SwiftUI

/// The round blue mascot. Layout takes `diameter` × `diameter`; the canvas overflows that box so
/// hops, the panic glow and the floating Zzz are not clipped.
struct MascotView: View {
    let state: CreatureState
    let diameter: CGFloat
    var isAnimating = true

    /// Seconds since launch keep the trigonometry precise; the reference-date epoch is ~8e8 s.
    private static let epoch = Date()
    private static let transitionDuration = 0.6

    @State private var seed = UInt64.random(in: .min ... .max)
    @State private var previousState: CreatureState?
    @State private var changeTime: TimeInterval = -.infinity

    var body: some View {
        TimelineView(.animation(minimumInterval: state == .sleeping ? 1.0 / 30 : 1.0 / 60, paused: !isAnimating)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSince(Self.epoch)
                MascotRenderer.draw(pose(at: time), in: &context, size: size, diameter: diameter)
            }
        }
        .frame(width: diameter * 2, height: diameter * 2)
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: state) { [state] _ in
            previousState = state
            changeTime = Date().timeIntervalSince(Self.epoch)
        }
    }

    /// Cross-fades the motion of the old mood into the new one so mood changes never jump.
    private func pose(at time: TimeInterval) -> MascotPose {
        let current = MascotMotion.pose(at: time, state: state, seed: seed)
        let progress = (time - changeTime) / Self.transitionDuration
        guard let previousState, progress < 1 else { return current }
        let old = MascotMotion.pose(at: time, state: previousState, seed: seed)
        let eased = progress * progress * (3 - 2 * progress)
        return MascotPose.blend(old, current, eased)
    }
}

enum MascotRenderer {
    static let lightBlue = Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
    static let deepBlue = Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
    static let alarmRed = Color(red: 0.94, green: 0.27, blue: 0.27)

    /// Eye geometry as fractions of the diameter: small vertical ovals, slightly left of center.
    static let eyeCenters: [CGFloat] = [-0.15, 0.03]
    static let eyeY: CGFloat = -0.02
    static let eyeWidth: CGFloat = 0.10
    static let eyeHeight: CGFloat = 0.22

    static func draw(_ pose: MascotPose, in context: inout GraphicsContext, size: CGSize, diameter d: CGFloat) {
        let r = d / 2
        let center = CGPoint(x: size.width / 2 + pose.offsetX * d, y: size.height / 2 + pose.offsetY * d)

        if pose.glow > 0.01 {
            let reach = r * 1.6
            let halo = Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2))
            context.fill(halo, with: .radialGradient(
                Gradient(stops: [
                    .init(color: alarmRed.opacity(0.7 * pose.glow), location: 0.55),
                    .init(color: alarmRed.opacity(0), location: 1)
                ]),
                center: center, startRadius: 0, endRadius: reach
            ))
        }

        // Tilt around the center, squash and stretch around the bottom, where the body "lands".
        var body = context
        body.translateBy(x: center.x, y: center.y)
        body.rotate(by: .radians(pose.rotation))
        body.translateBy(x: 0, y: r)
        body.scaleBy(x: pose.scaleX, y: pose.scaleY)
        body.translateBy(x: 0, y: -r)

        let circle = Path(ellipseIn: CGRect(x: -r, y: -r, width: d, height: d))
        body.fill(circle, with: .linearGradient(
            Gradient(colors: [lightBlue, deepBlue]),
            startPoint: CGPoint(x: -r * 0.6, y: -r),
            endPoint: CGPoint(x: r * 0.6, y: r)
        ))
        if pose.glow > 0.01 {
            body.fill(circle, with: .color(alarmRed.opacity(0.2 * pose.glow)))
        }

        // Blinks squash the ovals into a line; fully closed eyes (sleep) are short dashes.
        let open = min(max(pose.eyeOpenness, 0), 1)
        let eyeW = d * eyeWidth * pose.eyeScale * (1 + 0.5 * (1 - open))
        let eyeH = max(d * eyeHeight * pose.eyeScale * open, d * 0.05)
        let eyeX = pose.gazeX * d * 0.09
        let eyeYOffset = (eyeY + pose.eyeLift) * d + pose.gazeY * d * 0.07
        for x in eyeCenters {
            let rect = CGRect(x: x * d + eyeX - eyeW / 2, y: eyeYOffset - eyeH / 2, width: eyeW, height: eyeH)
            body.fill(Path(ellipseIn: rect), with: .color(.white))
        }

        if pose.zzzOpacity > 0.01 {
            for index in 0..<2 {
                let phase = (pose.zzzPhase + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                let fontSize = d * (0.28 + 0.16 * phase)
                let letter = context.resolve(
                    Text("z").font(.system(size: fontSize, weight: .heavy, design: .rounded)).foregroundColor(.white)
                )
                var layer = context
                layer.opacity = pose.zzzOpacity * sin(.pi * phase) * 0.9
                layer.draw(letter, at: CGPoint(x: center.x + r * (0.6 + 0.6 * phase), y: center.y - r * (0.5 + 0.75 * phase)))
            }
        }
    }
}
