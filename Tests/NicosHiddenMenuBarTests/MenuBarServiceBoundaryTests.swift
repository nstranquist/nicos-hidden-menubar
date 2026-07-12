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
        let placement = RecordingPlacementService(error: MenuBarPlacementError.targetUnavailable)
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true }
        )

        let outcome = await activation.activate(activationRequest())

        XCTAssertEqual(outcome, .failed(reason: "targetUnavailable"))
        XCTAssertEqual(placement.requests.count, 1)
    }

    func testARC001BActivationMapsTypedImmovableFailure() async {
        let placement = RecordingPlacementService(error: MenuBarPlacementError.itemNotMovable)
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true }
        )

        let outcome = await activation.activate(activationRequest())

        XCTAssertEqual(outcome, .unsupported(reason: "item_not_movable"))
    }

    func testARC001BLiveCompositionUsesExpectedOwnersAndSharedPlacement() {
        let services = MenuBarServices.live(preferencesStore: .shared)

        let report = services.compositionReport()

        XCTAssertTrue(report.ok, report.detail)
        XCTAssertEqual(report.ownerTypes.count, 5)
        XCTAssertTrue(report.usesExpectedLiveOwners)
        XCTAssertTrue(report.activationUsesRegisteredPlacement)
    }

    func testARC001BLivePlacementMapsVisibleRequestToMover() async throws {
        let display = MenuBarDisplayHandle(rawValue: 3)
        var observed: (windowID: UInt32, anchorID: UInt32, enabled: Bool)?
        let placement = LiveMenuBarPlacementService(
            isMovementEnabled: { true },
            displayExists: { $0 == display },
            move: { windowID, destination, enabled in
                guard case .rightOf(let anchorID) = destination else {
                    return XCTFail("expected right-of placement")
                }
                observed = (windowID, anchorID, enabled)
            }
        )

        try await placement.place(placementRequest(display: display))

        XCTAssertEqual(observed?.windowID, 7)
        XCTAssertEqual(observed?.anchorID, 11)
        XCTAssertEqual(observed?.enabled, true)
    }

    func testARC001BLivePlacementRejectsUnsupportedLaneBeforeMover() async {
        var moverCalled = false
        let placement = LiveMenuBarPlacementService(
            isMovementEnabled: { true },
            displayExists: { _ in true },
            move: { _, _, _ in moverCalled = true }
        )
        var request = placementRequest(display: MenuBarDisplayHandle(rawValue: 3))
        request.desiredLane = .hidden

        do {
            try await placement.place(request)
            XCTFail("expected unsupported lane")
        } catch let error as MenuBarPlacementError {
            XCTAssertEqual(error, .unsupportedLane(.hidden))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertFalse(moverCalled)
    }

    func testARC001BLivePlacementMapsMoverFailure() async {
        let placement = LiveMenuBarPlacementService(
            isMovementEnabled: { true },
            displayExists: { _ in true },
            move: { _, _, _ in throw MenuBarItemMover.MoveError.notMovable }
        )

        do {
            try await placement.place(placementRequest(display: MenuBarDisplayHandle(rawValue: 3)))
            XCTFail("expected typed placement failure")
        } catch let error as MenuBarPlacementError {
            XCTAssertEqual(error, .itemNotMovable)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testARC001BRevealModelUsesInjectedDiscoveryAndCaptureOwners() async {
        let display = MenuBarDisplayHandle(rawValue: 3)
        let hidden = discoveredItem(windowID: 7, ownerPID: 1, minX: 100)
        let ownControl = discoveredItem(windowID: 8, ownerPID: 42, minX: 200)
        let visible = discoveredItem(windowID: 9, ownerPID: 2, minX: 900)
        let discovery = RecordingDiscoveryService(items: [hidden, ownControl, visible])
        let capture = RecordingCaptureService(image: makeTestImage())
        let model = IceBarModel(discovery: discovery, capture: capture)

        await model.reload(on: display, leftOfX: 700, excludingOwnerPID: 42)

        XCTAssertEqual(discovery.requestedDisplays, [display])
        XCTAssertEqual(capture.requests.map { $0.items.map(\.handle.windowID) }, [[7]])
        XCTAssertEqual(capture.requests.map(\.display), [display])
        XCTAssertEqual(model.items.map(\.item.handle.windowID), [7])
        XCTAssertTrue(model.usesImages)
    }

    func testARC001BDiscoveryBuildsOneConsistentSnapshot() {
        let details = [
            windowInfo(windowID: 9, ownerPID: 2, minX: 900),
            windowInfo(windowID: 7, ownerPID: 1, minX: 100),
        ]

        let snapshot = LiveMenuBarDiscoveryService.makeSnapshot(
            from: details,
            toggleMinX: 700,
            visibleMaxX: 1_440,
            hasNotch: true
        )

        XCTAssertEqual(snapshot.items.map(\.handle.windowID), [7, 9])
        XCTAssertEqual(snapshot.items.map(\.ownerPID), [1, 2])
        XCTAssertEqual(snapshot.hideableItemCount, 1)
        XCTAssertEqual(snapshot.leftmostMinX, 100)
        XCTAssertTrue(snapshot.hasNotch)
    }

    func testARC001BCaptureMergeRetainsImageWithoutSerialization() throws {
        let item = discoveredItem(windowID: 7, ownerPID: 1, minX: 100)
        let image = makeTestImage()
        let captured = MenuBarItemImageCapture.CapturedItem(
            info: MenuBarItemInfo(namespace: "example", title: ""),
            displayName: item.displayName,
            windowID: item.handle.windowID,
            frame: item.frame,
            image: image
        )

        let merged = LiveMenuBarCaptureService.merge(
            items: [item],
            captured: [captured],
            scale: 2
        )

        let retained = try XCTUnwrap(merged.first?.image)
        XCTAssertTrue(retained === image)
        XCTAssertEqual(merged.first?.scale, 2)
    }

    func testARC001BDiagnosticsPreserveCategoryAndFieldPrivacy() {
        let rendered = LiveMenuBarDiagnosticsRecorder.render(
            MenuBarDiagnosticEvent(
                name: "context_menu_command",
                category: .commandExecution,
                publicFields: ["reason": "manual", "command": "collapse"],
                privateFields: ["window_id": "42"]
            )
        )

        XCTAssertEqual(rendered.category, .commandExecution)
        XCTAssertEqual(rendered.name, "context_menu_command")
        XCTAssertEqual(rendered.publicFields, "command=collapse reason=manual")
        XCTAssertEqual(rendered.privateFields, "window_id=42")
    }

    private func activationRequest() -> MenuBarActivationRequest {
        MenuBarActivationRequest(
            item: MenuBarItemHandle(windowID: 7),
            targetDisplay: MenuBarDisplayHandle(rawValue: 3),
            visibleAnchor: MenuBarItemHandle(windowID: 11)
        )
    }

    private func placementRequest(display: MenuBarDisplayHandle) -> MenuBarPlacementRequest {
        MenuBarPlacementRequest(
            item: MenuBarItemHandle(windowID: 7),
            targetDisplay: display,
            desiredLane: .visible,
            anchor: .rightOf(MenuBarItemHandle(windowID: 11))
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

    private func windowInfo(
        windowID: UInt32,
        ownerPID: Int32,
        minX: Double
    ) -> MenuBarWindowInfo {
        MenuBarWindowInfo(
            windowID: windowID,
            frame: CGRect(x: minX, y: 0, width: 24, height: 24),
            ownerPID: ownerPID,
            ownerName: "Owner \(ownerPID)",
            title: "Item \(windowID)",
            isOnScreen: true
        )
    }

    private func makeTestImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
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
    private let image: CGImage?

    init(image: CGImage?) {
        self.image = image
    }

    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem] {
        requests.append(Request(items: items, display: display))
        return items.map { item in
            MenuBarCapturedItem(item: item, image: image, scale: 2)
        }
    }
}
