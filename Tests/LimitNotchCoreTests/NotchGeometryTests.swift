import CoreGraphics
import XCTest
@testable import LimitNotchCore

final class NotchGeometryTests: XCTestCase {
    // MacBook Air 13" at its default scaled resolution, as NSScreen reports it:
    // 1470 × 956 pt, auxiliary areas 645.5 pt wide, 32 pt safe area → a 179 × 32 pt notch.
    private let airFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let airVisible = CGRect(x: 0, y: 0, width: 1470, height: 923)

    private func notched(left: CGFloat = 645.5, right: CGFloat = 645.5, top: CGFloat = 32,
                         frame: CGRect? = nil) -> NotchGeometry {
        let frame = frame ?? airFrame
        return NotchGeometry(screenFrame: frame, visibleFrame: frame.insetBy(dx: 0, dy: top / 2).offsetBy(dx: 0, dy: -top / 2),
                             safeAreaTop: top, auxiliaryTopLeftWidth: left, auxiliaryTopRightWidth: right, scale: 2)
    }

    func testNotchRectMatchesTheHardwareCutout() {
        let geometry = notched()
        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 645.5, y: 924, width: 179, height: 32))
        XCTAssertEqual(geometry.notchSize, CGSize(width: 179, height: 32))
        XCTAssertEqual(geometry.barHeight, 32)
        XCTAssertEqual(geometry.bodyWidth, 179)
    }

    func testCollapsedBodyIsTheNotchPlusTwoHairlineEars() {
        let geometry = notched()
        let collapsed = geometry.panelFrame(expanded: false)
        // As tall as the notch, flush with the top edge and centered on the camera housing.
        XCTAssertEqual(collapsed.height, geometry.notchRect.height)
        XCTAssertEqual(collapsed.maxY, geometry.notchRect.maxY)
        XCTAssertEqual(collapsed.midX, geometry.notchRect.midX, accuracy: 0.001)
        // The 179 pt notch plus a 15 pt ear on each side and no flare: 209 × 32.
        XCTAssertEqual(geometry.collapsedBodyWidth, 209)
        XCTAssertEqual(geometry.collapsedSize, CGSize(width: 209, height: 32))
        XCTAssertEqual(collapsed, CGRect(x: 630.5, y: 924, width: 209, height: 32))
        XCTAssertEqual(collapsed.minX, geometry.notchRect.minX - NotchGeometry.earWidth)
        XCTAssertEqual(collapsed.maxX, geometry.notchRect.maxX + NotchGeometry.earWidth)
    }

    func testEarsAreAboutOneEyeWide() {
        let widest = [CreatureState.happy, .worried, .panic, .sleeping]
            .map { EyeExpression.for($0).width }.max() ?? 0
        // Each ear adds at most a few points of black around its eye.
        XCTAssertLessThanOrEqual(NotchGeometry.earWidth - widest, 4)
        XCTAssertLessThanOrEqual(notched().collapsedBodyWidth - 179, 2 * (widest + 4))
    }

    func testEyesStayBesideTheCamera() {
        let geometry = notched()
        let notchLeft = NotchGeometry.earWidth
        let notchRight = notchLeft + geometry.notchRect.width
        let box = NotchGeometry.eyeBox
        // Each eye's box is centered in its ear: on visible pixels, never behind the camera housing.
        let left = geometry.leftEarCenter
        XCTAssertEqual(left, CGPoint(x: 7.5, y: 16))
        XCTAssertLessThanOrEqual(left.x + box.width / 2, notchLeft)
        XCTAssertGreaterThanOrEqual(left.x - box.width / 2, 0)
        let right = geometry.rightEarCenter
        XCTAssertEqual(right, CGPoint(x: geometry.collapsedSize.width - 7.5, y: 16))
        XCTAssertGreaterThanOrEqual(right.x - box.width / 2, notchRight)
        XCTAssertLessThanOrEqual(right.x + box.width / 2, geometry.collapsedSize.width)
        // The box fits in the band, and every expression fits in the box.
        XCTAssertLessThanOrEqual(box.height, geometry.barHeight)
        for mood in [CreatureState.happy, .worried, .panic, .sleeping] {
            let eye = EyeExpression.for(mood)
            XCTAssertLessThanOrEqual(eye.width, box.width, "\(mood)")
            XCTAssertLessThanOrEqual(eye.height, box.height, "\(mood)")
        }
    }

    func testOutlineMorphsFromEarsToIsland() {
        let collapsed = notched().outline(progress: 0)
        XCTAssertEqual(collapsed, NotchOutline(topRadius: 0, bottomRadius: 8))
        let expanded = notched().outline(progress: 1)
        XCTAssertEqual(expanded, NotchOutline(topRadius: 10, bottomRadius: 28))
        // Halfway through the spring the radius is halfway between the two shapes.
        XCTAssertEqual(notched().outline(progress: 0.5).bottomRadius, (8 + 28) / 2)
        XCTAssertEqual(notched().outline(progress: 3), expanded)
    }

    func testOutlineFillsItsRectWithAFlatTop() {
        let rect = CGRect(origin: .zero, size: notched().collapsedSize)
        let path = notched().outline(progress: 0).path(in: rect)
        XCTAssertEqual(path.boundingBoxOfPath.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.height, rect.height, accuracy: 0.001)
        // Inside under the notch and in the ears, outside at the extreme bottom corners.
        XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: rect.height - 0.5)))
        XCTAssertTrue(path.contains(notched().leftEarCenter))
        XCTAssertTrue(path.contains(notched().rightEarCenter))
        // Collapsed, the sides drop straight from the top edge.
        XCTAssertTrue(path.contains(CGPoint(x: 0.5, y: 0.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 0.5, y: rect.height / 2)))
        // Expanded, the shoulders flare out only at the top edge.
        let island = CGRect(origin: .zero, size: notched().expandedSize)
        let open = notched().outline(progress: 1).path(in: island)
        XCTAssertTrue(open.contains(CGPoint(x: 2, y: 0.2)))
        XCTAssertFalse(open.contains(CGPoint(x: 2, y: 6)))
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: rect.height - 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: rect.width - 0.5, y: rect.height - 0.5)))
        XCTAssertTrue(NotchOutline(topRadius: 4, bottomRadius: 8).path(in: .zero).isEmpty)
    }

    func testAsymmetricAuxiliaryAreasCenterOnTheRealNotch() {
        let geometry = notched(left: 640, right: 651)
        XCTAssertEqual(geometry.notchRect.minX, 640)
        XCTAssertEqual(geometry.notchRect.width, 179)
        for expanded in [false, true] {
            XCTAssertEqual(geometry.panelFrame(expanded: expanded).midX, geometry.notchRect.midX, accuracy: 0.5)
        }
    }

    func testFramesArePixelAligned() {
        for scale: CGFloat in [1, 2] {
            let geometry = NotchGeometry(screenFrame: airFrame, visibleFrame: airVisible, safeAreaTop: 32,
                                         auxiliaryTopLeftWidth: 645.5, auxiliaryTopRightWidth: 645.5, scale: scale)
            for expanded in [false, true] {
                let frame = geometry.panelFrame(expanded: expanded)
                for edge in [frame.minX, frame.maxX, frame.minY, frame.maxY] {
                    XCTAssertEqual((edge * scale).rounded(), edge * scale, "\(edge) at @\(scale)x")
                }
            }
        }
    }

    func testExpandedPanelEnclosesTheCollapsedOne() {
        let geometry = notched()
        let collapsed = geometry.panelFrame(expanded: false)
        let expanded = geometry.panelFrame(expanded: true)
        XCTAssertTrue(expanded.contains(collapsed))
        XCTAssertEqual(expanded.maxY, airFrame.maxY)
        // The mouth opens downward into a 260 × 138 island plus 10 pt shoulders.
        XCTAssertEqual(geometry.expandedBodyWidth, 260)
        XCTAssertEqual(expanded.width, 280)
        XCTAssertEqual(expanded.height, 138)
        // A wider notch keeps a 40 pt margin on each side of the camera.
        XCTAssertEqual(notched(left: 600, right: 600).expandedBodyWidth, 270 + 80)
    }

    func testScreenWithoutNotchFallsBackToTopCenterPill() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(screenFrame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
                                     safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, scale: 1)
        XCTAssertFalse(geometry.hasNotch)
        XCTAssertEqual(geometry.notchRect, .zero)
        XCTAssertEqual(geometry.barHeight, NotchGeometry.fallbackPillHeight)
        let pill = geometry.panelFrame(expanded: false)
        XCTAssertEqual(pill.midX, 960, accuracy: 0.5)
        XCTAssertEqual(pill.maxY, 1080)
        XCTAssertEqual(pill.height, 28)
        XCTAssertEqual(pill.width, NotchGeometry.fallbackBridgeWidth + 2 * NotchGeometry.earWidth
                       + 2 * NotchGeometry.collapsedShoulder)
    }

    func testFallbackUsesTallMenuBarAndDefaultWhenMenuBarIsHidden() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let tall = NotchGeometry(screenFrame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1046),
                                 safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        XCTAssertEqual(tall.barHeight, 34)
        XCTAssertEqual(tall.leftEarCenter.y, 17)

        let hidden = NotchGeometry(screenFrame: frame, visibleFrame: frame, safeAreaTop: 0,
                                   auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        XCTAssertEqual(hidden.barHeight, NotchGeometry.fallbackPillHeight)
    }

    func testInconsistentNotchReportsFallBackToPill() {
        XCTAssertFalse(notched(left: 645.5, right: 0).hasNotch)
        XCTAssertFalse(notched(top: 0).hasNotch)
        XCTAssertFalse(notched(left: 800, right: 800).hasNotch)
        let tooWide = notched(left: 100, right: 100)
        XCTAssertFalse(tooWide.hasNotch)
        XCTAssertEqual(tooWide.panelFrame(expanded: false).midX, airFrame.midX, accuracy: 0.5)
    }

    func testSecondaryScreenOriginIsRespected() {
        let frame = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let geometry = NotchGeometry(screenFrame: frame, visibleFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1055),
                                     safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        let panel = geometry.panelFrame(expanded: true)
        XCTAssertEqual(panel.midX, -960, accuracy: 0.001)
        XCTAssertEqual(panel.maxY, 1280, accuracy: 0.001)

        let notchedFrame = CGRect(x: 2560, y: 0, width: 1512, height: 982)
        let builtIn = notched(left: 662, right: 662, frame: notchedFrame)
        XCTAssertEqual(builtIn.notchRect, CGRect(x: 3222, y: 950, width: 188, height: 32))
        XCTAssertEqual(builtIn.panelFrame(expanded: false).midX, builtIn.notchRect.midX, accuracy: 0.001)
    }

    func testExpandedPanelNeverExceedsANarrowScreen() {
        let frame = CGRect(x: 0, y: 0, width: 260, height: 300)
        let geometry = NotchGeometry(screenFrame: frame, visibleFrame: frame, safeAreaTop: 0,
                                     auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        let panel = geometry.panelFrame(expanded: true)
        XCTAssertEqual(panel.width, 260 - 2 * NotchGeometry.screenMargin)
        XCTAssertGreaterThanOrEqual(panel.minX, frame.minX)
        XCTAssertLessThanOrEqual(panel.maxX, frame.maxX)
    }
}
