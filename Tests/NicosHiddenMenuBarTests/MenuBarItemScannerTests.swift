import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class MenuBarItemScannerTests: XCTestCase {
    private func item(_ id: CGWindowID, minX: Double, width: Double = 24) -> MenuBarItemScanner.Item {
        MenuBarItemScanner.Item(windowID: id, frame: CGRect(x: minX, y: 0, width: width, height: 24))
    }

    func testSummarizeSortsItemsLeftToRightAndReportsLeftmost() {
        let scan = MenuBarItemScanner.summarize(
            items: [item(1, minX: 900), item(2, minX: 300), item(3, minX: 600)],
            toggleMinX: nil,
            visibleMaxX: 1440,
            hasNotch: false
        )
        XCTAssertEqual(scan.items.map(\.windowID), [2, 3, 1])
        XCTAssertEqual(scan.leftmostMinX, 300)
    }

    func testHideableCountsOnlyItemsFullyLeftOfToggle() {
        // toggle at 700: items ending at/under 700 are hideable; the one at 690+24 is not.
        let scan = MenuBarItemScanner.summarize(
            items: [item(1, minX: 100), item(2, minX: 690), item(3, minX: 800)],
            toggleMinX: 700,
            visibleMaxX: 1440,
            hasNotch: false
        )
        XCTAssertEqual(scan.hideableItemCount, 1)  // only the item at 100 fully clears 700
    }

    func testAnyItemHiddenPastEdgeWhenHideableItemPushedBeyondVisibleMaxX() {
        // Explicit placement parked an item at x=1500, past visibleMaxX=1440.
        let scan = MenuBarItemScanner.summarize(
            items: [item(1, minX: 1500), item(2, minX: 200)],
            toggleMinX: 1450,
            visibleMaxX: 1440,
            hasNotch: false
        )
        XCTAssertTrue(scan.anyItemHiddenPastEdge)
    }

    func testNoItemHiddenWhenEverythingStaysOnScreen() {
        let scan = MenuBarItemScanner.summarize(
            items: [item(1, minX: 200), item(2, minX: 400)],
            toggleMinX: 1450,
            visibleMaxX: 1440,
            hasNotch: true
        )
        XCTAssertFalse(scan.anyItemHiddenPastEdge)
        XCTAssertTrue(scan.hasNotch)
    }
}
