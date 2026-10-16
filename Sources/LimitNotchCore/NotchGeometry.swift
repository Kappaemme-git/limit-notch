import CoreGraphics

/// Where the panel sits on a screen, derived from the values NSScreen reports.
/// Pure so it can be tested without a display: the app passes in `frame`, `visibleFrame`,
/// `safeAreaInsets.top`, the widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` and
/// `backingScaleFactor`.
///
/// Collapsed, the black body is exactly the camera housing reported by NSScreen plus a narrow ear
/// on each side, each holding one of the bot's eyes, so the notch reads as a face: 219 × 32 pt
/// around a 179 pt notch. Hover opens its "mouth" downward into a 260 × 138 pt island.
public struct NotchGeometry: Equatable, Sendable {
    /// Height of the top-center pill on displays without a notch.
    public static let fallbackPillHeight: CGFloat = 28
    /// Menu bar height assumed when it cannot be measured (for example, when it auto-hides).
    public static let defaultMenuBarHeight: CGFloat = 24
    /// Width of each ear beside the camera housing: one eye plus a hairline of black around it.
    public static let earWidth: CGFloat = 20
    /// The box every eye expression fits in, centered in its ear.
    public static let eyeBox = CGSize(width: 16, height: 22)
    /// Concave flare where the body meets the top edge, outside the body on each side.
    public static let collapsedShoulder: CGFloat = 6
    public static let expandedShoulder: CGFloat = 10
    public static let collapsedBottomRadius: CGFloat = 10
    public static let expandedBottomRadius: CGFloat = 28
    /// Height of the mouth below the notch band when expanded.
    public static let expandedContentHeight: CGFloat = 106
    /// Narrowest expanded body, without the shoulders.
    public static let minimumExpandedWidth: CGFloat = 260
    /// Minimum black margin on each side of the camera housing when expanded.
    public static let expandedSideWidth: CGFloat = 40
    /// Bridge between the ears on displays without a notch.
    public static let fallbackBridgeWidth: CGFloat = 8
    public static let screenMargin: CGFloat = 8

    public let screenFrame: CGRect
    /// The camera housing in screen coordinates, or `.zero` when the display has no notch.
    public let notchRect: CGRect
    /// Height of the black band along the top edge: the notch height, or the fallback pill height.
    public let barHeight: CGFloat
    public let scale: CGFloat

    public var notchSize: CGSize { notchRect.size }
    public var hasNotch: Bool { notchRect.width > 0 }

    public init(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        scale: CGFloat = 2
    ) {
        self.screenFrame = screenFrame
        self.scale = scale > 0 ? scale : 2
        // The notch is the gap between the two auxiliary areas.
        if safeAreaTop > 0, let left = auxiliaryTopLeftWidth, let right = auxiliaryTopRightWidth, left > 0, right > 0 {
            let width = screenFrame.width - left - right
            if width > 0, width < screenFrame.width / 2 {
                notchRect = CGRect(x: screenFrame.minX + left, y: screenFrame.maxY - safeAreaTop,
                                   width: width, height: safeAreaTop)
                barHeight = safeAreaTop
                return
            }
        }
        notchRect = .zero
        var menuBar = screenFrame.maxY - visibleFrame.maxY
        if menuBar <= 0 || menuBar > 60 { menuBar = Self.defaultMenuBarHeight }
        barHeight = max(menuBar, Self.fallbackPillHeight)
    }

    /// Horizontal center of the notch (or of the screen without one), in screen coordinates.
    public var centerX: CGFloat {
        hasNotch ? notchRect.midX : screenFrame.midX
    }

    /// Width of the camera housing, or a short bridge on plain displays.
    public var bodyWidth: CGFloat {
        hasNotch ? notchRect.width : Self.fallbackBridgeWidth
    }

    /// The collapsed black body: camera housing plus both ears, without the shoulders.
    public var collapsedBodyWidth: CGFloat {
        bodyWidth + 2 * Self.earWidth
    }

    public var expandedBodyWidth: CGFloat {
        max(Self.minimumExpandedWidth, bodyWidth + 2 * Self.expandedSideWidth)
    }

    /// Panel sizes, including the shoulders.
    public var collapsedSize: CGSize {
        CGSize(width: collapsedBodyWidth + 2 * Self.collapsedShoulder, height: barHeight)
    }

    public var expandedSize: CGSize {
        CGSize(width: expandedBodyWidth + 2 * Self.expandedShoulder,
               height: barHeight + Self.expandedContentHeight)
    }

    /// Centers of the left and right eyes, relative to the collapsed panel's left edge and top.
    public var leftEarCenter: CGPoint {
        CGPoint(x: Self.collapsedShoulder + Self.earWidth / 2, y: barHeight / 2)
    }

    public var rightEarCenter: CGPoint {
        CGPoint(x: collapsedSize.width - Self.collapsedShoulder - Self.earWidth / 2, y: barHeight / 2)
    }

    /// Panel frame in screen coordinates: centered on the notch, flush with the top edge and
    /// aligned to the pixel grid so edges stay crisp on Retina displays.
    public func panelFrame(expanded: Bool) -> CGRect {
        let size = expanded ? expandedSize : collapsedSize
        let width = min(size.width, screenFrame.width - 2 * Self.screenMargin)
        var x = min(max(centerX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        x = Self.pixelAligned(x, scale: scale)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: width, height: size.height)
    }

    /// The outline for a given expansion progress (0 collapsed, 1 expanded).
    public func outline(progress: CGFloat) -> NotchOutline {
        let t = min(max(progress, 0), 1)
        return NotchOutline(
            topRadius: Self.collapsedShoulder + (Self.expandedShoulder - Self.collapsedShoulder) * t,
            bottomRadius: Self.collapsedBottomRadius + (Self.expandedBottomRadius - Self.collapsedBottomRadius) * t
        )
    }

    static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}

/// The notch silhouette: flat top flush with the screen edge, small concave shoulders where it
/// meets the bezel, and continuous ("squircle") bottom corners. Both radii animate.
public struct NotchOutline: Equatable, Sendable {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    /// Continuous corners start this many radii before the corner, like Apple's rounded rects.
    public static let smoothing: CGFloat = 1.28

    public init(topRadius: CGFloat, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// Path in a top-left-origin coordinate space (SwiftUI's), filling `rect`.
    public func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bodyWidth = rect.width - 2 * top
        let reach = max(0, min(bottomRadius * Self.smoothing, rect.height - top, bodyWidth / 2))
        // Control points of a cubic that leaves each edge tangentially and eases into the curve.
        let handle = reach * 0.42
        let left = rect.minX + top
        let right = rect.maxX - top

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(to: CGPoint(x: left, y: rect.minY + top),
                      control1: CGPoint(x: rect.minX + top * 0.55, y: rect.minY),
                      control2: CGPoint(x: left, y: rect.minY + top * 0.45))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - reach))
        path.addCurve(to: CGPoint(x: left + reach, y: rect.maxY),
                      control1: CGPoint(x: left, y: rect.maxY - handle),
                      control2: CGPoint(x: left + handle, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - reach, y: rect.maxY))
        path.addCurve(to: CGPoint(x: right, y: rect.maxY - reach),
                      control1: CGPoint(x: right - handle, y: rect.maxY),
                      control2: CGPoint(x: right, y: rect.maxY - handle))
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: right, y: rect.minY + top * 0.45),
                      control2: CGPoint(x: rect.maxX - top * 0.55, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
