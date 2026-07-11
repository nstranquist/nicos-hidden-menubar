import XCTest
@testable import NicosHiddenMenuBar

final class FirstPartyVisibleTitlesTests: XCTestCase {
    func testCandidateTitlesPreferBridgeThenConfigThenDefaults() {
        XCTAssertEqual(
            FirstPartyVisibleTitles.candidateTitles(
                configTitles: ["PW", "TO"],
                bridgeTitles: ["BR", "TO"]
            ),
            ["BR", "TO", "PW"]
        )
    }

    func testToggledAddsAndRemovesTitlesWithoutDuplicates() {
        XCTAssertEqual(
            FirstPartyVisibleTitles.toggled(["TO", "BR"], title: "PW", enabled: true),
            ["TO", "BR", "PW"]
        )
        XCTAssertEqual(
            FirstPartyVisibleTitles.toggled(["TO", "BR", "PW"], title: "BR", enabled: false),
            ["TO", "PW"]
        )
        XCTAssertEqual(
            FirstPartyVisibleTitles.toggled(["TO", "BR"], title: "TO", enabled: true),
            ["TO", "BR"]
        )
    }

    @MainActor
    func testPreferencesStorePersistsConfiguredFirstPartyTitles() throws {
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

        XCTAssertTrue(store.setFirstPartyVisibleTitle("TO", enabled: false))
        XCTAssertTrue(store.setFirstPartyVisibleTitle("PW", enabled: true))

        let reloadedStore = PreferencesStore(
            paths: paths,
            fileManager: .default,
            importer: HiddenBarImporter(loadDefaults: { _ in [:] })
        )

        XCTAssertEqual(reloadedStore.config.firstPartyVisible.preferredVisibleTitles, ["PW"])
    }
}
