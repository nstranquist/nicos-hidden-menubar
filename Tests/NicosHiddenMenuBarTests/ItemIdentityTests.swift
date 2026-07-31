import XCTest
@testable import NicosHiddenMenuBar

final class ItemIdentityTests: XCTestCase {
    func testITEM001AControlCenterFixturesResolveDistinctModules() {
        let raw = ControlCenterModules.fixtureTitles.map {
            (namespace: ControlCenterModules.controlCenterNamespace, title: $0.title)
        }
        let identities = MenuBarItemIdentity.resolveScan(raw)

        XCTAssertEqual(identities.count, ControlCenterModules.fixtureTitles.count)
        let moduleIDs = identities.compactMap(\.moduleID)
        XCTAssertEqual(Set(moduleIDs).count, moduleIDs.count, "modules must be unique")

        for (identity, fixture) in zip(identities, ControlCenterModules.fixtureTitles) {
            XCTAssertEqual(identity.moduleID, fixture.moduleID, fixture.title)
            XCTAssertEqual(identity.ordinal, 0)
            XCTAssertTrue(identity.key.hasPrefix("v1:"))
            XCTAssertEqual(identity.legacyKey, "\(ControlCenterModules.controlCenterNamespace):\(fixture.title)")
        }
    }

    func testITEM001AImageOnlyPeersGetDistinctOrdinals() {
        let raw = Array(repeating: (namespace: ControlCenterModules.controlCenterNamespace, title: ""), count: 3)
        let identities = MenuBarItemIdentity.resolveScan(raw)

        XCTAssertEqual(identities.map(\.ordinal), [0, 1, 2])
        XCTAssertEqual(Set(identities.map(\.key)).count, 3)
        XCTAssertEqual(identities.map(\.moduleID), ["module", "module", "module"])
    }

    func testITEM001BLegacyKeyMigrationPreservesNamespaceAndTitle() {
        let legacy = "com.example.app:Status"
        let identity = MenuBarItemIdentity.migrateLegacyKey(legacy)

        XCTAssertEqual(identity.namespace, "com.example.app")
        XCTAssertEqual(identity.title, "Status")
        XCTAssertEqual(identity.legacyKey, legacy)
        XCTAssertTrue(identity.key.hasPrefix("v1:"))
    }

    func testITEM001BPolicyKeyMigrationIsIdempotentForVersionedKeys() {
        let versioned = MenuBarItemIdentity(namespace: "a", title: "b").key
        let migrated = FirstPartyVisibleTitles.migratePolicyKeys([versioned, "com.x:y", "  Bare Title  "])

        XCTAssertEqual(migrated[0], versioned)
        XCTAssertTrue(migrated[1].hasPrefix("v1:"))
        XCTAssertEqual(migrated[2], "Bare Title")
    }

    func testMenuBarItemInfoKeyUsesVersionedIdentity() {
        let cc = MenuBarItemInfo(namespace: "com.apple.controlcenter", title: "WiFi")
        XCTAssertTrue(cc.key.contains("com.apple.controlcenter"))
        XCTAssertTrue(cc.key.hasPrefix("v1:"))
        XCTAssertEqual(cc.legacyKey, "com.apple.controlcenter:WiFi")
        XCTAssertTrue(cc.isLikelyImmovable)

        let regular = MenuBarItemInfo(namespace: "com.example.app", title: "")
        XCTAssertFalse(regular.isLikelyImmovable)
    }

    func testControlCenterDisplayNamesAndSymbols() {
        XCTAssertEqual(
            ControlCenterModules.displayName(forModuleID: "wifi", title: "", ordinal: 0),
            "Wi‑Fi"
        )
        XCTAssertEqual(
            ControlCenterModules.symbolName(forModuleID: "focus", title: ""),
            "moon.fill"
        )
        XCTAssertEqual(
            ControlCenterModules.displayName(forModuleID: "module", title: "", ordinal: 2),
            "Control Center 3"
        )
    }

    func testOffScreenWindowDescriptionRetainsOwnerAndTitle() {
        let expectedFrame = CGRect(x: 1_540, y: 0, width: 28, height: 24)
        let dictionary: [String: Any] = [
            kCGWindowOwnerPID as String: pid_t(42_424),
            kCGWindowOwnerName as String: "Example Utility",
            kCGWindowName as String: "Sync Status",
            kCGWindowIsOnscreen as String: false,
            kCGWindowBounds as String: CGRectCreateDictionaryRepresentation(expectedFrame),
        ]

        let info = MenuBarWindowInfo.decode(
            windowID: 99,
            dictionary: dictionary,
            bridgedFrame: nil
        )

        XCTAssertEqual(info.ownerPID, 42_424)
        XCTAssertEqual(info.ownerName, "Example Utility")
        XCTAssertEqual(info.title, "Sync Status")
        XCTAssertEqual(info.frame, expectedFrame)
        XCTAssertFalse(info.isOnScreen)
        XCTAssertEqual(info.displayName, "Sync Status")
    }

    func testWindowServerMenuBarBackdropIsNotAnItem() {
        let dictionary: [String: Any] = [
            kCGWindowOwnerPID as String: pid_t(428),
            kCGWindowOwnerName as String: "Window Server",
            kCGWindowName as String: "Menubar",
            kCGWindowIsOnscreen as String: true,
            kCGWindowBounds as String: CGRectCreateDictionaryRepresentation(
                CGRect(x: 0, y: 0, width: 1_496, height: 33)
            ),
        ]

        let info = MenuBarWindowInfo.decode(
            windowID: 36,
            dictionary: dictionary,
            bridgedFrame: nil
        )

        XCTAssertTrue(info.isMenuBarBackdrop)
    }
}
