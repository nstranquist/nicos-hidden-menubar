import XCTest
@testable import NicosHiddenMenuBar

final class HiddenBarImporterTests: XCTestCase {
    func testImporterMapsSupportedFieldsAndTracksIgnoredKeys() {
        let result = HiddenBarImporter.importConfig(from: [
            "autoHideEnabled": .bool(true),
            "autoHideSeconds": .int(7),
            "isShowPreferences": .bool(true),
            "alwaysHiddenSectionEnabled": .bool(true),
            "useFullStatusBarOnExpandEnabled": .bool(true),
            "shortcutKeyCode": .int(35),
            "shortcutCarbonFlags": .int(1572864),
            "shortcutDisplay": .string("cmd+shift+p"),
            "ratingHasShown": .bool(true),
            "mysteryKey": .string("ignored"),
        ])

        XCTAssertTrue(result.config.autoCollapse.enabled)
        XCTAssertEqual(result.config.autoCollapse.seconds, 7)
        XCTAssertTrue(result.config.showPreferencesOnLaunch)
        XCTAssertTrue(result.config.lanes.alwaysHiddenEnabled)
        XCTAssertTrue(result.config.useRegularActivationOnExpand)
        XCTAssertEqual(result.config.globalShortcut.keyCode, 35)
        XCTAssertEqual(result.config.globalShortcut.carbonFlags, 1572864)
        XCTAssertEqual(result.config.globalShortcut.display, "cmd+shift+p")
        XCTAssertTrue(result.note.importedKeys.contains("autoHideEnabled"))
        XCTAssertTrue(result.note.importedKeys.contains("alwaysHiddenSectionEnabled"))
        XCTAssertEqual(result.note.ignoredKeys, ["mysteryKey"])
    }

    func testImporterReturnsNilWhenDomainIsMissing() {
        let importer = HiddenBarImporter(loadDefaults: { _ in [:] })
        XCTAssertNil(importer.importIfAvailable())
    }

    func testImporterFallsBackWhenFoundationReturnsEmpty() {
        let importer = HiddenBarImporter(
            loadDefaults: { _ in [:] },
            loadFallback: { _ in
                [
                    "autoHideEnabled": .bool(true),
                    "autoHideSeconds": .int(3),
                    "alwaysHiddenSectionEnabled": .bool(true),
                ]
            }
        )
        let result = importer.importIfAvailable()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.config.autoCollapse.seconds, 3)
        XCTAssertTrue(result?.config.lanes.alwaysHiddenEnabled ?? false)
    }

    func testImporterReturnsNilWhenBothPathsEmpty() {
        let importer = HiddenBarImporter(
            loadDefaults: { _ in [:] },
            loadFallback: { _ in [:] }
        )
        XCTAssertNil(importer.importIfAvailable())
    }

    func testImporterPrefersFoundationOverFallback() {
        let importer = HiddenBarImporter(
            loadDefaults: { _ in ["autoHideSeconds": .int(9)] },
            loadFallback: { _ in ["autoHideSeconds": .int(999)] }
        )
        let result = importer.importIfAvailable()
        XCTAssertEqual(result?.config.autoCollapse.seconds, 9)
    }

    func testDefaultsExportFallbackParsesRealDomain() throws {
        // com.apple.dock is always present on macOS; exercise the real subprocess path
        // end-to-end to catch launch failures, empty-output paths, or plist-decode regressions.
        let values = HiddenBarImporter.readDomainViaDefaultsExport(domain: "com.apple.dock")
        XCTAssertFalse(values.isEmpty, "com.apple.dock should expose at least one key via /usr/bin/defaults export")
    }
}
