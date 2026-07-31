import XCTest
@testable import NicosHiddenMenuBar

/// DSP-001-A style pure geometry coverage for display attach/scale/offset cases.
final class DisplayGeometryTests: XCTestCase {
    func testValidOrderTwoLaneAndThreeLane() {
        XCTAssertTrue(
            MarkerGeometry.isValidOrder(
                toggleX: 1200, primaryX: 1000, secondaryX: nil, alwaysHiddenEnabled: false
            )
        )
        XCTAssertTrue(
            MarkerGeometry.isValidOrder(
                toggleX: 1200, primaryX: 1000, secondaryX: 800, alwaysHiddenEnabled: true
            )
        )
        XCTAssertFalse(
            MarkerGeometry.isValidOrder(
                toggleX: 900, primaryX: 1000, secondaryX: nil, alwaysHiddenEnabled: false
            )
        )
        XCTAssertFalse(
            MarkerGeometry.isValidOrder(
                toggleX: 1200, primaryX: 800, secondaryX: 1000, alwaysHiddenEnabled: true
            )
        )
    }

    func testCollapsedWidthClampsAndRejectsInvalid() {
        XCTAssertEqual(
            MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1500, primaryMinX: 1400),
            100
        )
        // Wide gap clamps up to maxCollapseWidth only when raw exceeds it.
        XCTAssertEqual(
            MarkerGeometry.collapsedWidth(visibleFrameMaxX: 20_000, primaryMinX: 0),
            MarkerGeometry.maxCollapseWidth
        )
        XCTAssertEqual(
            MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1500, primaryMinX: 0),
            1500
        )
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 100, primaryMinX: 200))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: nil, primaryMinX: 10))
    }

    func testCompactMinXRecoversAfterSpacerInflation() {
        // Item reported at minX=900 with length 200 while compact width is 8:
        // true compact origin is right-edge anchored → 900 + (200-8) = 1092.
        XCTAssertEqual(
            MarkerGeometry.compactMinX(currentMinX: 900, currentWidth: 200, compactWidth: 8),
            1092
        )
        XCTAssertNil(MarkerGeometry.compactMinX(currentMinX: nil, currentWidth: 10, compactWidth: 8))
    }

    func testReadyAnchorRequiresRightHalfOfScreen() {
        // Built-in 0…1512, mid 756.
        XCTAssertTrue(
            MarkerGeometry.isReadyStatusItemAnchor(1200, screenMinX: 0, screenMidX: 756, screenMaxX: 1512)
        )
        // External display offset to the right: 1512…3432.
        XCTAssertTrue(
            MarkerGeometry.isReadyStatusItemAnchor(3000, screenMinX: 1512, screenMidX: 2472, screenMaxX: 3432)
        )
        // Placeholder near left edge during launch.
        XCTAssertFalse(
            MarkerGeometry.isReadyStatusItemAnchor(40, screenMinX: 0, screenMidX: 756, screenMaxX: 1512)
        )
        // External removed → coordinate no longer on that screen.
        XCTAssertFalse(
            MarkerGeometry.isReadyStatusItemAnchor(3000, screenMinX: 0, screenMidX: 756, screenMaxX: 1512)
        )
    }

    func testScaledDisplayStillAcceptsRelativeRightHalf() {
        // "Retina math" still uses point space; mid remains geometric mid.
        XCTAssertTrue(
            MarkerGeometry.isReadyStatusItemAnchor(900, screenMinX: 0, screenMidX: 640, screenMaxX: 1280)
        )
    }

    func testRevealPanelLayoutSurvivesNarrowExternalStrip() {
        let layout = RevealPanelLayout.calculate(
            itemCount: 12,
            visibleFrame: CGRect(x: 2000, y: 0, width: 320, height: 900)
        )
        XCTAssertLessThanOrEqual(layout.width, 320 - 12 + 1)
        XCTAssertGreaterThanOrEqual(layout.columnCount, 1)
        XCTAssertLessThanOrEqual(layout.height, 360)
    }
}
