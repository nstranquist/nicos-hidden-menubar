import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

/// Hidden + Overflow tiles share `discoveredItems(from:axLabels:)`.
final class SiblingExtraLabelTests: XCTestCase {
    private let pid: pid_t = 12

    func testSameAppUnderGapExtrasGetDistinctAXTitles() {
        let details = [
            extra(windowID: 1, x: 753, width: 31),
            extra(windowID: 2, x: 782, width: 64),
        ]
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: CGRect(x: 753, y: 4, width: 31, height: 24), pid: pid),
            .init(title: "HS ⚠3", frame: CGRect(x: 782, y: 4, width: 64, height: 24), pid: pid),
        ]

        let items = LiveMenuBarDiscoveryService.discoveredItems(
            from: details,
            axLabels: labels,
            appNameForPID: { _ in "Nicos Dev" }
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].displayName.contains("Flash"), items[0].displayName)
        XCTAssertTrue(items[1].displayName.contains("HS ⚠3"), items[1].displayName)
        XCTAssertNotEqual(items[0].displayName, items[1].displayName)
        XCTAssertFalse(items.allSatisfy { $0.displayName == "Nicos Dev" })
        XCTAssertEqual(items[0].displayName, "Nicos Dev — Flash")
        XCTAssertEqual(items[1].displayName, "Nicos Dev — HS ⚠3")
    }

    func testFarAXFramesStillPairLeftToRightOneToOne() {
        let details = [
            extra(windowID: 1, x: 753, width: 31),
            extra(windowID: 2, x: 782, width: 64),
        ]
        // AX frames are far from the under-notch CG frames — proximity returns nil.
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: CGRect(x: 100, y: 0, width: 24, height: 24), pid: pid),
            .init(title: "HS ⚠3", frame: CGRect(x: 200, y: 0, width: 24, height: 24), pid: pid),
        ]
        XCTAssertNil(
            MenuBarAccessibilityCatalog.bestTitle(
                for: details[0].frame,
                pid: pid,
                among: labels
            )
        )
        XCTAssertNil(
            MenuBarAccessibilityCatalog.bestTitle(
                for: details[1].frame,
                pid: pid,
                among: labels
            )
        )

        let items = LiveMenuBarDiscoveryService.discoveredItems(
            from: details,
            axLabels: labels,
            appNameForPID: { _ in "Nicos Dev" }
        )

        XCTAssertEqual(items[0].title, "Flash")
        XCTAssertEqual(items[1].title, "HS ⚠3")
        XCTAssertEqual(items[0].displayName, "Nicos Dev — Flash")
        XCTAssertEqual(items[1].displayName, "Nicos Dev — HS ⚠3")
        XCTAssertNotEqual(items[0].displayName, items[1].displayName)
        XCTAssertFalse(items.allSatisfy { $0.displayName == "Nicos Dev" })
    }

    func testProximityWinsOverLeftToRightPairing() {
        let details = [
            extra(windowID: 1, x: 198, width: 24),
            extra(windowID: 2, x: 753, width: 31),
        ]
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: CGRect(x: 90, y: 0, width: 24, height: 24), pid: pid),
            .init(title: "Focus", frame: CGRect(x: 200, y: 0, width: 24, height: 24), pid: pid),
        ]

        let items = LiveMenuBarDiscoveryService.discoveredItems(
            from: details,
            axLabels: labels,
            appNameForPID: { _ in "Nicos Dev" }
        )

        XCTAssertEqual(items[0].title, "Focus")
        XCTAssertEqual(items[1].title, "Flash")
        XCTAssertTrue(items[0].displayName.contains("Focus"))
        XCTAssertTrue(items[1].displayName.contains("Flash"))
    }

    func testAmbiguousSingleFarLabelDoesNotStealAndSiblingsGetOrdinals() {
        let details = [
            extra(windowID: 1, x: 753, width: 31),
            extra(windowID: 2, x: 782, width: 64),
        ]
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: CGRect(x: 100, y: 0, width: 24, height: 24), pid: pid)
        ]

        let items = LiveMenuBarDiscoveryService.discoveredItems(
            from: details,
            axLabels: labels,
            appNameForPID: { _ in "Nicos Dev" }
        )

        XCTAssertEqual(items[0].title, "")
        XCTAssertEqual(items[1].title, "")
        XCTAssertEqual(items[0].displayName, "Nicos Dev 1")
        XCTAssertEqual(items[1].displayName, "Nicos Dev 2")
        XCTAssertNotEqual(items[0].displayName, items[1].displayName)
        XCTAssertFalse(items.contains { $0.displayName == "Nicos Dev — Flash" })
    }

    func testGeometryLessPairDoesNotGuess() {
        let details = [
            extra(windowID: 1, x: 753, width: 31),
            extra(windowID: 2, x: 782, width: 64),
        ]
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: .null, pid: pid),
            .init(title: "HS ⚠3", frame: .null, pid: pid),
        ]

        let items = LiveMenuBarDiscoveryService.discoveredItems(
            from: details,
            axLabels: labels,
            appNameForPID: { _ in "Nicos Dev" }
        )

        XCTAssertEqual(items.map(\.title), ["", ""])
        XCTAssertEqual(Set(items.map(\.displayName)), Set(["Nicos Dev 1", "Nicos Dev 2"]))
    }

    func testVisibleTileLabelKeepsExtraTitleAfterAssigner() {
        let details = [
            extra(windowID: 1, x: 753, width: 31),
            extra(windowID: 2, x: 782, width: 64),
        ]
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: CGRect(x: 100, y: 0, width: 24, height: 24), pid: pid),
            .init(title: "HS ⚠3", frame: CGRect(x: 200, y: 0, width: 24, height: 24), pid: pid),
        ]
        let items = LiveMenuBarDiscoveryService.discoveredItems(
            from: details,
            axLabels: labels,
            appNameForPID: { _ in "Nicos Dev" }
        )
        let tiles = items.map { MenuBarExtraLabelAssigner.visibleTileLabel($0.displayName) }
        XCTAssertEqual(tiles, ["Flash", "HS ⚠3"])
        XCTAssertNotEqual(tiles[0], tiles[1])
        XCTAssertFalse(tiles.contains("Nicos Dev"))
    }

    func testVisibleTileLabelPassesThroughOrdinalsAndBareNames() {
        XCTAssertEqual(MenuBarExtraLabelAssigner.visibleTileLabel("Nicos Dev 1"), "Nicos Dev 1")
        XCTAssertEqual(MenuBarExtraLabelAssigner.visibleTileLabel("OrbStack"), "OrbStack")
        XCTAssertEqual(MenuBarExtraLabelAssigner.visibleTileLabel("Nicos Dev — "), "Nicos Dev —")
    }

    func testAssignerIsSectionAgnostic() {
        let extras = [
            MenuBarExtraLabelAssigner.Extra(
                pid: pid,
                frame: CGRect(x: 753, y: 4, width: 31, height: 24),
                windowTitle: "",
                ownerName: "Nicos Dev",
                appName: "Nicos Dev"
            ),
            MenuBarExtraLabelAssigner.Extra(
                pid: pid,
                frame: CGRect(x: 882, y: 4, width: 37, height: 24),
                windowTitle: "",
                ownerName: "Nicos Dev",
                appName: "Nicos Dev"
            ),
        ]
        let labels: [MenuBarAccessibilityCatalog.LabeledFrame] = [
            .init(title: "Flash", frame: CGRect(x: 100, y: 0, width: 24, height: 24), pid: pid),
            .init(title: "Scratchpad", frame: CGRect(x: 200, y: 0, width: 24, height: 24), pid: pid),
        ]
        let assigned = MenuBarExtraLabelAssigner.assign(extras: extras, axLabels: labels)
        // Same names whether the tiles later classify as Overflow or Hidden.
        XCTAssertEqual(assigned[0].displayName, "Nicos Dev — Flash")
        XCTAssertEqual(assigned[1].displayName, "Nicos Dev — Scratchpad")
    }

    private func extra(windowID: CGWindowID, x: Double, width: Double) -> MenuBarWindowInfo {
        MenuBarWindowInfo(
            windowID: windowID,
            frame: CGRect(x: x, y: 4, width: width, height: 24),
            ownerPID: pid,
            ownerName: "Nicos Dev",
            title: nil,
            isOnScreen: true
        )
    }
}
