import Foundation
import XCTest
@testable import NicosHiddenMenuBar

final class ConfigRoundTripTests: XCTestCase {
    @MainActor
    func testDefaultConfigIsWrittenAndRoundTrips() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let paths = PreferencesStore.Paths(
            configURL: tempDir.appendingPathComponent("config.json"),
            diagnosticsURL: tempDir.appendingPathComponent("diagnostics.json"),
            bridgeURL: tempDir.appendingPathComponent("hammerspoon-bridge.json")
        )

        let store = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configURL.path))
        XCTAssertEqual(store.config.activeProfile, "default")
        XCTAssertFalse(store.config.isOnboardingCompleted)
        XCTAssertFalse(store.config.globalShortcut.enabled)
        XCTAssertEqual(store.config.globalShortcut, .deliberate(enabled: false))

        XCTAssertTrue(
            store.updateConfig { current in
                current.activeProfile = "focus"
                current.autoCollapse.seconds = 12
                current.firstPartyVisible.preferredVisibleTitles = ["TO", "PW"]
                current.onboardingCompleted = true
            })

        let reloadedStore = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )

        XCTAssertEqual(reloadedStore.config.activeProfile, "focus")
        XCTAssertEqual(reloadedStore.config.autoCollapse.seconds, 12)
        XCTAssertEqual(reloadedStore.config.firstPartyVisible.preferredVisibleTitles, ["TO", "PW"])
        XCTAssertTrue(reloadedStore.config.isOnboardingCompleted)
    }

    func testConfigValidationFailsClosed() {
        var invalid = HiddenBarConfig.default
        invalid.activeProfile = "missing"
        XCTAssertThrowsError(try invalid.validated())
    }

    func testValidationMigratesLegacyHSOutOfPersistedVisibleTitles() throws {
        var config = HiddenBarConfig.default
        config.firstPartyVisible.preferredVisibleTitles = ["HS", "TO", "PW", "TO"]

        let validated = try config.validated()

        XCTAssertEqual(validated.firstPartyVisible.preferredVisibleTitles, ["TO", "PW"])
    }

    func testLegacyCocoaShortcutMaskMigratesDisabledToDeliberateCarbonPreset() throws {
        var config = HiddenBarConfig.default
        config.globalShortcut = GlobalShortcutSettings(
            enabled: true,
            keyCode: 42,
            carbonFlags: 1_572_864,
            display: #"cmd+shift+\\"#
        )

        let validated = try config.validated()

        XCTAssertEqual(validated.globalShortcut, .deliberate(enabled: false))
        XCTAssertLessThanOrEqual(
            validated.globalShortcut.carbonFlags,
            GlobalShortcutSettings.maximumCarbonFlags
        )
    }

    @MainActor
    func testCustomizationSurfacePersistsLanesRevealModeAutoCollapseShortcutProfiles() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let paths = PreferencesStore.Paths(
            configURL: tempDir.appendingPathComponent("config.json"),
            diagnosticsURL: tempDir.appendingPathComponent("diagnostics.json"),
            bridgeURL: tempDir.appendingPathComponent("hammerspoon-bridge.json")
        )

        let store = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )

        XCTAssertTrue(
            store.updateConfig { current in
                current.lanes.alwaysHiddenEnabled = true
                current.lanes.primarySeparatorVisibleWhenExpanded = false
                current.revealMode = .belowMenuBar
                current.autoCollapse.enabled = true
                current.autoCollapse.seconds = 7
                current.globalShortcut.enabled = true
                current.globalShortcut.display = "cmd+shift+h"
                current.activeProfile = "focus"
                current.enableExperimentalItemMovement = false
                current.onboardingCompleted = true
            })

        let reloaded = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )

        XCTAssertTrue(reloaded.config.lanes.alwaysHiddenEnabled)
        XCTAssertFalse(reloaded.config.lanes.primarySeparatorVisibleWhenExpanded)
        XCTAssertEqual(reloaded.config.configuredRevealMode, .belowMenuBar)
        XCTAssertEqual(reloaded.config.resolvedRevealMode(hasNotch: false), .belowMenuBar)
        XCTAssertTrue(reloaded.config.autoCollapse.enabled)
        XCTAssertEqual(reloaded.config.autoCollapse.seconds, 7)
        XCTAssertTrue(reloaded.config.globalShortcut.enabled)
        XCTAssertEqual(reloaded.config.globalShortcut.display, "cmd+shift+h")
        XCTAssertEqual(reloaded.config.activeProfile, "focus")
        XCTAssertFalse(reloaded.config.isExperimentalItemMovementEnabled)
        XCTAssertFalse(reloaded.config.isRescueOverflowIntoHiddenLaneEnabled)
        XCTAssertTrue(reloaded.config.isOnboardingCompleted)
        // Required profiles remain present after customization.
        for name in HiddenBarConfig.requiredProfiles {
            XCTAssertNotNil(reloaded.config.profiles[name])
        }
    }

    @MainActor
    func testRescueOverflowDefaultsOffAndRoundTripsWhenOptedIn() throws {
        XCTAssertFalse(HiddenBarConfig.default.isRescueOverflowIntoHiddenLaneEnabled)

        var decoded = HiddenBarConfig.default
        decoded.rescueOverflowIntoHiddenLane = nil
        XCTAssertFalse(decoded.isRescueOverflowIntoHiddenLaneEnabled)
        let normalized = try decoded.validated()
        XCTAssertFalse(normalized.isRescueOverflowIntoHiddenLaneEnabled)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let paths = PreferencesStore.Paths(
            configURL: tempDir.appendingPathComponent("config.json"),
            diagnosticsURL: tempDir.appendingPathComponent("diagnostics.json"),
            bridgeURL: tempDir.appendingPathComponent("hammerspoon-bridge.json")
        )
        let store = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )
        XCTAssertFalse(store.config.isRescueOverflowIntoHiddenLaneEnabled)
        XCTAssertTrue(
            store.updateConfig { current in
                current.rescueOverflowIntoHiddenLane = true
                current.enableExperimentalItemMovement = true
            })
        let reloaded = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )
        XCTAssertTrue(reloaded.config.isRescueOverflowIntoHiddenLaneEnabled)
        XCTAssertTrue(reloaded.config.isExperimentalItemMovementEnabled)
    }

    func testCollapseFailureRawValuesAreStableDiagnosticsKeys() {
        XCTAssertEqual(MenuBarCollapseFailure.markersOffScreen.rawValue, "markers_off_screen")
        XCTAssertEqual(MenuBarCollapseFailure.nothingToHide.rawValue, "nothing_to_hide")
        XCTAssertEqual(MenuBarCollapseFailure.invalidMarkerOrder.rawValue, "invalid_marker_order")
        XCTAssertEqual(MenuBarCollapseFailure.unreadableGeometry.rawValue, "geometry_unreadable")
    }
}
