import CoreGraphics
import Foundation
import XCTest
@testable import NicosHiddenMenuBar

@MainActor
final class MenuBarServiceBoundaryTests: XCTestCase {
    func testARC001BActivationDelegatesToPlacementOwner() async {
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true }
        )
        let request = activationRequest()

        let outcome = await activation.activate(request)

        XCTAssertEqual(outcome, .revealedForActivation)
        XCTAssertEqual(
            placement.requests,
            [
                MenuBarPlacementRequest(
                    item: request.item,
                    targetDisplay: request.targetDisplay,
                    desiredLane: .visible,
                    anchor: .rightOf(request.visibleAnchor)
                ),
            ]
        )
    }

    func testARC001BActivationFailsClosedWhenMovementIsDisabled() async {
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { false }
        )

        let outcome = await activation.activate(activationRequest())

        XCTAssertEqual(outcome, .unsupported(reason: "experimental_item_movement_disabled"))
        XCTAssertTrue(placement.requests.isEmpty)
    }

    func testARC001BActivationReturnsTypedPlacementFailure() async {
        let placement = RecordingPlacementService(error: TestPlacementError.failed)
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true }
        )

        let outcome = await activation.activate(activationRequest())

        XCTAssertEqual(outcome, .failed(reason: "failed"))
        XCTAssertEqual(placement.requests.count, 1)
    }

    func testARC001BRevealModelUsesInjectedDiscoveryAndCaptureOwners() async {
        let display = MenuBarDisplayHandle(rawValue: 3)
        let hidden = discoveredItem(windowID: 7, ownerPID: 1, minX: 100)
        let ownControl = discoveredItem(windowID: 8, ownerPID: 42, minX: 200)
        let visible = discoveredItem(windowID: 9, ownerPID: 2, minX: 900)
        let discovery = RecordingDiscoveryService(items: [hidden, ownControl, visible])
        let capture = RecordingCaptureService()
        let model = IceBarModel(discovery: discovery, capture: capture)

        await model.reload(on: display, leftOfX: 700, excludingOwnerPID: 42)

        XCTAssertEqual(discovery.requestedDisplays, [display])
        XCTAssertEqual(capture.requests.map { $0.items.map(\.handle.windowID) }, [[7]])
        XCTAssertEqual(capture.requests.map(\.display), [display])
        XCTAssertEqual(model.items.map(\.item.handle.windowID), [7])
        XCTAssertTrue(model.usesImages)
    }

    private func activationRequest() -> MenuBarActivationRequest {
        MenuBarActivationRequest(
            item: MenuBarItemHandle(windowID: 7),
            targetDisplay: MenuBarDisplayHandle(rawValue: 3),
            visibleAnchor: MenuBarItemHandle(windowID: 11)
        )
    }

    private func discoveredItem(
        windowID: UInt32,
        ownerPID: Int32,
        minX: Double
    ) -> MenuBarDiscoveredItem {
        MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(windowID: windowID),
            ownerPID: ownerPID,
            ownerName: "Owner \(ownerPID)",
            title: "",
            displayName: "Item \(windowID)",
            frame: CGRect(x: minX, y: 0, width: 24, height: 24)
        )
    }
}

@MainActor
private final class RecordingPlacementService: MenuBarItemPlacing {
    private(set) var requests: [MenuBarPlacementRequest] = []
    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func place(_ request: MenuBarPlacementRequest) async throws {
        requests.append(request)
        if let error {
            throw error
        }
    }
}

private enum TestPlacementError: Error {
    case failed
}

@MainActor
private final class RecordingDiscoveryService: MenuBarItemDiscovering {
    private let items: [MenuBarDiscoveredItem]
    private(set) var requestedDisplays: [MenuBarDisplayHandle] = []

    init(items: [MenuBarDiscoveredItem]) {
        self.items = items
    }

    func snapshot(
        on display: MenuBarDisplayHandle,
        toggleMinX: Double?
    ) -> MenuBarDiscoverySnapshot? {
        nil
    }

    func discoverItems(on display: MenuBarDisplayHandle) -> [MenuBarDiscoveredItem] {
        requestedDisplays.append(display)
        return items
    }
}

@MainActor
private final class RecordingCaptureService: MenuBarItemCapturing {
    struct Request: Equatable {
        var items: [MenuBarDiscoveredItem]
        var display: MenuBarDisplayHandle
    }

    private(set) var requests: [Request] = []

    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem] {
        requests.append(Request(items: items, display: display))
        return items.map { item in
            MenuBarCapturedItem(item: item, pngData: Data([0x01]), scale: 2)
        }
    }
}
