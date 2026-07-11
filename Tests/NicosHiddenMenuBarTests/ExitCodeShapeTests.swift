import XCTest
@testable import NicosHiddenMenuBar

final class ExitCodeShapeTests: XCTestCase {
    func testMarkerOrderInvalidJSONShapeMatchesSpec() throws {
        let envelope = CLIErrorEnvelope.markerOrderInvalid()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains(#""ok":false"#))
        XCTAssertTrue(json.contains(#""error":"marker_order_invalid""#))
        XCTAssertTrue(json.contains(#""message":"The separator markers are not in a valid order for collapse.""#))
        XCTAssertTrue(json.contains(#""recommendedAction":"Open diagnostics and cmd-drag the markers back into the expected order.""#))
    }

    func testExitCodesMatchFrozenContract() {
        XCTAssertEqual(MenubarSectionsExit.success.rawValue, 0)
        XCTAssertEqual(MenubarSectionsExit.genericFailure.rawValue, 1)
        XCTAssertEqual(MenubarSectionsExit.appNotInstalled.rawValue, 2)
        XCTAssertEqual(MenubarSectionsExit.appNotRunning.rawValue, 3)
        XCTAssertEqual(MenubarSectionsExit.markerOrderInvalid.rawValue, 4)
        XCTAssertEqual(MenubarSectionsExit.bridgeInvalid.rawValue, 5)
        XCTAssertEqual(MenubarSectionsExit.configInvalid.rawValue, 6)
        XCTAssertEqual(MenubarSectionsExit.profileNotFound.rawValue, 7)
    }
}
