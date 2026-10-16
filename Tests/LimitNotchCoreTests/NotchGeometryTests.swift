import CoreGraphics
import XCTest
@testable import LimitNotchCore

final class NotchGeometryTests: XCTestCase {
    // MacBook Air 13" at its default scaled resolution: 1470 × 956 pt, 32 pt notch.
    private let airFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let airVisible = CGRect(x: 0, y: 0, width: 1470, height: 924)

    private func notched() -> NotchGeometry {
        NotchGeometry(screenFrame: airFrame, visibleFrame: airVisible, safeAreaTop: 32,
                      auxiliaryTopLeftWidth: 640, auxiliaryTopRightWidth: 640)
    }

    func testNotchSizeComesFromSafeAreaAndAuxiliaryAreas() {
        let geometry = notched()
        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notchSize, CGSize(width: 190, height: 32))
        XCTAssertEqual(geometry.barHeight, 32)
        XCTAssertEqual(geometry.mascotDiameter, 22)
        XCTAssertEqual(geometry.collapsedSize, CGSize(width: 190 + 2 * NotchGeometry.earWidth, height: 32))
    }

    func testPanelIsCenteredOnTheNotchAndFlushWithTheTopEdge() {
        let geometry = notched()
        for expanded in [false, true] {
            let frame = geometry.panelFrame(expanded: expanded)
            XCTAssertEqual(frame.midX, airFrame.midX, accuracy: 0.001)
            XCTAssertEqual(frame.maxY, airFrame.maxY, accuracy: 0.001)
        }
        let expanded = geometry.panelFrame(expanded: true)
        XCTAssertEqual(expanded.width, NotchGeometry.minimumExpandedWidth)
        XCTAssertEqual(expanded.height, 32 + NotchGeometry.expandedContentHeight)
    }

    func testScreenWithoutNotchFallsBackToTopCenterPill() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(screenFrame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
                                     safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        XCTAssertFalse(geometry.hasNotch)
        XCTAssertEqual(geometry.notchSize, .zero)
        XCTAssertEqual(geometry.barHeight, NotchGeometry.fallbackPillHeight)
        XCTAssertEqual(geometry.mascotDiameter, 18)
        let pill = geometry.panelFrame(expanded: false)
        XCTAssertEqual(pill, CGRect(x: 960 - NotchGeometry.earWidth, y: 1080 - 28, width: 2 * NotchGeometry.earWidth, height: 28))
    }

    func testFallbackUsesTallMenuBarAndDefaultWhenMenuBarIsHidden() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let tall = NotchGeometry(screenFrame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1046),
                                 safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        XCTAssertEqual(tall.barHeight, 34)
        XCTAssertEqual(tall.mascotDiameter, 24)

        let hidden = NotchGeometry(screenFrame: frame, visibleFrame: frame, safeAreaTop: 0,
                                   auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        XCTAssertEqual(hidden.barHeight, NotchGeometry.fallbackPillHeight)
    }

    func testInconsistentNotchReportsFallBackToPill() {
        let missingArea = NotchGeometry(screenFrame: airFrame, visibleFrame: airVisible, safeAreaTop: 32,
                                        auxiliaryTopLeftWidth: 640, auxiliaryTopRightWidth: nil)
        XCTAssertFalse(missingArea.hasNotch)

        let noInset = NotchGeometry(screenFrame: airFrame, visibleFrame: airVisible, safeAreaTop: 0,
                                    auxiliaryTopLeftWidth: 640, auxiliaryTopRightWidth: 640)
        XCTAssertFalse(noInset.hasNotch)

        let overlapping = NotchGeometry(screenFrame: airFrame, visibleFrame: airVisible, safeAreaTop: 32,
                                        auxiliaryTopLeftWidth: 800, auxiliaryTopRightWidth: 800)
        XCTAssertFalse(overlapping.hasNotch)

        let tooWide = NotchGeometry(screenFrame: airFrame, visibleFrame: airVisible, safeAreaTop: 32,
                                    auxiliaryTopLeftWidth: 100, auxiliaryTopRightWidth: 100)
        XCTAssertFalse(tooWide.hasNotch)
        XCTAssertEqual(tooWide.panelFrame(expanded: false).midX, airFrame.midX, accuracy: 0.001)
    }

    func testSecondaryScreenOriginIsRespected() {
        let frame = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let geometry = NotchGeometry(screenFrame: frame, visibleFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1055),
                                     safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        let panel = geometry.panelFrame(expanded: true)
        XCTAssertEqual(panel.midX, -960, accuracy: 0.001)
        XCTAssertEqual(panel.maxY, 1280, accuracy: 0.001)
    }

    func testExpandedPanelNeverExceedsANarrowScreen() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let geometry = NotchGeometry(screenFrame: frame, visibleFrame: frame, safeAreaTop: 0,
                                     auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)
        let panel = geometry.panelFrame(expanded: true)
        XCTAssertEqual(panel.width, 400 - 2 * NotchGeometry.screenMargin)
        XCTAssertGreaterThanOrEqual(panel.minX, frame.minX)
        XCTAssertLessThanOrEqual(panel.maxX, frame.maxX)
    }
}
