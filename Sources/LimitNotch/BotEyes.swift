import LimitNotchCore
import SwiftUI

/// The bot's two eyes, one in each ear, so the notch reads as a face. Drawn like EVE's: each eye
/// is one solid, glowing rounded shape with a single crisp highlight, and every expression is a
/// change of silhouette (size, roundness, a lid cut, a tilt, a squash) rather than added detail.
/// `EyeRig` supplies the pose; the timeline only ticks while something moves.
struct BotEyes: View {
    @ObservedObject var rig: EyeRig
    let glance: UsageGlance
    /// Eye centers within the drawing surface.
    let left: CGPoint
    let right: CGPoint

    /// Each eye's canvas: its ear plus room for the glow, as tall as the band.
    private static let canvasWidth = NotchGeometry.earWidth + 10

    var body: some View {
        TimelineView(.animation(paused: !rig.isRunning)) { _ in
            let frame = rig.frame(at: CACurrentMediaTime())
            let height = left.y * 2
            ZStack(alignment: .topLeading) {
                canvas(frame, mirrored: false, height: height).position(left)
                canvas(frame, mirrored: true, height: height).position(right)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: glance.mood) { rig.setMood(glance.mood) }
        .task(id: glance.windows) { rig.observe(glance.windows) }
    }

    private func canvas(_ frame: EyeFrame, mirrored: Bool, height: CGFloat) -> some View {
        Canvas { context, size in
            EyePainter(frame: frame, mirrored: mirrored).draw(in: &context, size: size)
        }
        .frame(width: Self.canvasWidth, height: height)
    }
}

/// Draws one eye. The left eye's outer corner is on the left; `mirrored` flips lids, tilt and brow
/// for the right eye, while the highlight stays on the same side so both eyes share one light.
private struct EyePainter {
    let frame: EyeFrame
    let mirrored: Bool

    /// +1 when the camera is to the right of this eye (the left eye), -1 otherwise.
    private var inward: CGFloat { mirrored ? -1 : 1 }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let f = frame
        let flash = clamp(f.flash, upper: 1.2)
        let eyeScale = max(0, 1 - flash * 1.6)
        if eyeScale > 0 {
            var eye = context
            let pivot = CGPoint(x: size.width / 2, y: size.height / 2)
            eye.opacity = Double(min(1, eyeScale * 1.4))
            eye.translateBy(x: pivot.x, y: pivot.y)
            eye.scaleBy(x: eyeScale, y: eyeScale)
            eye.translateBy(x: -pivot.x, y: -pivot.y)
            drawEye(in: &eye, size: size)
        }
        if flash > 0.3 {
            drawCelebration(in: &context, center: CGPoint(x: size.width / 2, y: size.height / 2 + 0.5),
                            progress: (flash - 0.3) / 0.7)
        }
    }

    // MARK: - Eye

    private func drawEye(in context: inout GraphicsContext, size: CGSize) {
        let f = frame
        let e = f.expression
        let gaze = mirrored ? f.rightGaze : f.leftGaze
        let closure = clamp(f.closure)
        let widen = clamp(f.widen, upper: 1.5)

        // Squash and stretch: a blink presses the eye into a flat, wider line, and the squash
        // spring's overshoot stretches it a little taller as it pops back open.
        let press = closure + 0.4 * (CGFloat(f.squash) - closure)
        var width = e.width * (1 + 0.04 * widen) * (1 + 0.16 * press)
        var height = e.height * (1 + 0.08 * widen) * (1 - 0.9 * press)
        // Turning toward the pointer foreshortens the eye a touch.
        width *= 1 - 0.08 * abs(gaze.dx)
        height *= 1 - 0.05 * abs(gaze.dy)
        height = max(height, 1.8)
        width = max(width, 1)

        // The eye itself moves to look; it closes toward a line a little below its middle.
        let center = CGPoint(x: size.width / 2 + gaze.dx * 1.1 + f.tremble.width,
                             y: size.height / 2 + e.drop + gaze.dy * 2.8 + (e.height - height) * 0.18
                                 + f.tremble.height)

        // Lids relax when the eye widens, follow a downward look, and give way to the blink.
        let open = (1 - min(widen, 1)) * (1 - closure)
        let follow = 0.12 * max(0, gaze.dy)
        let lids = (outer: clamp(e.outerLid * open + follow * (1 - closure)),
                    inner: clamp(e.innerLid * open + follow * (1 - closure)))
        let shape = EyeShape(halfWidth: width / 2, halfHeight: height / 2, roundness: e.roundness,
                             outerLid: lids.outer, innerLid: lids.inner, inward: inward)
        let outline = shape.path(center: center, rotation: -e.tilt * inward)
        let color = f.color

        // The eye lights the black around it.
        let glow = clamp(e.glow + 0.25 * widen)
        if glow > 0.01 {
            var halo = context
            halo.addFilter(.blur(radius: 2.6))
            halo.fill(outline, with: .color(color.color(opacity: 0.75 * glow)))
        }

        // One solid shape, a shade lighter at the top, like a lit, slightly domed screen.
        let top = center.y - height / 2
        let bottom = center.y + height / 2
        context.fill(outline, with: .linearGradient(
            Gradient(colors: [color.mixed(with: .white, by: 0.2).color(), color.color(),
                              color.mixed(with: .black, by: 0.1).color()]),
            startPoint: CGPoint(x: center.x, y: top), endPoint: CGPoint(x: center.x, y: bottom)))

        // A single crisp highlight high on the light side. It lags the gaze, so the eye reads as
        // glass turning under a fixed light; it slides down under a lowered lid instead of being
        // cut, and fades out of a heavy-lidded, sleepy eye.
        let x = -width * 0.2 - gaze.dx * 0.5
        let edge = shape.topEdge(at: x)
        let uncovered = (height / 2 - edge) / height
        let visible = clamp((height - 4) / (e.height * 0.4)) * smoothstep(0.55, 0.75, uncovered)
        if visible > 0 {
            let spot = CGSize(width: max(2.2, width * 0.34),
                              height: max(2.4, height * 0.3 * min(1, 0.3 + uncovered)))
            let below: CGFloat = max(spot.height / 2 + 1, (height / 2 - edge) * 0.3)
            let spotCenter = CGPoint(x: center.x + x, y: center.y + edge + below - gaze.dy * 0.4)
            var gloss = context
            gloss.clip(to: outline)
            gloss.opacity = Double(visible)
            gloss.translateBy(x: spotCenter.x, y: spotCenter.y)
            gloss.rotate(by: .radians(-0.35))
            gloss.fill(Path(ellipseIn: CGRect(x: -spot.width / 2, y: -spot.height / 2,
                                              width: spot.width, height: spot.height)),
                       with: .color(.white.opacity(0.96)))
        }

        drawBrow(in: &context, center: center, height: height, gaze: gaze, widen: widen)
    }

    /// A short capsule above the eye, its inner end raised: worry, or with more lift, alarm.
    private func drawBrow(in context: inout GraphicsContext, center: CGPoint, height: CGFloat, gaze: CGVector,
                          widen: CGFloat) {
        let f = frame
        let e = f.expression
        let presence = clamp(e.brow)
        guard presence > 0.01 else { return }
        let span = e.width * 0.4 * (0.7 + 0.3 * presence)
        let midX = center.x + inward * 0.6
        let base = center.y - e.height / 2 - e.browLift - 1.2 * widen - 1 + (e.height - height) * 0.1
        let tilt = e.browTilt * presence
        var brow = Path()
        brow.move(to: CGPoint(x: midX - inward * span, y: base + tilt / 2))
        brow.addQuadCurve(to: CGPoint(x: midX + inward * span, y: base - tilt / 2),
                          control: CGPoint(x: midX, y: base - 0.6))
        context.stroke(brow, with: .color(f.color.color(opacity: presence)),
                       style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
    }

    // MARK: - Reset celebration

    private func drawCelebration(in context: inout GraphicsContext, center: CGPoint, progress: CGFloat) {
        let grow = max(0, progress)
        var shape = context
        shape.opacity = Double(min(1, grow * 2))
        shape.translateBy(x: center.x, y: center.y)
        switch frame.celebration {
        case .heart:
            shape.scaleBy(x: grow, y: grow)
            let pink = RGB(hex: 0xFF375F)
            let heart = Self.heart(size: CGSize(width: 12, height: 11))
            var halo = shape
            halo.addFilter(.blur(radius: 2.6))
            halo.fill(heart, with: .color(pink.color(opacity: 0.6)))
            shape.fill(heart, with: .linearGradient(Gradient(colors: [
                pink.mixed(with: .white, by: 0.2).color(), pink.color(), pink.mixed(with: .black, by: 0.1).color()
            ]), startPoint: CGPoint(x: 0, y: -5.5), endPoint: CGPoint(x: 0, y: 5.5)))
            shape.fill(Path(ellipseIn: CGRect(x: -4.2, y: -3.6, width: 2.6, height: 2)), with: .color(.white.opacity(0.96)))
        case .star:
            shape.rotate(by: .radians(Double(1 - min(grow, 1)) * 0.9))
            shape.scaleBy(x: grow, y: grow)
            let gold = RGB(hex: 0xFFD60A)
            let star = Self.sparkle(radius: 7, waist: 1.6)
            var halo = shape
            halo.addFilter(.blur(radius: 2.6))
            halo.fill(star, with: .color(gold.color(opacity: 0.6)))
            shape.fill(star, with: .linearGradient(Gradient(colors: [
                gold.mixed(with: .white, by: 0.35).color(), gold.color()
            ]), startPoint: CGPoint(x: 0, y: -7), endPoint: CGPoint(x: 0, y: 7)))
        }
    }

    private static func heart(size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: (x - 0.5) * w, y: (y - 0.5) * h) }
        var path = Path()
        path.move(to: p(0.5, 0.96))
        path.addCurve(to: p(0, 0.34), control1: p(0.24, 0.76), control2: p(0, 0.58))
        path.addCurve(to: p(0.5, 0.2), control1: p(0, 0.02), control2: p(0.4, -0.04))
        path.addCurve(to: p(1, 0.34), control1: p(0.6, -0.04), control2: p(1, 0.02))
        path.addCurve(to: p(0.5, 0.96), control1: p(1, 0.58), control2: p(0.76, 0.76))
        path.closeSubpath()
        return path
    }

    /// A four-pointed sparkle with concave sides.
    private static func sparkle(radius: CGFloat, waist: CGFloat) -> Path {
        var path = Path()
        let tips = [CGPoint(x: 0, y: -radius), CGPoint(x: radius, y: 0), CGPoint(x: 0, y: radius), CGPoint(x: -radius, y: 0)]
        path.move(to: tips[0])
        for index in 0..<4 {
            let next = tips[(index + 1) % 4]
            let mid = CGPoint(x: (tips[index].x + next.x) / 2, y: (tips[index].y + next.y) / 2)
            let length = max((mid.x * mid.x + mid.y * mid.y).squareRoot(), 0.001)
            path.addQuadCurve(to: next, control: CGPoint(x: mid.x / length * waist, y: mid.y / length * waist))
        }
        path.closeSubpath()
        return path
    }
}

/// An eye's silhouette in its own coordinates (origin at the center, y down): a superellipse
/// whose top can be cut by a straight lid that runs from the outer corner to the inner one. The
/// cut blends into the outline with a soft maximum, so the lid's corners are rounded, never sharp.
private struct EyeShape {
    let halfWidth: CGFloat
    let halfHeight: CGFloat
    let roundness: CGFloat
    let outerLid: CGFloat
    let innerLid: CGFloat
    let inward: CGFloat

    private static let samples = 72

    private var exponent: CGFloat { max(roundness, 1.2) }
    private var lidPresence: CGFloat { clamp(max(outerLid, innerLid) * 8) }

    /// Height of the lid's edge at `x`; above the eye when the lids are up.
    private func lid(at x: CGFloat) -> CGFloat {
        let u = clamp((x / halfWidth * inward + 1) / 2)
        let fraction = outerLid + (innerLid - outerLid) * u
        let arch = 0.4 * (1 - (x / halfWidth) * (x / halfWidth))
        return -halfHeight + 2 * halfHeight * fraction - arch * lidPresence
    }

    private func outlineHalf(at x: CGFloat) -> CGFloat {
        let t = clamp(abs(x) / halfWidth)
        return halfHeight * pow(max(0, 1 - pow(t, exponent)), 1 / exponent)
    }

    /// Upper edge of the visible eye at `x`.
    func topEdge(at x: CGFloat) -> CGFloat {
        let half = outlineHalf(at: x)
        return min(softMax(-half, lid(at: x)), half)
    }

    private func softMax(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let k = 1.6 * lidPresence
        return (a + b + ((a - b) * (a - b) + k * k).squareRoot()) / 2
    }

    func path(center: CGPoint, rotation: CGFloat) -> Path {
        let n = exponent
        var points: [CGPoint] = []
        points.reserveCapacity(Self.samples)
        for index in 0..<Self.samples {
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(Self.samples)
            let c = cos(angle)
            let s = sin(angle)
            let x = halfWidth * copysign(pow(abs(c), 2 / n), c)
            var y = halfHeight * copysign(pow(abs(s), 2 / n), s)
            if lidPresence > 0 {
                y = min(softMax(y, lid(at: x)), outlineHalf(at: x))
            }
            let rotated = CGPoint(x: x * cos(rotation) - y * sin(rotation), y: x * sin(rotation) + y * cos(rotation))
            points.append(CGPoint(x: center.x + rotated.x, y: center.y + rotated.y))
        }
        return Self.smoothClosed(points)
    }

    /// A closed Catmull-Rom spline through `points`, as cubic Béziers.
    private static func smoothClosed(_ points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}

/// A color the rig can interpolate.
struct RGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = RGB(red: 1, green: 1, blue: 1)
    static let black = RGB(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    func mixed(with other: RGB, by t: CGFloat) -> RGB {
        let t = Double(t)
        return RGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                   blue: blue + (other.blue - blue) * t)
    }

    func color(opacity: CGFloat = 1) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: Double(opacity))
    }
}

private func clamp(_ value: CGFloat, upper: CGFloat = 1) -> CGFloat {
    min(max(value, 0), upper)
}

private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}
