import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class ParityModelTests: XCTestCase {
    func testMenuBarItemInfoKeyAndImmovability() {
        let cc = MenuBarItemInfo(namespace: "com.apple.controlcenter", title: "WiFi")
        XCTAssertTrue(cc.key.hasPrefix("v1:"))
        XCTAssertEqual(cc.legacyKey, "com.apple.controlcenter:WiFi")
        XCTAssertTrue(cc.isLikelyImmovable)

        let regular = MenuBarItemInfo(namespace: "com.example.app", title: "")
        XCTAssertFalse(regular.isLikelyImmovable)
    }

    func testControlSectionSeedPositionsAreOrderedRightToLeft() {
        XCTAssertLessThan(ControlSection.visible.seedPreferredPosition, ControlSection.hidden.seedPreferredPosition)
        XCTAssertLessThan(ControlSection.hidden.seedPreferredPosition, ControlSection.alwaysHidden.seedPreferredPosition)
        XCTAssertEqual(Set(ControlSection.allCases.map(\.autosaveName)).count, 3)
    }

    func testConfigDecodesWithoutParityFieldsAndDefaultsOff() throws {
        // Simulate an older persisted config that predates the parity additions.
        let legacy = HiddenBarConfig.default
        var data = try JSONEncoder().encode(legacy)
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "revealPanelEnabled")
        dict.removeValue(forKey: "revealMode")
        dict.removeValue(forKey: "enableExperimentalItemMovement")
        dict.removeValue(forKey: "revealOnHover")
        dict.removeValue(forKey: "rescueOverflowIntoHiddenLane")
        data = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(HiddenBarConfig.self, from: data)
        XCTAssertFalse(decoded.isRevealPanelEnabled)
        XCTAssertFalse(decoded.isExperimentalItemMovementEnabled)
        XCTAssertFalse(decoded.isRevealOnHoverEnabled)
        XCTAssertFalse(decoded.isRescueOverflowIntoHiddenLaneEnabled)
        XCTAssertEqual(decoded.configuredRevealMode, .automatic)
    }

    func testRevealPanelHiddenCandidatesFilterLeftOfToggleAndExcludeOwnControls() {
        func item(_ id: CGWindowID, minX: Double, width: Double, ownerPID: Int32 = 1, name: String) -> MenuBarDiscoveredItem {
            let identity = MenuBarItemIdentity(namespace: name, title: "")
            return MenuBarDiscoveredItem(
                handle: MenuBarItemHandle(windowID: id, identity: identity),
                identity: identity,
                ownerPID: ownerPID,
                ownerName: name,
                title: "",
                displayName: name,
                frame: CGRect(x: minX, y: 0, width: width, height: 24),
            )
        }
        let items = [
            item(1, minX: 100, width: 24, name: "com.example.a"),
            item(2, minX: 200, width: 24, name: "com.apple.controlcenter"),
            item(3, minX: 900, width: 24, name: "com.example.b"),
            item(4, minX: 300, width: 24, ownerPID: 42, name: "Nicos Hidden Bar"),
        ]
        let hidden = RevealPanelModel.hiddenCandidates(items, leftOfX: 700, excludingOwnerPID: 42)
        XCTAssertEqual(hidden.map(\.handle.windowID), [1, 2])
    }

    func testRevealPanelHiddenCandidatesWithoutAnchorReturnsAllMovable() {
        let identity = MenuBarItemIdentity(namespace: "com.example.x", title: "")
        let item = MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(windowID: 5, identity: identity),
            identity: identity,
            ownerPID: 1,
            ownerName: "com.example.x",
            title: "",
            displayName: "Example",
            frame: CGRect(x: 10, y: 0, width: 20, height: 24)
        )
        XCTAssertEqual(RevealPanelModel.hiddenCandidates([item], leftOfX: nil).count, 1)
    }

    func testRevealPanelHiddenCandidatesUseLaneBoundsAndRepairFallback() {
        func item(_ id: CGWindowID, minX: Double, ownerPID: Int32 = 1) -> MenuBarDiscoveredItem {
            let identity = MenuBarItemIdentity(namespace: "com.example.\(id)", title: "")
            return MenuBarDiscoveredItem(
                handle: MenuBarItemHandle(windowID: id, identity: identity),
                identity: identity,
                ownerPID: ownerPID,
                ownerName: "app",
                title: "",
                displayName: "app",
                frame: CGRect(x: minX, y: 0, width: 24, height: 24)
            )
        }
        let items = [
            item(1, minX: 1_050),
            item(2, minX: 1_250),
            item(3, minX: 1_450),
            item(4, minX: 1_300, ownerPID: 99),
        ]
        let usable = MenuBarLaneBounds(
            toggleX: 1_400,
            primaryX: 1_200,
            secondaryX: 1_100,
            alwaysHiddenEnabled: true,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let hidden = RevealPanelModel.hiddenCandidates(items, laneBounds: usable, excludingOwnerPID: 99)
        XCTAssertEqual(Set(hidden.map(\.handle.windowID)), Set([1, 2]))

        let broken = MenuBarLaneBounds(
            toggleX: -3_772,
            primaryX: -3_780,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let fallback = RevealPanelModel.hiddenCandidates(items, laneBounds: broken, excludingOwnerPID: 99)
        // Repair fallback lists on-screen third-party items so the panel is not empty.
        XCTAssertEqual(Set(fallback.map(\.handle.windowID)), Set([1, 2, 3]))
    }

    func testConfigRoundTripsParityFlags() throws {
        var config = HiddenBarConfig.default
        config.revealPanelEnabled = true
        config.enableExperimentalItemMovement = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HiddenBarConfig.self, from: data)
        XCTAssertTrue(decoded.isRevealPanelEnabled)
        XCTAssertTrue(decoded.isExperimentalItemMovementEnabled)
    }

    func testLegacyIceBarEnabledKeyMigratesToRevealPanel() throws {
        // Disk still has iceBarEnabled from the old branding.
        var legacy = HiddenBarConfig.default
        legacy.iceBarEnabled = true
        legacy.revealPanelEnabled = nil
        XCTAssertTrue(legacy.isRevealPanelEnabled)
        XCTAssertEqual(legacy.configuredRevealMode, .belowMenuBar)

        let migrated = try legacy.validated()
        XCTAssertEqual(migrated.revealPanelEnabled, true)
        XCTAssertNil(migrated.iceBarEnabled)

        // Encode should not re-introduce the Ice product name as a public key
        // once migrated (nil optionals omit under encodeIfPresent).
        let data = try JSONEncoder().encode(migrated)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(dict["iceBarEnabled"])
        XCTAssertEqual(dict["revealPanelEnabled"] as? Bool, true)
    }

    func testRevealModeMigratesLegacyFlagAndResolvesNotches() throws {
        var config = HiddenBarConfig.default
        config.revealPanelEnabled = true
        XCTAssertEqual(config.configuredRevealMode, .belowMenuBar)

        config.revealPanelEnabled = nil
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: false), .inline)
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: true), .belowMenuBar)

        config.revealMode = .inline
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: true), .inline)

        config.revealMode = .belowMenuBar
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: false), .belowMenuBar)
    }

    func testRevealPanelLayoutClampsToActiveScreenAndWrapsItems() {
        let small = RevealPanelLayout.calculate(
            itemCount: 20,
            visibleFrame: CGRect(x: 1_500, y: 0, width: 500, height: 800)
        )
        XCTAssertLessThanOrEqual(small.width, 500 - 16 + 1)
        XCTAssertGreaterThan(small.height, 54)
        XCTAssertGreaterThan(small.columnCount, 1)

        let compact = RevealPanelLayout.calculate(
            itemCount: 3,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_496, height: 900)
        )
        XCTAssertEqual(compact.columnCount, 3)
        // One row of tiles + chrome + status — no scroll for 3 items.
        let expected =
            RevealPanelLayout.rowHeight + RevealPanelLayout.chromeHeight + RevealPanelLayout.statusHeight
        XCTAssertEqual(compact.height, expected)
        XCTAssertFalse(compact.needsScroll)
        XCTAssertFalse(compact.showsSearch)
    }

    func testRevealPanelLayoutTwelveItemsFitsWithoutScrollOnWideDisplay() {
        let layout = RevealPanelLayout.calculate(
            itemCount: 12,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_496, height: 900)
        )
        // Prefer one row when columns allow.
        XCTAssertLessThanOrEqual(layout.columnCount, RevealPanelLayout.maxColumnsPreferred)
        XCTAssertFalse(layout.needsScroll, "12 items on a wide display should not force scroll")
        XCTAssertFalse(layout.showsSearch)
    }

    func testChevronColorNormalizedAndResolved() {
        XCTAssertEqual(ChevronIconColor.normalized(nil), .white)
        XCTAssertEqual(ChevronIconColor.normalized("blue"), .blue)
        XCTAssertEqual(ChevronIconColor.normalized("nope"), .white)
        var config = HiddenBarConfig.default
        config.chevronColor = .blue
        XCTAssertEqual(config.resolvedChevronColor, .blue)
        config.chevronColor = nil
        XCTAssertEqual(config.resolvedChevronColor, .white)
    }

    func testRevealPanelDropPreviewInsertionIndex() {
        let keys = ["a", "b", "c"]
        XCTAssertEqual(
            RevealPanelDropPreview.insertionIndex(orderedKeys: keys, draggedKey: "c", beforeKey: "a"),
            0
        )
        XCTAssertEqual(
            RevealPanelDropPreview.insertionIndex(orderedKeys: keys, draggedKey: "a", beforeKey: "c"),
            1
        )
        XCTAssertEqual(
            RevealPanelDropPreview.insertionIndex(orderedKeys: keys, draggedKey: "b", beforeKey: nil),
            2
        )
        XCTAssertTrue(RevealPanelDropPreview.shouldHighlightTarget(draggedKey: "a", beforeKey: "b"))
        XCTAssertFalse(RevealPanelDropPreview.shouldHighlightTarget(draggedKey: "a", beforeKey: "a"))
        XCTAssertFalse(RevealPanelDropPreview.shouldHighlightTarget(draggedKey: nil, beforeKey: "b"))
    }

    func testRevealPanelDropPreviewEndAndAfterTile() {
        let keys = ["a", "b", "c"]
        // Right half of last tile → append (beforeKey nil).
        XCTAssertNil(
            RevealPanelDropPreview.beforeKeyForTileDrop(
                orderedKeys: keys,
                draggedKey: "a",
                targetKey: "c",
                dropXInTile: 0.8,
                tileWidth: 1
            )
        )
        // Right half of middle → before next.
        XCTAssertEqual(
            RevealPanelDropPreview.beforeKeyForTileDrop(
                orderedKeys: keys,
                draggedKey: "a",
                targetKey: "b",
                dropXInTile: 0.8,
                tileWidth: 1
            ),
            "c"
        )
        // Left half → before target.
        XCTAssertEqual(
            RevealPanelDropPreview.beforeKeyForTileDrop(
                orderedKeys: keys,
                draggedKey: "c",
                targetKey: "b",
                dropXInTile: 0.2,
                tileWidth: 1
            ),
            "b"
        )
    }

    func testRevealPanelHorizontalShiftsOpenGap() {
        let keys = ["a", "b", "c", "d"]
        // Drag "a" toward end (insertIndex 3 after remove).
        let shifts = RevealPanelDropPreview.horizontalShifts(
            orderedKeys: keys,
            draggedKey: "a",
            insertIndex: 3,
            gap: 10
        )
        XCTAssertEqual(shifts["a"], 0)
        // b,c,d were right of source → close hole (-10), and all >= insert 3 get +10 only at end
        // remaining = [b,c,d], insertIndex 3 → none get +gap from insert; all get -gap from hole
        XCTAssertEqual(shifts["b"], -10)
        XCTAssertEqual(shifts["c"], -10)
        XCTAssertEqual(shifts["d"], -10)

        // Drag "d" to front (insertIndex 0).
        let shifts2 = RevealPanelDropPreview.horizontalShifts(
            orderedKeys: keys,
            draggedKey: "d",
            insertIndex: 0,
            gap: 10
        )
        // remaining [a,b,c] all i >= 0 get +10; none were right of d
        XCTAssertEqual(shifts2["a"], 10)
        XCTAssertEqual(shifts2["b"], 10)
        XCTAssertEqual(shifts2["c"], 10)
    }

    func testMenuBarBandDetection() {
        let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        let visible = CGRect(x: 0, y: 0, width: 1500, height: 978)  // menu bar ~22pt
        XCTAssertTrue(
            MenuBarBridging.isInMenuBarBand(
                CGPoint(x: 100, y: 990),
                screen: screen,
                visible: visible
            )
        )
        XCTAssertFalse(
            MenuBarBridging.isInMenuBarBand(
                CGPoint(x: 100, y: 500),
                screen: screen,
                visible: visible
            )
        )
    }

    func testUserMenuBarCommandDragPolicy() {
        XCTAssertTrue(
            UserMenuBarCommandDragPolicy.shouldRevealMarkersForCommandDrag(
                isCommand: true,
                isInMenuBarBand: true
            )
        )
        XCTAssertFalse(
            UserMenuBarCommandDragPolicy.shouldRevealMarkersForCommandDrag(
                isCommand: false,
                isInMenuBarBand: true
            )
        )
        XCTAssertFalse(
            UserMenuBarCommandDragPolicy.shouldRevealMarkersForCommandDrag(
                isCommand: true,
                isInMenuBarBand: false
            )
        )
        XCTAssertTrue(UserMenuBarCommandDragPolicy.shouldSuppressCollapseReapply(isUserDragging: true))
        XCTAssertFalse(UserMenuBarCommandDragPolicy.shouldSuppressCollapseReapply(isUserDragging: false))
    }

    func testCrossBarDropPolicyClassify() {
        XCTAssertEqual(
            CrossBarDropPolicy.classify(
                draggedFromPanel: true,
                dropOnUnhideZone: true,
                dropOnPanelTileOrBackground: false,
                dropOnMenuBarBand: false
            ),
            .unhideToMenuBar
        )
        XCTAssertEqual(
            CrossBarDropPolicy.classify(
                draggedFromPanel: true,
                dropOnUnhideZone: false,
                dropOnPanelTileOrBackground: true,
                dropOnMenuBarBand: false
            ),
            .panelReorder
        )
        XCTAssertEqual(
            CrossBarDropPolicy.classify(
                draggedFromPanel: false,
                dropOnUnhideZone: false,
                dropOnPanelTileOrBackground: true,
                dropOnMenuBarBand: false
            ),
            .hideIntoPanel
        )
        XCTAssertNil(
            CrossBarDropPolicy.classify(
                draggedFromPanel: false,
                dropOnUnhideZone: false,
                dropOnPanelTileOrBackground: false,
                dropOnMenuBarBand: false
            )
        )
    }

    func testUnhidePanelRemovalIsSuccessGated() {
        // AX deny / mover failure must not drop the tile (skeptic AC).
        XCTAssertFalse(
            CrossBarDropPolicy.shouldRemovePanelItemAfterUnhide(moveSucceeded: false)
        )
        XCTAssertTrue(
            CrossBarDropPolicy.shouldRemovePanelItemAfterUnhide(moveSucceeded: true)
        )
        // Simulates RevealPanelView: only mutate list when policy says so.
        var panelKeys = ["keep-me", "unhide-me"]
        let moveOK = false
        if CrossBarDropPolicy.shouldRemovePanelItemAfterUnhide(moveSucceeded: moveOK) {
            panelKeys.removeAll { $0 == "unhide-me" }
        }
        XCTAssertEqual(panelKeys, ["keep-me", "unhide-me"])
        let moveOK2 = true
        if CrossBarDropPolicy.shouldRemovePanelItemAfterUnhide(moveSucceeded: moveOK2) {
            panelKeys.removeAll { $0 == "unhide-me" }
        }
        XCTAssertEqual(panelKeys, ["keep-me"])
    }

    func testRevealPanelReorderMovesBeforeTarget() {
        func cap(_ id: CGWindowID, _ name: String) -> MenuBarCapturedItem {
            let identity = MenuBarItemIdentity(namespace: "com.example.\(name)", title: name)
            let item = MenuBarDiscoveredItem(
                handle: MenuBarItemHandle(windowID: id, identity: identity),
                identity: identity,
                ownerPID: 1,
                ownerName: name,
                title: name,
                displayName: name,
                frame: CGRect(x: Double(id) * 10, y: 0, width: 20, height: 20)
            )
            return MenuBarCapturedItem(item: item, image: nil, scale: 2)
        }
        let items = [cap(1, "A"), cap(2, "B"), cap(3, "C")]
        let keys = items.map(\.item.identity.key)
        let result = RevealPanelReorder.move(
            items: items,
            draggedKey: keys[2],  // C
            beforeKey: keys[0]  // before A
        )
        XCTAssertEqual(result?.items.map(\.item.displayName), ["C", "A", "B"])
        XCTAssertEqual(result?.draggedWindowID, 3)
        XCTAssertEqual(result?.beforeWindowID, 1)
    }

    func testRevealPanelPresentationDropsUnparkedControlCenterNoise() {
        let ccNS = ControlCenterModules.controlCenterNamespace
        let items: [MenuBarDiscoveredItem] = (0..<5).map { i in
            let id = MenuBarItemIdentity(
                namespace: ccNS,
                title: "",
                moduleID: "module",
                ordinal: i
            )
            return MenuBarDiscoveredItem(
                handle: MenuBarItemHandle(windowID: CGWindowID(100 + i), identity: id),
                identity: id,
                ownerPID: 1,
                ownerName: "Control Center",
                title: "",
                displayName: ControlCenterModules.displayName(
                    forModuleID: "module",
                    title: "",
                    ordinal: i
                ) ?? "Control Center",
                frame: CGRect(x: 100 + Double(i) * 30, y: 0, width: 24, height: 24)
            )
        }
        let appID = MenuBarItemIdentity(namespace: "com.example.app", title: "App")
        let app = MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(windowID: 50, identity: appID),
            identity: appID,
            ownerPID: 2,
            ownerName: "App",
            title: "App",
            displayName: "App",
            frame: CGRect(x: 50, y: 0, width: 24, height: 24)
        )
        let all = items + [app]
        let refined = RevealPanelPresentation.refine(all, parkedWindowIDs: [])
        XCTAssertEqual(refined.count, 1)
        XCTAssertEqual(refined.first?.displayName, "App")

        // Parked generic CC kept once.
        let parked = RevealPanelPresentation.refine(
            all,
            parkedWindowIDs: [100, 101, 102]
        )
        XCTAssertEqual(parked.filter { $0.identity.namespace == ccNS }.count, 1)
        XCTAssertTrue(parked.contains { $0.displayName == "App" })
    }
}
