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

        XCTAssertTrue(store.updateConfig { current in
            current.activeProfile = "focus"
            current.autoCollapse.seconds = 12
            current.firstPartyVisible.preferredVisibleTitles = ["TO", "PW"]
        })

        let reloadedStore = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )

        XCTAssertEqual(reloadedStore.config.activeProfile, "focus")
        XCTAssertEqual(reloadedStore.config.autoCollapse.seconds, 12)
        XCTAssertEqual(reloadedStore.config.firstPartyVisible.preferredVisibleTitles, ["TO", "PW"])
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
}
