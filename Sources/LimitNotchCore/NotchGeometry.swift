import CoreGraphics

/// Where the panel sits on a screen, derived from the values NSScreen reports.
/// Pure so it can be tested without a display: the app passes in `frame`, `visibleFrame`,
/// `safeAreaInsets.top` and the widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
public struct NotchGeometry: Equatable, Sendable {
    /// Width of the black "ear" added on each side of the notch while collapsed.
    public static let earWidth: CGFloat = 38
    /// Height of the top-center pill on displays without a notch.
    public static let fallbackPillHeight: CGFloat = 28
    /// Menu bar height assumed when it cannot be measured (for example, when it auto-hides).
    public static let defaultMenuBarHeight: CGFloat = 24
    /// Height of the usage area below the notch band when expanded.
    public static let expandedContentHeight: CGFloat = 118
    public static let minimumExpandedWidth: CGFloat = 420
    public static let screenMargin: CGFloat = 8

    public let screenFrame: CGRect
    /// Size of the camera housing, or `.zero` when the display has no notch.
    public let notchSize: CGSize
    /// Height of the black band along the top edge: the notch height, or the fallback pill height.
    public let barHeight: CGFloat

    public var hasNotch: Bool { notchSize.width > 0 }

    public init(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) {
        self.screenFrame = screenFrame
        // The notch is the gap between the two auxiliary areas, centered on the screen.
        if safeAreaTop > 0, let left = auxiliaryTopLeftWidth, let right = auxiliaryTopRightWidth {
            let width = screenFrame.width - left - right
            if width > 0, width < screenFrame.width / 2 {
                notchSize = CGSize(width: width, height: safeAreaTop)
                barHeight = safeAreaTop
                return
            }
        }
        notchSize = .zero
        var menuBar = screenFrame.maxY - visibleFrame.maxY
        if menuBar <= 0 || menuBar > 60 { menuBar = Self.defaultMenuBarHeight }
        barHeight = max(menuBar, Self.fallbackPillHeight)
    }

    /// Collapsed mascot size: 18–24 pt, fitted to the band height.
    public var mascotDiameter: CGFloat {
        min(max(barHeight - 10, 18), 24)
    }

    public var collapsedSize: CGSize {
        CGSize(width: notchSize.width + 2 * Self.earWidth, height: barHeight)
    }

    public var expandedSize: CGSize {
        let width = max(Self.minimumExpandedWidth, collapsedSize.width + 60)
        return CGSize(width: width, height: barHeight + Self.expandedContentHeight)
    }

    /// Panel frame in screen coordinates: centered on the notch and flush with the top edge.
    public func panelFrame(expanded: Bool) -> CGRect {
        let size = expanded ? expandedSize : collapsedSize
        let width = min(size.width, screenFrame.width - 2 * Self.screenMargin)
        let x = min(max(screenFrame.midX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: width, height: size.height)
    }
}
