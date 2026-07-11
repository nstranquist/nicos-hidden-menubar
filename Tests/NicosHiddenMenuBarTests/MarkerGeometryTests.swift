import XCTest
@testable import NicosHiddenMenuBar

final class MarkerGeometryTests: XCTestCase {
    func testCollapsedWidthUsesFrozenFormulaAndClamp() {
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1440, primaryMinX: 1420), 32.0)
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1512, primaryMinX: 1012), 500.0)
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 12050, primaryMinX: 10), 10000.0)
    }

    func testCollapsedWidthUsesGlobalRightEdgeForOffsetDisplays() {
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 4147, primaryMinX: -3611), 7758.0)
    }

    func testPreferredVisibleFrameMaxXPrefersReadableCandidatesInOrder() {
        XCTAssertEqual(
            MarkerGeometry.preferredVisibleFrameMaxX(
                primaryMinX: 1176,
                preferredVisibleFrameMaxX: [1956, 1728],
                fallbackVisibleFrameMaxX: [1728, 1956]
            ),
            1956
        )
    }

    func testPreferredVisibleFrameMaxXFallsBackToLargestReadableCandidate() {
        XCTAssertEqual(
            MarkerGeometry.preferredVisibleFrameMaxX(
                primaryMinX: 1176,
                preferredVisibleFrameMaxX: [nil, 1000],
                fallbackVisibleFrameMaxX: [1728, 1956]
            ),
            1956
        )
    }

    func testCollapsedWidthReturnsNilWhenGeometryIsUnreadable() {
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: nil, primaryMinX: 120))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1512, primaryMinX: nil))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 300, primaryMinX: 300))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 300, primaryMinX: 301))
        XCTAssertNil(
            MarkerGeometry.preferredVisibleFrameMaxX(
                primaryMinX: 300,
                preferredVisibleFrameMaxX: [nil, 300],
                fallbackVisibleFrameMaxX: [299, 300]
            )
        )
    }

    func testMarkerOrderPredicateOneSeparator() {
        XCTAssertTrue(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 800, secondaryX: nil, alwaysHiddenEnabled: false))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 800, primaryX: 800, secondaryX: nil, alwaysHiddenEnabled: false))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: nil, primaryX: 800, secondaryX: nil, alwaysHiddenEnabled: false))
    }

    func testMarkerOrderPredicateTwoSeparators() {
        XCTAssertTrue(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 850, secondaryX: 800, alwaysHiddenEnabled: true))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 850, secondaryX: 860, alwaysHiddenEnabled: true))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: nil, secondaryX: 800, alwaysHiddenEnabled: true))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 850, secondaryX: nil, alwaysHiddenEnabled: true))
    }

    func testMenuBarBandMatchesOnlyTheTopStripAboveVisibleFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1091)

        XCTAssertTrue(
            MarkerGeometry.isPointInMenuBarBand(
                CGPoint(x: 300, y: 1108),
                frame: frame,
                visibleFrame: visibleFrame
            )
        )
        XCTAssertFalse(
            MarkerGeometry.isPointInMenuBarBand(
                CGPoint(x: 300, y: 1080),
                frame: frame,
                visibleFrame: visibleFrame
            )
        )
    }
}
