import CoreGraphics

/// The shape of one of the bot's eyes for a mood. Every value interpolates linearly, so the app can
/// spring from one expression to the next (overshoot included) without the eye ever jumping.
///
/// Like EVE's, an eye is one glowing, solid rounded shape with a single crisp highlight and no
/// pupil: the mood is in the silhouette. Its size and roundness change, a straight upper lid can
/// cut across it (lower at the outer corner reads as worried, low on both sides as drowsy), the
/// whole eye can tilt, and a short brow can sit above it.
public struct EyeExpression: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    /// Superellipse exponent of the outline: 2 is an ellipse, higher values square it off.
    public var roundness: CGFloat
    /// Fraction of the height hidden by the upper lid at the corner away from the camera.
    public var outerLid: CGFloat
    /// Fraction of the height hidden by the upper lid at the corner next to the camera.
    public var innerLid: CGFloat
    /// Rotation in radians; positive raises the corner next to the camera.
    public var tilt: CGFloat
    /// 0 no brow, 1 a full brow.
    public var brow: CGFloat
    /// Gap between the top of the eye and the brow, in points.
    public var browLift: CGFloat
    /// How much higher the brow's inner end sits than its outer end, in points.
    public var browTilt: CGFloat
    /// How far the eye sits below the center of its ear, to leave room for a brow.
    public var drop: CGFloat
    /// Strength of the soft light the eye casts on the black around it.
    public var glow: CGFloat

    public init(width: CGFloat, height: CGFloat, roundness: CGFloat = 2.3, outerLid: CGFloat = 0,
                innerLid: CGFloat = 0, tilt: CGFloat = 0, brow: CGFloat = 0, browLift: CGFloat = 0,
                browTilt: CGFloat = 0, drop: CGFloat = 0, glow: CGFloat = 0) {
        self.width = width
        self.height = height
        self.roundness = roundness
        self.outerLid = outerLid
        self.innerLid = innerLid
        self.tilt = tilt
        self.brow = brow
        self.browLift = browLift
        self.browTilt = browTilt
        self.drop = drop
        self.glow = glow
    }

    /// Happy: a tall, soft capsule. Worried: smaller, tilted, the outer lid drooping under a
    /// slanted brow. Panic: the biggest and roundest, wide open under high brows, glowing hard.
    /// Sleeping: heavy lids halfway down over a dim eye.
    public static func `for`(_ mood: CreatureState) -> EyeExpression {
        switch mood {
        case .happy:
            return EyeExpression(width: 10, height: 15.5, roundness: 2.4, glow: 0.5)
        case .worried:
            return EyeExpression(width: 9.5, height: 13, roundness: 2.3, outerLid: 0.34, innerLid: 0.06,
                                 tilt: 0.1, brow: 1, browLift: 2, browTilt: 2, drop: 2, glow: 0.45)
        case .panic:
            return EyeExpression(width: 11, height: 16.5, roundness: 2, brow: 1, browLift: 2.6,
                                 browTilt: 2.4, drop: 2.5, glow: 0.9)
        case .sleeping:
            return EyeExpression(width: 10, height: 13, roundness: 2.4, outerLid: 0.52, innerLid: 0.46,
                                 drop: -1, glow: 0.12)
        }
    }

    /// The expression `t` of the way to `other`; values of `t` outside 0...1 extrapolate.
    public func mixed(with other: EyeExpression, by t: CGFloat) -> EyeExpression {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return EyeExpression(
            width: mix(width, other.width), height: mix(height, other.height),
            roundness: mix(roundness, other.roundness),
            outerLid: mix(outerLid, other.outerLid), innerLid: mix(innerLid, other.innerLid),
            tilt: mix(tilt, other.tilt), brow: mix(brow, other.brow),
            browLift: mix(browLift, other.browLift), browTilt: mix(browTilt, other.browTilt),
            drop: mix(drop, other.drop), glow: mix(glow, other.glow)
        )
    }
}
