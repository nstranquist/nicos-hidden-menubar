import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class NotchGeometryTests: XCTestCase {
    /// Matches a typical MacBook Pro band: left aux maxX≈668, right aux 828…1496.
    private let liveLike = NotchBandGeometry(
        leftUsableMaxX: 668,
        rightUsableMinX: 828,
        rightUsableMaxX: 1_496,
        screenMinX: 0,
        screenMaxX: 1_496
    )

    private let overflowLayout = MenuBarOverflowLayout(
        leftUsableMaxX: 668,
        rightUsableMinX: 828,
        rightUsableMaxX: 1_496,
        visibleMaxX: 1_496,
        screenMinX: 0,
        screenMaxX: 1_496
    )

    func testFromAuxiliaryAreasBuildsDeadZone() {
        let left = CGRect(x: 0, y: 939, width: 668, height: 28)
        let right = CGRect(x: 828, y: 939, width: 668, height: 28)
        let band = NotchBandGeometry.fromAuxiliaryAreas(
            left: left,
            right: right,
            screenMinX: 0,
            screenMaxX: 1496
        )
        XCTAssertNotNil(band)
        XCTAssertEqual(band?.leftUsableMaxX, 668)
        XCTAssertEqual(band?.rightUsableMinX, 828)
        XCTAssertEqual(band?.rightUsableMaxX, 1_496)
        XCTAssertTrue(band?.hasDeadZone == true)
    }

    func testFromAuxiliaryAreasNilWhenNoGap() {
        let left = CGRect(x: 0, y: 900, width: 800, height: 28)
        let right = CGRect(x: 800, y: 900, width: 800, height: 28)
        let band = NotchBandGeometry.fromAuxiliaryAreas(left: left, right: right)
        XCTAssertNil(band)
    }

    func testUnderNotchClassificationForMidGapItem() {
        XCTAssertTrue(
            liveLike.isUnderNotch(itemMinX: 700, itemMaxX: 724, itemMidX: 712)
        )
        XCTAssertEqual(
            liveLike.placement(itemMinX: 700, itemMaxX: 724, itemMidX: 712),
            .underNotch
        )
    }

    func testUsableBandsNotClassifiedAsUnderNotch() {
        XCTAssertFalse(
            liveLike.isUnderNotch(itemMinX: 100, itemMaxX: 124, itemMidX: 112)
        )
        XCTAssertEqual(
            liveLike.placement(itemMinX: 100, itemMaxX: 124, itemMidX: 112),
            .leftUsable
        )
        XCTAssertFalse(
            liveLike.isUnderNotch(itemMinX: 1200, itemMaxX: 1224, itemMidX: 1212)
        )
        XCTAssertEqual(
            liveLike.placement(itemMinX: 1200, itemMaxX: 1224, itemMidX: 1212),
            .rightUsable
        )
    }

    func testPartialOverlapWithNotchCountsAsUnderNotch() {
        XCTAssertTrue(
            liveLike.isUnderNotch(itemMinX: 650, itemMaxX: 690, itemMidX: 670)
        )
    }

    func testEstimatedCenteredProducesGap() {
        let est = NotchBandGeometry.estimatedCentered(screenMinX: 0, screenMaxX: 1000)
        XCTAssertNotNil(est)
        XCTAssertTrue(est!.hasDeadZone)
        XCTAssertTrue(est!.isUnderNotch(itemMinX: 490, itemMaxX: 510, itemMidX: 500))
    }

    // MARK: Overflow = cut-off status items

    func testOverflowWhenUnderCameraGap() {
        XCTAssertTrue(
            overflowLayout.isOverflow(itemMinX: 700, itemMaxX: 724, itemMidX: 712)
        )
    }

    func testOverflowWhenPastVisibleRightEdge() {
        XCTAssertTrue(
            overflowLayout.isOverflow(itemMinX: 1_500, itemMaxX: 1_524, itemMidX: 1_512)
        )
    }

    func testFullyVisibleRightStripNotOverflow() {
        // Fully inside right usable strip (aux right 828…1496).
        XCTAssertFalse(
            overflowLayout.isOverflow(itemMinX: 1_200, itemMaxX: 1_224, itemMidX: 1_212)
        )
    }

    func testAppMenuLeftBandNotOverflow() {
        XCTAssertFalse(
            overflowLayout.isOverflow(itemMinX: 100, itemMaxX: 124, itemMidX: 112)
        )
    }

    func testClassifierOverflowSection() {
        let bounds = MenuBarLaneBounds(
            toggleX: 500,
            primaryX: 400,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let section = RevealPanelClassifier.section(
            itemMinX: 700,
            itemMaxX: 724,
            itemMidX: 712,
            laneBounds: bounds,
            notch: liveLike,
            overflow: overflowLayout,
            notchSupportEnabled: true,
            isParked: false
        )
        XCTAssertEqual(section, .overflow)
    }

    func testClassifierOverflowWinsOverLeftOfPrimaryHidden() {
        // Under gap AND left of primary separator — Overflow, not Hidden.
        let bounds = MenuBarLaneBounds(
            toggleX: 1_300,
            primaryX: 1_260,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let section = RevealPanelClassifier.section(
            itemMinX: 700,
            itemMaxX: 724,
            itemMidX: 712,
            laneBounds: bounds,
            notch: liveLike,
            overflow: overflowLayout,
            notchSupportEnabled: true,
            isParked: false
        )
        XCTAssertEqual(section, .overflow)
    }

    func testFullyVisibleLeftOfPrimaryIsHidden() {
        // Hammerspoon-like: fully in right strip but left of hide separator.
        let bounds = MenuBarLaneBounds(
            toggleX: 1_300,
            primaryX: 1_260,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let section = RevealPanelClassifier.section(
            itemMinX: 852,
            itemMaxX: 890,
            itemMidX: 871,
            laneBounds: bounds,
            notch: liveLike,
            overflow: overflowLayout,
            notchSupportEnabled: true,
            isParked: false
        )
        XCTAssertEqual(section, .hidden)
    }

    func testClassifierHonorsOverflowSupportOff() {
        let bounds = MenuBarLaneBounds(
            toggleX: 500,
            primaryX: 400,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let section = RevealPanelClassifier.section(
            itemMinX: 700,
            itemMaxX: 724,
            itemMidX: 712,
            laneBounds: bounds,
            notch: liveLike,
            overflow: overflowLayout,
            notchSupportEnabled: false,
            isParked: false
        )
        XCTAssertNil(section)
    }

    func testClassifiedCandidatesIncludesOverflowOutsideHiddenLane() {
        let bounds = MenuBarLaneBounds(
            toggleX: 500,
            primaryX: 400,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let cutOff = MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(
                windowID: 42,
                identity: MenuBarItemIdentity(namespace: "com.example.app", title: "Foo")
            ),
            identity: MenuBarItemIdentity(namespace: "com.example.app", title: "Foo"),
            ownerPID: 99,
            ownerName: "Example",
            title: "Foo",
            displayName: "Example — Foo",
            frame: CGRect(x: 700, y: 0, width: 24, height: 24)
        )
        let visibleRight = MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(
                windowID: 43,
                identity: MenuBarItemIdentity(namespace: "com.example.other", title: "Bar")
            ),
            identity: MenuBarItemIdentity(namespace: "com.example.other", title: "Bar"),
            ownerPID: 100,
            ownerName: "Other",
            title: "Bar",
            displayName: "Other — Bar",
            frame: CGRect(x: 1200, y: 0, width: 24, height: 24)
        )
        let classified = RevealPanelModel.classifiedCandidates(
            [cutOff, visibleRight],
            laneBounds: bounds,
            excludingOwnerPID: 1,
            notch: liveLike,
            overflow: overflowLayout,
            notchSupportEnabled: true
        )
        XCTAssertEqual(classified.count, 1)
        XCTAssertEqual(classified.first?.section, .overflow)
        XCTAssertEqual(classified.first?.item.handle.windowID, 42)
    }

    func testNotchSupportDefaultsOn() {
        XCTAssertTrue(HiddenBarConfig.default.isNotchSupportEnabled)
        var decoded = HiddenBarConfig.default
        decoded.notchSupportEnabled = nil
        XCTAssertTrue(decoded.isNotchSupportEnabled)
        decoded.notchSupportEnabled = false
        XCTAssertFalse(decoded.isNotchSupportEnabled)
        decoded.notchSupportEnabled = nil
        let normalized = try! decoded.validated()
        XCTAssertEqual(normalized.notchSupportEnabled, true)
    }

    func testSectionSortOrderUserItemsFirst() {
        XCTAssertTrue(RevealPanelSection.hidden < RevealPanelSection.alwaysHidden)
        XCTAssertTrue(RevealPanelSection.alwaysHidden < RevealPanelSection.overflow)
    }

    func testJunkMenubarChromeRejected() {
        XCTAssertFalse(
            RevealPanelItemQuality.isUsablePanelItem(
                ownerName: "Menubar",
                namespace: "Menubar",
                displayName: "Menubar",
                frameWidth: 400,
                frameHeight: 24
            )
        )
        XCTAssertFalse(
            RevealPanelItemQuality.isUsablePanelItem(
                ownerName: "App",
                namespace: "com.nstranquist.nicos-hidden-menubar",
                displayName: "Hidden Bar",
                frameWidth: 24,
                frameHeight: 24
            )
        )
        XCTAssertTrue(
            RevealPanelItemQuality.isUsablePanelItem(
                ownerName: "Bluesnooze",
                namespace: "com.oliveroneill.Bluesnooze",
                displayName: "Bluesnooze",
                frameWidth: 24,
                frameHeight: 22
            )
        )
        // pid-0 overflow extras under the camera gap still count.
        XCTAssertTrue(
            RevealPanelItemQuality.isUsablePanelItem(
                ownerName: "",
                namespace: "unknown",
                displayName: "Unknown",
                frameWidth: 34,
                frameHeight: 22
            )
        )
    }

    func testLiveLikeUnderGapItemsAreOverflow() {
        // From operator dump 2026-07-23: extras at mid ~700–835, right strip starts 828.
        XCTAssertTrue(overflowLayout.isOverflow(itemMinX: 672, itemMaxX: 729, itemMidX: 700))
        XCTAssertTrue(overflowLayout.isOverflow(itemMinX: 818, itemMaxX: 852, itemMidX: 835))
        // Fully in right strip (Hammerspoon-like).
        XCTAssertFalse(overflowLayout.isOverflow(itemMinX: 852, itemMaxX: 890, itemMidX: 871))
    }

    func testRefineKeepsOverflowControlCenter() {
        let cc = MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(
                windowID: 7,
                identity: MenuBarItemIdentity(namespace: "com.apple.controlcenter", title: "WiFi")
            ),
            identity: MenuBarItemIdentity(namespace: "com.apple.controlcenter", title: "WiFi"),
            ownerPID: 1,
            ownerName: "Control Center",
            title: "WiFi",
            displayName: "WiFi",
            frame: CGRect(x: 700, y: 0, width: 24, height: 24)
        )
        let kept = RevealPanelPresentation.refine([cc], parkedWindowIDs: [], keepWindowIDs: [7])
        XCTAssertEqual(kept.count, 1)
        let dropped = RevealPanelPresentation.refine([cc], parkedWindowIDs: [], keepWindowIDs: [])
        XCTAssertTrue(dropped.isEmpty)
    }

    /// Shipped entry point: overflow under-gap vs hide-lane vs junk chrome vs left-band ghosts.
    func testClassifiedCandidatesRealWorldMixOverflowHiddenJunk() {
        // Operator layout: primary/toggle far right; right strip 828…1496; gap 668…828.
        let bounds = MenuBarLaneBounds(
            toggleX: 1_300,
            primaryX: 1_260,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        func item(
            id: CGWindowID,
            midX: Double,
            width: Double,
            owner: String,
            namespace: String,
            name: String,
            pid: Int32 = 99
        ) -> MenuBarDiscoveredItem {
            let identity = MenuBarItemIdentity(namespace: namespace, title: name)
            return MenuBarDiscoveredItem(
                handle: MenuBarItemHandle(windowID: id, identity: identity),
                identity: identity,
                ownerPID: pid,
                ownerName: owner,
                title: name,
                displayName: name,
                frame: CGRect(x: midX - width / 2, y: 0, width: width, height: 22)
            )
        }
        let underGap = item(id: 1, midX: 712, width: 24, owner: "", namespace: "unknown", name: "Unknown", pid: 0)
        let hideLane = item(id: 2, midX: 871, width: 24, owner: "Hammerspoon", namespace: "org.hammerspoon.Hammerspoon", name: "Hammerspoon")
        let chrome = item(id: 3, midX: 748, width: 400, owner: "Menubar", namespace: "Menubar", name: "Menubar", pid: 412)
        let leftGhost = item(id: 4, midX: 520, width: 33, owner: "", namespace: "unknown", name: "Unknown", pid: 0)
        // Right of toggle → everyday visible; must not appear in panel.
        let visibleRight = item(id: 5, midX: 1_350, width: 24, owner: "Other", namespace: "com.example.other", name: "Other")

        let classified = RevealPanelModel.classifiedCandidates(
            [underGap, hideLane, chrome, leftGhost, visibleRight],
            laneBounds: bounds,
            excludingOwnerPID: 1,
            notch: liveLike,
            overflow: overflowLayout,
            notchSupportEnabled: true
        )
        let byID = Dictionary(uniqueKeysWithValues: classified.map { ($0.item.handle.windowID, $0.section) })
        XCTAssertEqual(byID[1], .overflow, "under-gap cut-off → Overflow")
        XCTAssertEqual(byID[2], .hidden, "fully-in-right-strip left of separator → Hidden")
        XCTAssertNil(byID[3], "full-width Menubar chrome rejected")
        XCTAssertNil(byID[4], "left-band ghost rejected")
        XCTAssertNil(byID[5], "right of toggle / fully visible everyday item not listed")
        XCTAssertEqual(classified.count, 2)
        XCTAssertTrue(RevealPanelSection.hidden < RevealPanelSection.overflow)
    }
}
