import AppKit
import LimitNotchCore
import QuartzCore
import SwiftUI

/// A fixed-size AppKit surface. Only this tiny view redraws at the display refresh rate.
struct MascotView: NSViewRepresentable {
    let state: CreatureState
    let diameter: CGFloat
    let isAnimating: Bool

    func makeNSView(context: Context) -> MascotDrawingView {
        let view = MascotDrawingView()
        view.state = state
        view.diameter = diameter
        view.isAnimating = isAnimating
        return view
    }

    func updateNSView(_ view: MascotDrawingView, context: Context) {
        view.changeState(to: state)
        view.diameter = diameter
        view.isAnimating = isAnimating
        view.updateDisplayLink()
    }

    static func dismantleNSView(_ view: MascotDrawingView, coordinator: ()) {
        view.isAnimating = false
        view.updateDisplayLink()
    }
}

final class MascotDrawingView: NSView {
    private static let epoch = Date()
    private static let transitionDuration = 0.6
    private static let blue = NSColor(srgbRed: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255, alpha: 1)
    private static let red = NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1)

    var state: CreatureState = .happy
    var diameter: CGFloat = 40
    var isAnimating = true
    private let seed = UInt64.random(in: .min ... .max)
    private var previousState: CreatureState?
    private var changeTime = -Double.infinity
    private var link: NSObject?
    private var fallbackTimer: Timer?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    func changeState(to newState: CreatureState) {
        guard newState != state else { return }
        previousState = state
        changeTime = Date().timeIntervalSince(Self.epoch)
        state = newState
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        needsDisplay = true
    }

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
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let time = Date().timeIntervalSince(Self.epoch)
        let current = MascotMotion.pose(at: time, state: state, seed: seed)
        let progress = (time - changeTime) / Self.transitionDuration
        let pose: MascotPose
        if let previousState, progress < 1 {
            let old = MascotMotion.pose(at: time, state: previousState, seed: seed)
            let t = min(max(progress, 0), 1)
            pose = MascotPose.blend(old, current, t * t * (3 - 2 * t))
        } else {
            pose = current
        }
        draw(pose, in: context)
    }

    private func draw(_ pose: MascotPose, in context: CGContext) {
        let d = diameter
        let radius = d / 2
        let center = CGPoint(x: bounds.midX + pose.offsetX * d,
                             y: bounds.midY + pose.offsetY * d)

        if pose.glow > 0.01 {
            let colors = [Self.red.withAlphaComponent(0.55 * pose.glow).cgColor,
                          Self.red.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: [0.55, 1]) {
                context.saveGState()
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: radius * 1.6,
                                           options: [])
                context.restoreGState()
            }
        }

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: pose.rotation)
        context.translateBy(x: 0, y: radius)
        context.scaleBy(x: pose.scaleX, y: pose.scaleY)
        context.translateBy(x: 0, y: -radius)
        context.setFillColor(Self.blue.cgColor)
        context.fillEllipse(in: CGRect(x: -radius, y: -radius, width: d, height: d))

        // Two small white vertical ovals, slightly left of center; never a mouth.
        let open = min(max(pose.eyeOpenness, 0), 1)
        let eyeWidth = d * 0.10 * pose.eyeScale * (1 + 0.5 * (1 - open))
        let eyeHeight = max(d * 0.22 * pose.eyeScale * open, d * 0.05)
        let eyeX = pose.gazeX * d * 0.09
        let eyeY = (-0.02 + pose.eyeLift) * d + pose.gazeY * d * 0.07
        context.setFillColor(NSColor.white.cgColor)
        for x: CGFloat in [-0.15, 0.03] {
            context.fillEllipse(in: CGRect(x: x * d + eyeX - eyeWidth / 2,
                                           y: eyeY - eyeHeight / 2,
                                           width: eyeWidth, height: eyeHeight))
        }
        context.restoreGState()

        if pose.zzzOpacity > 0.01 {
            for index in 0..<2 {
                let phase = (pose.zzzPhase + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                let alpha = pose.zzzOpacity * sin(.pi * phase) * 0.9
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: d * (0.28 + 0.16 * phase), weight: .heavy),
                    .foregroundColor: NSColor.white.withAlphaComponent(alpha),
                ]
                ("z" as NSString).draw(at: CGPoint(x: center.x + radius * (0.6 + 0.6 * phase),
                                                     y: center.y - radius * (0.5 + 0.75 * phase)),
                                       withAttributes: attributes)
            }
        }
    }

}
