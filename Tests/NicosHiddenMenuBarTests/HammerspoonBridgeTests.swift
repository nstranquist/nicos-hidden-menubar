import Foundation
import XCTest
@testable import NicosHiddenMenuBar

final class HammerspoonBridgeTests: XCTestCase {
    @MainActor
    func testMissingBridgeFileFailsClosed() {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let status = HammerspoonBridge.loadStatus(from: tempURL, now: Date(), config: .default)
        XCTAssertEqual(status, .missing(path: tempURL))
    }

    @MainActor
    func testInvalidBridgeJSONFailsClosed() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let bridgeURL = tempDir.appendingPathComponent("bridge.json")
        try Data("{not-json}".utf8).write(to: bridgeURL)

        let status = HammerspoonBridge.loadStatus(from: bridgeURL, now: Date(), config: .default)
        XCTAssertEqual(status.code, .invalid)
    }

    @MainActor
    func testBridgeAgreementKeepsConfigAsAuthority() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let bridgeURL = tempDir.appendingPathComponent("bridge.json")
        let payload = """
        {
          "schemaVersion": 1,
          "generatedAt": "\(hiddenBarTimestampString(Date()))",
          "source": "nicos-tools/hammerspoon",
          "items": []
        }
        """
        try Data(payload.utf8).write(to: bridgeURL)

        let bridge = HammerspoonBridge(bridgeURL: bridgeURL)
        bridge.refresh(using: .default)

        XCTAssertEqual(bridge.status.code, .valid)
        XCTAssertEqual(bridge.resolvedVisibleTitles, [])
        if case .valid(_, _, _, let disagreesWithConfig) = bridge.status {
            XCTAssertFalse(disagreesWithConfig)
        } else {
            XCTFail("Expected valid bridge status")
        }
    }

    @MainActor
    func testBridgeDisagreementSurfacesSuggestionButConfigWins() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let bridgeURL = tempDir.appendingPathComponent("bridge.json")
        let payload = """
        {
          "schemaVersion": 1,
          "generatedAt": "\(hiddenBarTimestampString(Date()))",
          "source": "nicos-tools/hammerspoon",
          "items": [
            { "title": "ALT", "kind": "menu", "module": "task_orbit", "preferredLane": "visible" }
          ]
        }
        """
        try Data(payload.utf8).write(to: bridgeURL)

        let bridge = HammerspoonBridge(bridgeURL: bridgeURL)
        bridge.refresh(using: .default)

        XCTAssertEqual(bridge.status.code, .valid)
        XCTAssertEqual(bridge.resolvedVisibleTitles, [])
        if case .valid(_, _, let suggestion, let disagreesWithConfig) = bridge.status {
            XCTAssertEqual(suggestion.preferredVisibleTitles, ["ALT"])
            XCTAssertTrue(disagreesWithConfig)
        } else {
            XCTFail("Expected valid bridge status")
        }
    }
}
