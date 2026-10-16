import AppKit
import LimitNotchCore
import QuartzCore
import SwiftUI

/// A small AppKit surface. Only this view redraws at the display refresh rate. The mascot's size
/// follows the view's frame (see `MascotDrawingView.canvasScale`), so SwiftUI can animate it.
struct MascotView: NSViewRepresentable {
    let state: CreatureState
    let isAnimating: Bool
    /// Changing this plays the short squash used when the mood or the selected service changes.
    var popTrigger: String = ""

    func makeNSView(context: Context) -> MascotDrawingView {
        let view = MascotDrawingView()
        view.state = state
        view.popTrigger = popTrigger
        view.isAnimating = isAnimating
        return view
    }

    func updateNSView(_ view: MascotDrawingView, context: Context) {
        view.changeState(to: state)
        if view.popTrigger != popTrigger {
            view.popTrigger = popTrigger
            view.pop()
        }
        view.isAnimating = isAnimating
        view.updateDisplayLink()
    }

    static func dismantleNSView(_ view: MascotDrawingView, coordinator: ()) {
        view.isAnimating = false
        view.updateDisplayLink()
    }
}

/// Body color and opacity for each mood. The whole body changes color, not just an outline.
private struct MoodPaint {
    let top: (CGFloat, CGFloat, CGFloat)
    let bottom: (CGFloat, CGFloat, CGFloat)
    let alpha: CGFloat

    static func `for`(_ state: CreatureState) -> MoodPaint {
        switch state {
        case .happy: return MoodPaint(top: rgb(0x3B82F6), bottom: rgb(0x2563EB), alpha: 1)
        case .worried: return MoodPaint(top: rgb(0xFBBF24), bottom: rgb(0xF59E0B), alpha: 1)
        case .panic: return MoodPaint(top: rgb(0xEF4444), bottom: rgb(0xDC2626), alpha: 1)
        case .sleeping: return MoodPaint(top: rgb(0x9CA3AF), bottom: rgb(0x6B7280), alpha: 0.85)
        }
    }

    static func mix(_ a: MoodPaint, _ b: MoodPaint, _ t: CGFloat) -> MoodPaint {
        func m(_ x: (CGFloat, CGFloat, CGFloat), _ y: (CGFloat, CGFloat, CGFloat)) -> (CGFloat, CGFloat, CGFloat) {
            (x.0 + (y.0 - x.0) * t, x.1 + (y.1 - x.1) * t, x.2 + (y.2 - x.2) * t)
        }
        return MoodPaint(top: m(a.top, b.top), bottom: m(a.bottom, b.bottom), alpha: a.alpha + (b.alpha - a.alpha) * t)
    }

    private static func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }
}

final class MascotDrawingView: NSView {
    private static let epoch = Date()
    /// Body color and pose blend between moods.
    private static let transitionDuration = 0.6
    /// The old face fades out while the new one fades in.
    private static let faceFadeDuration = 0.3
    /// Squash to 1.12 × 0.86 and spring back.
    private static let popDuration = 0.36
    private static let glowRed = NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
    private static let sweat = NSColor(srgbRed: 0xDB / 255, green: 0xEA / 255, blue: 0xFE / 255, alpha: 1)
    private static let pupil = NSColor(srgbRed: 0x7F / 255, green: 0x1D / 255, blue: 0x1D / 255, alpha: 1)
    private static let zzz = NSColor(srgbRed: 0xA5 / 255, green: 0xB4 / 255, blue: 0xFC / 255, alpha: 1)

    var state: CreatureState = .happy
    var isAnimating = true
    var popTrigger = ""
    private let seed = UInt64.random(in: .min ... .max)
    private var previousState: CreatureState?
    private var changeTime = -Double.infinity
    private var popTime = -Double.infinity
    private var link: NSObject?
    private var fallbackTimer: Timer?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The view is `canvasScale` body diameters wide, leaving room for the glow and the Zzz.
    static let canvasScale: CGFloat = 2.5
    private var diameter: CGFloat { min(bounds.width, bounds.height) / Self.canvasScale }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    func changeState(to newState: CreatureState) {
        guard newState != state else { return }
        previousState = state
        changeTime = now
        state = newState
        pop()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        needsDisplay = true
    }

    func pop() {
        popTime = now
        needsDisplay = true
    }

    private var now: TimeInterval { Date().timeIntervalSince(Self.epoch) }

    func updateDisplayLink() {
        guard window != nil && isAnimating else {
            if #available(macOS 14, *), let displayLink = link as? CADisplayLink {
                displayLink.invalidate()
            }
            link = nil
            fallbackTimer?.invalidate()
            fallbackTimer = nil
            return
        }
        if #available(macOS 14, *) {
            if link == nil {
                link = displayLink(target: self, selector: #selector(displayFrame(_:)))
                (link as? CADisplayLink)?.add(to: .main, forMode: .common)
            }
            (link as? CADisplayLink)?.preferredFrameRateRange = CAFrameRateRange(
                minimum: state == .sleeping ? 15 : 60,
                maximum: state == .sleeping ? 30 : 120,
                preferred: state == .sleeping ? 30 : 120)
        } else if fallbackTimer == nil {
            fallbackTimer = Timer.scheduledTimer(timeInterval: state == .sleeping ? 1 / 30 : 1 / 60,
                                                 target: self, selector: #selector(timerFrame(_:)),
                                                 userInfo: nil, repeats: true)
        }
    }

    @objc private func displayFrame(_ sender: AnyObject) {
        needsDisplay = true
    }

    @objc private func timerFrame(_ sender: Timer) {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, diameter > 1 else { return }
        let time = now
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let motionTime = reduceMotion ? 0 : time
        var pose = MascotMotion.pose(at: motionTime, state: state, seed: seed)
        var paint = MoodPaint.for(state)
        var faces: [(CreatureState, CGFloat)] = [(state, 1)]

        if let previousState {
            let progress = smoothstep((time - changeTime) / Self.transitionDuration)
            if progress < 1 {
                let old = MascotMotion.pose(at: motionTime, state: previousState, seed: seed)
                pose = MascotPose.blend(old, pose, progress)
                paint = MoodPaint.mix(MoodPaint.for(previousState), paint, progress)
                let fade = smoothstep((time - changeTime) / Self.faceFadeDuration)
                faces = [(previousState, 1 - fade), (state, fade)]
            } else {
                self.previousState = nil
            }
        }
        if reduceMotion, pose.zzzOpacity > 0 { pose.zzzPhase = 0.3 }

        let popElapsed = time - popTime
        if !reduceMotion, popElapsed >= 0, popElapsed < Self.popDuration {
            let squash = sin(.pi * popElapsed / Self.popDuration)
            pose.scaleX *= 1 + 0.12 * squash
            pose.scaleY *= 1 - 0.14 * squash
        }
        draw(pose, paint: paint, faces: faces, in: context)
    }

    private func smoothstep(_ x: Double) -> CGFloat {
        let t = min(max(x, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }

    // MARK: - Drawing

    private func draw(_ pose: MascotPose, paint: MoodPaint, faces: [(CreatureState, CGFloat)], in context: CGContext) {
        let d = diameter
        let radius = d / 2
        let center = CGPoint(x: bounds.midX + pose.offsetX * d, y: bounds.midY + pose.offsetY * d)

        context.saveGState()
        context.setAlpha(paint.alpha)

        if pose.glow > 0.01 {
            let colors = [Self.glowRed.withAlphaComponent(0.9 * pose.glow).cgColor,
                          Self.glowRed.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: [0.55, 1]) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: radius * 1.75, options: [])
            }
        }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: pose.rotation)
        // Squash and stretch around the bottom of the body.
        context.translateBy(x: 0, y: radius)
        context.scaleBy(x: pose.scaleX, y: pose.scaleY)
        context.translateBy(x: 0, y: -radius)

        let body = CGRect(x: -radius, y: -radius, width: d, height: d)
        context.saveGState()
        context.addEllipse(in: body)
        context.clip()
        let colors = [CGColor(srgbRed: paint.top.0, green: paint.top.1, blue: paint.top.2, alpha: 1),
                      CGColor(srgbRed: paint.bottom.0, green: paint.bottom.1, blue: paint.bottom.2, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: -radius), end: CGPoint(x: 0, y: radius), options: [])
        }
        context.restoreGState()

        // Faces are drawn in the design's 100 × 100 viewBox.
        context.translateBy(x: -radius, y: -radius)
        context.scaleBy(x: d / 100, y: d / 100)
        for (face, alpha) in faces where alpha > 0.01 {
            context.saveGState()
            drawFace(face, pose: pose, diameter: d, alpha: paint.alpha * alpha, in: context)
            context.restoreGState()
        }
        context.restoreGState()
        context.restoreGState()

        if pose.zzzOpacity > 0.01 {
            drawZzz(pose, bodyOrigin: CGPoint(x: center.x - radius, y: center.y - radius), diameter: d)
        }
    }

    /// Stroke widths in viewBox units: heavier at ear size so the face stays legible.
    private func stroke(small: CGFloat, large: CGFloat, diameter: CGFloat) -> CGFloat {
        let t = min(max((diameter - 18) / (44 - 18), 0), 1)
        return small + (large - small) * t
    }

    private func drawFace(_ face: CreatureState, pose: MascotPose, diameter d: CGFloat, alpha: CGFloat,
                          in context: CGContext) {
        context.setAlpha(alpha)
        let open = CGFloat(min(max(pose.eyeOpenness, 0), 1))
        let gazeX = CGFloat(pose.gazeX) * 4
        let gazeY = CGFloat(pose.gazeY) * 3
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineCap(.round)

        switch face {
        case .happy:
            // Smiling ^ ^ eyes; a blink flattens the arcs.
            // The design's arcs are 16 units wide, so their round caps touch and read as one "m";
            // narrowing them keeps a gap between the eyes at every stroke weight.
            let width = stroke(small: 9, large: 7, diameter: d)
            let half = (20 - width - 1) / 2
            context.setLineWidth(width)
            for cx: CGFloat in [37, 57] {
                let x = cx + gazeX
                let base = 52 + gazeY
                context.move(to: CGPoint(x: x - half, y: base))
                context.addQuadCurve(to: CGPoint(x: x + half, y: base), control: CGPoint(x: x, y: base - 16 * open))
            }
            context.strokePath()

        case .worried:
            // Smaller, raised vertical ovals under slanted brows, and a sweat drop.
            let scale = CGFloat(pose.eyeScale)
            let cy = 46 + CGFloat(pose.eyeLift) * 100 + gazeY
            let rx = 6 * scale
            let ry = max(10 * scale * open, 1.5)
            for cx: CGFloat in [39, 56] {
                context.fillEllipse(in: CGRect(x: cx + gazeX - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
            }
            context.setLineWidth(stroke(small: 7, large: 5, diameter: d))
            let browX = gazeX / 2
            context.move(to: CGPoint(x: 31 + browX, y: 29))
            context.addLine(to: CGPoint(x: 44 + browX, y: 24))
            context.move(to: CGPoint(x: 51 + browX, y: 24))
            context.addLine(to: CGPoint(x: 64 + browX, y: 29))
            context.strokePath()
            if pose.dropOpacity > 0.01 {
                context.saveGState()
                context.setAlpha(alpha * CGFloat(pose.dropOpacity))
                context.translateBy(x: 0, y: CGFloat(pose.dropOffset) * 100)
                context.setFillColor(Self.sweat.cgColor)
                let drop = CGMutablePath()
                drop.move(to: CGPoint(x: 79, y: 22))
                drop.addCurve(to: CGPoint(x: 85, y: 36), control1: CGPoint(x: 83, y: 29), control2: CGPoint(x: 85, y: 32))
                drop.addArc(center: CGPoint(x: 79, y: 36), radius: 6, startAngle: 0, endAngle: .pi, clockwise: false)
                drop.addCurve(to: CGPoint(x: 79, y: 22), control1: CGPoint(x: 73, y: 32), control2: CGPoint(x: 75, y: 29))
                context.addPath(drop)
                context.fillPath()
                context.restoreGState()
            }

        case .panic:
            // Big round eyes with small pupils that dart around.
            let r = 12 * CGFloat(pose.eyeScale)
            let ry = max(r * open, 1.5)
            for cx: CGFloat in [35, 60] {
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: cx - r, y: 46 - ry, width: 2 * r, height: 2 * ry))
                guard open > 0.3 else { continue }
                let pr: CGFloat = 4.5
                let pupilY = 46 + gazeY * open
                context.setFillColor(Self.pupil.cgColor)
                context.fillEllipse(in: CGRect(x: cx + gazeX - pr, y: pupilY - pr * open, width: 2 * pr, height: 2 * pr * open))
            }

        case .sleeping:
            // Closed eyes, curving down.
            let width = stroke(small: 8, large: 6, diameter: d)
            let half = (20 - width - 1) / 2
            context.setLineWidth(width)
            for cx: CGFloat in [37, 57] {
                context.move(to: CGPoint(x: cx - half, y: 48))
                context.addQuadCurve(to: CGPoint(x: cx + half, y: 48), control: CGPoint(x: cx, y: 55))
            }
            context.strokePath()
        }
    }

    /// "Z z" drifting up and to the right of the body, staggered like the design's lcZ.
    private func drawZzz(_ pose: MascotPose, bodyOrigin: CGPoint, diameter d: CGFloat) {
        let letters: [(String, CGFloat, Double, CGPoint)] = [
            ("Z", 0.3, 0, CGPoint(x: 0.86, y: -0.24)),
            ("z", 0.22, MascotMotion.zzzStagger, CGPoint(x: 1.06, y: -0.24 - 0.8 * 0.22))
        ]
        for (letter, size, delay, anchor) in letters {
            var phase = pose.zzzPhase - delay
            if phase < 0 { phase += 1 }
            let p = CGFloat(phase)
            let opacity = (p < 0.25 ? p / 0.25 : 1 - (p - 0.25) / 0.75) * CGFloat(pose.zzzOpacity)
            guard opacity > 0.01 else { continue }
            let eased = 1 - (1 - p) * (1 - p)
            let em = size * d
            let fontSize = em * (0.6 + 0.55 * eased)
            var font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
            if let rounded = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: rounded, size: fontSize) ?? font
            }
            let point = CGPoint(x: bodyOrigin.x + anchor.x * d + 0.3 * em * eased,
                                y: bodyOrigin.y + anchor.y * d - 0.6 * em * eased)
            (letter as NSString).draw(at: point, withAttributes: [
                .font: font,
                .foregroundColor: Self.zzz.withAlphaComponent(opacity),
            ])
        }
    }
}
