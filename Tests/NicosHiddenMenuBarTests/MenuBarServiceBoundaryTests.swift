import CoreGraphics
import Foundation
import XCTest
@testable import NicosHiddenMenuBar

@MainActor
final class MenuBarServiceBoundaryTests: XCTestCase {
    func testACT001InPlaceActivationOpensMenuWithoutPlacement() async {
        var opened: CGWindowID?
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { false },
            openMenu: { opened = $0 },
            accessibilityGranted: { true }
        )

        let outcome = await activation.activate(activationRequest(preferInPlace: true))

        XCTAssertEqual(outcome, .activated)
        XCTAssertEqual(opened, 7)
        XCTAssertTrue(placement.requests.isEmpty)
    }

    func testACT001PermissionRequiredIsExplicit() async {
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { false },
            openMenu: { _ in XCTFail("should not open without permission") },
            accessibilityGranted: { false }
        )

        let outcome = await activation.activate(activationRequest(preferInPlace: true))

        XCTAssertEqual(outcome, .permissionRequired(permission: "accessibility"))
        XCTAssertTrue(placement.requests.isEmpty)
    }

    func testACT001MovementPathPlacesThenRevealsWhenOpenSkipped() async {
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true },
            openMenu: { _ in throw MenuBarItemActivator.ActivateError.missingFrame },
            accessibilityGranted: { true }
        )
        // preferInPlace false forces placement-first path used when relocate requested.
        let outcome = await activation.activate(activationRequest(preferInPlace: false))

        XCTAssertEqual(outcome, .revealedForActivation)
        XCTAssertEqual(placement.requests.count, 1)
        XCTAssertEqual(placement.requests.first?.desiredLane, .visible)
    }

    func testACT001InPlaceFailureFallsBackToPlacementWhenMovementEnabled() async {
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true },
            openMenu: { _ in throw MenuBarItemActivator.ActivateError.missingFrame },
            accessibilityGranted: { true }
        )

        let outcome = await activation.activate(activationRequest(preferInPlace: true))

        XCTAssertEqual(outcome, .revealedForActivation)
        XCTAssertEqual(placement.requests.count, 1)
    }

    func testACT001UnsupportedWhenMovementDisabledAndOpenFails() async {
        let placement = RecordingPlacementService()
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { false },
            openMenu: { _ in throw MenuBarItemActivator.ActivateError.missingItem },
            accessibilityGranted: { true }
        )

        let outcome = await activation.activate(activationRequest(preferInPlace: true))

        XCTAssertEqual(outcome, .unsupported(reason: "item_missing"))
        XCTAssertTrue(placement.requests.isEmpty)
    }

    func testACT001OffScreenItemNeedsRelocateEvenWhenMovementDisabled() {
        let off = MenuBarWindowInfo(
            windowID: 9,
            frame: CGRect(x: 700, y: 0, width: 24, height: 22),
            ownerPID: 0,
            ownerName: nil,
            title: nil,
            isOnScreen: false
        )
        XCTAssertTrue(LiveMenuBarActivationService.itemNeedsRelocateForActivation(off))
        let on = MenuBarWindowInfo(
            windowID: 10,
            frame: CGRect(x: 1_200, y: 0, width: 24, height: 22),
            ownerPID: 42,
            ownerName: "App",
            title: "Item",
            isOnScreen: true
        )
        XCTAssertFalse(LiveMenuBarActivationService.itemNeedsRelocateForActivation(on))
        XCTAssertFalse(LiveMenuBarActivationService.itemNeedsRelocateForActivation(nil))
    }

    func testACT001MapsTypedImmovableFailure() async {
        let placement = RecordingPlacementService(error: MenuBarPlacementError.itemNotMovable)
        let activation = LiveMenuBarActivationService(
            placement: placement,
            isMovementEnabled: { true },
            openMenu: { _ in throw MenuBarItemActivator.ActivateError.missingFrame },
            accessibilityGranted: { true }
        )

        let outcome = await activation.activate(activationRequest(preferInPlace: false))

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
        let model = RevealPanelModel(discovery: discovery, capture: capture)

        let bounds = MenuBarLaneBounds(
            toggleX: 700,
            primaryX: 0,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_440
        )
        await model.reload(on: display, laneBounds: bounds, parkedWindowIDs: [], excludingOwnerPID: 42)

        XCTAssertEqual(discovery.requestedDisplays, [display])
        XCTAssertEqual(capture.requests.map { $0.items.map(\.handle.windowID) }, [[7]])
        XCTAssertEqual(capture.requests.map(\.display), [display])
        XCTAssertEqual(model.items.map(\.item.handle.windowID), [7])
        XCTAssertTrue(model.usesImages)

        model.prepareForHide()

        XCTAssertEqual(model.items.map(\.item.handle.windowID), [7])
        XCTAssertNil(model.items.first?.image)
        XCTAssertTrue(model.items.allSatisfy(\.isPlaceholder))
        XCTAssertFalse(model.usesImages)
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
        // Identities assigned and distinct.
        XCTAssertEqual(Set(snapshot.items.map(\.identity.key)).count, 2)
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

    private func activationRequest(preferInPlace: Bool = true) -> MenuBarActivationRequest {
        MenuBarActivationRequest(
            item: MenuBarItemHandle(windowID: 7),
            targetDisplay: MenuBarDisplayHandle(rawValue: 3),
            visibleAnchor: MenuBarItemHandle(windowID: 11),
            preferInPlace: preferInPlace
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
        let identity = MenuBarItemIdentity(namespace: "owner.\(ownerPID)", title: "Item \(windowID)")
        return MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(windowID: windowID, identity: identity),
            identity: identity,
            ownerPID: ownerPID,
            ownerName: "Owner \(ownerPID)",
            title: "Item \(windowID)",
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
            MenuBarCapturedItem(item: item, image: image, scale: 2, isPlaceholder: image == nil)
        }
    }
}
