import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class ParityModelTests: XCTestCase {
    func testMenuBarItemInfoKeyAndImmovability() {
        let cc = MenuBarItemInfo(namespace: "com.apple.controlcenter", title: "WiFi")
        XCTAssertEqual(cc.key, "com.apple.controlcenter:WiFi")
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
        dict.removeValue(forKey: "iceBarEnabled")
        dict.removeValue(forKey: "revealMode")
        dict.removeValue(forKey: "enableExperimentalItemMovement")
        dict.removeValue(forKey: "revealOnHover")
        data = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(HiddenBarConfig.self, from: data)
        XCTAssertFalse(decoded.isIceBarEnabled)
        XCTAssertFalse(decoded.isExperimentalItemMovementEnabled)
        XCTAssertFalse(decoded.isRevealOnHoverEnabled)
        XCTAssertEqual(decoded.configuredRevealMode, .automatic)
    }

    func testIceBarHiddenCandidatesFilterLeftOfToggleAndExcludeImmovable() {
        func win(_ id: CGWindowID, minX: Double, width: Double, ns: String) -> MenuBarWindowInfo {
            MenuBarWindowInfo(
                windowID: id,
                frame: CGRect(x: minX, y: 0, width: width, height: 24),
                ownerPID: 1,
                ownerName: ns,
                title: "",
                isOnScreen: true
            )
        }
        let items = [
            win(1, minX: 100, width: 24, ns: "com.example.a"),           // left of toggle → hidden
            win(2, minX: 200, width: 24, ns: "com.apple.controlcenter"), // immovable → excluded
            win(3, minX: 900, width: 24, ns: "com.example.b"),           // right of toggle → not hidden
        ]
        let hidden = IceBarModel.hiddenCandidates(items, leftOfX: 700)
        XCTAssertEqual(hidden.map(\.windowID), [1])
    }

    func testIceBarHiddenCandidatesWithoutAnchorReturnsAllMovable() {
        let item = MenuBarWindowInfo(
            windowID: 5, frame: CGRect(x: 10, y: 0, width: 20, height: 24),
            ownerPID: 1, ownerName: "com.example.x", title: "", isOnScreen: true
        )
        XCTAssertEqual(IceBarModel.hiddenCandidates([item], leftOfX: nil).count, 1)
    }

    func testConfigRoundTripsParityFlags() throws {
        var config = HiddenBarConfig.default
        config.iceBarEnabled = true
        config.enableExperimentalItemMovement = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(HiddenBarConfig.self, from: data)
        XCTAssertTrue(decoded.isIceBarEnabled)
        XCTAssertTrue(decoded.isExperimentalItemMovementEnabled)
    }

    func testRevealModeMigratesLegacyFlagAndResolvesNotches() throws {
        var config = HiddenBarConfig.default
        config.iceBarEnabled = true
        XCTAssertEqual(config.configuredRevealMode, .belowMenuBar)

        config.iceBarEnabled = nil
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: false), .inline)
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: true), .belowMenuBar)

        config.revealMode = .inline
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: true), .inline)

        config.revealMode = .belowMenuBar
        XCTAssertEqual(config.resolvedRevealMode(hasNotch: false), .belowMenuBar)
    }

    func testIceBarLayoutClampsToActiveScreenAndWrapsItems() {
        let small = IceBarLayout.calculate(
            itemCount: 20,
            visibleFrame: CGRect(x: 1_500, y: 0, width: 500, height: 800)
        )
        XCTAssertLessThanOrEqual(small.width, 488)
        XCTAssertGreaterThan(small.height, 54)
        XCTAssertGreaterThan(small.columnCount, 1)

        let compact = IceBarLayout.calculate(
            itemCount: 3,
            visibleFrame: CGRect(x: 0, y: 0, width: 1_496, height: 900)
        )
        XCTAssertEqual(compact.columnCount, 3)
        XCTAssertEqual(compact.height, 54)
    }
}
