import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class AccessibilityLabelTests: XCTestCase {
    func testBestTitleMatchesNearestFrameOnSamePID() {
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Wi‑Fi", frame: CGRect(x: 100, y: 0, width: 24, height: 24), pid: 42),
            .init(title: "Focus", frame: CGRect(x: 200, y: 0, width: 24, height: 24), pid: 42),
            .init(title: "OtherApp", frame: CGRect(x: 200, y: 0, width: 24, height: 24), pid: 99),
        ]

        let wifi = MenuBarAccessibilityCatalog.bestTitle(
            for: CGRect(x: 102, y: 0, width: 22, height: 24),
            pid: 42,
            among: labels
        )
        let focus = MenuBarAccessibilityCatalog.bestTitle(
            for: CGRect(x: 198, y: 0, width: 24, height: 24),
            pid: 42,
            among: labels
        )
        XCTAssertEqual(wifi, "Wi‑Fi")
        XCTAssertEqual(focus, "Focus")
    }

    func testBestTitleIgnoresFarFrames() {
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Wi‑Fi", frame: CGRect(x: 100, y: 0, width: 24, height: 24), pid: 42)
        ]
        let title = MenuBarAccessibilityCatalog.bestTitle(
            for: CGRect(x: 800, y: 0, width: 24, height: 24),
            pid: 42,
            among: labels
        )
        XCTAssertNil(title)
    }

    func testBestTitleSingleGeometryLessLabelFallsBack() {
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Bluetooth", frame: .null, pid: 7)
        ]
        let title = MenuBarAccessibilityCatalog.bestTitle(
            for: CGRect(x: 10, y: 0, width: 20, height: 20),
            pid: 7,
            among: labels
        )
        XCTAssertEqual(title, "Bluetooth")
    }

    func testBestTitleMultipleGeometryLessLabelsDoNotGuess() {
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "A", frame: .null, pid: 7),
            .init(title: "B", frame: .null, pid: 7),
        ]
        let title = MenuBarAccessibilityCatalog.bestTitle(
            for: CGRect(x: 10, y: 0, width: 20, height: 20),
            pid: 7,
            among: labels
        )
        XCTAssertNil(title)
    }

    func testIsWithinProximityMatchesBestTitleWindow() {
        let near = CGRect(x: 102, y: 0, width: 22, height: 24)
        let label = CGRect(x: 100, y: 0, width: 24, height: 24)
        XCTAssertTrue(MenuBarAccessibilityCatalog.isWithinProximity(extra: near, label: label))
        let far = CGRect(x: 800, y: 0, width: 24, height: 24)
        XCTAssertFalse(MenuBarAccessibilityCatalog.isWithinProximity(extra: far, label: label))
        XCTAssertFalse(MenuBarAccessibilityCatalog.isWithinProximity(extra: near, label: .null))
    }
}
