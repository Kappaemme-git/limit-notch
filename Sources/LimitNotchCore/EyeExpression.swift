import CoreGraphics

/// The shape of one of the bot's eyes for a mood. Every value interpolates linearly, so the app can
/// spring from one expression to the next without the eye ever jumping.
///
/// An eye is an oval in the mood color. A straight upper lid can hide part of it (more at the
/// outer corner reads as worried). Fully `closed`, the oval is replaced by a short curved line.
public struct EyeExpression: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    /// Fraction of the height hidden by the upper lid at the corner away from the camera.
    public var outerLid: CGFloat
    /// Fraction of the height hidden by the upper lid at the corner next to the camera.
    public var innerLid: CGFloat
    /// 0 open, 1 shut.
    public var closed: CGFloat
    /// Opacity of the soft halo around the eye.
    public var glow: CGFloat

    public init(width: CGFloat, height: CGFloat, outerLid: CGFloat = 0, innerLid: CGFloat = 0,
                closed: CGFloat = 0, glow: CGFloat = 0) {
        self.width = width
        self.height = height
        self.outerLid = outerLid
        self.innerLid = innerLid
        self.closed = closed
        self.glow = glow
    }

    /// Happy: a soft, nearly round eye. Worried: the outer lid droops. Panic: tall and wide open.
    /// Sleeping: closed into a line.
    public static func `for`(_ mood: CreatureState) -> EyeExpression {
        switch mood {
        case .happy:
            return EyeExpression(width: 14, height: 17, glow: 0.35)
        case .worried:
            return EyeExpression(width: 13, height: 18, outerLid: 0.4, innerLid: 0.04, glow: 0.3)
        case .panic:
            return EyeExpression(width: 15, height: 21, glow: 0.7)
        case .sleeping:
            return EyeExpression(width: 14, height: 3, closed: 1)
        }
    }
}
