import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class LiveMenuBarDiscoveryService: MenuBarItemDiscovering {
    func snapshot(
        on display: MenuBarDisplayHandle,
        toggleMinX: Double?
    ) -> MenuBarDiscoverySnapshot? {
        guard let screen = NSScreen.menuBarScreen(for: display) else {
            return nil
        }

        return Self.makeSnapshot(
            from: MenuBarItemScanner.detailedItems(screen: screen),
            toggleMinX: toggleMinX,
            visibleMaxX: Double(screen.visibleFrame.maxX),
            hasNotch: MenuBarItemScanner.screenHasNotch(screen)
        )
    }

    static func makeSnapshot(
        from details: [MenuBarWindowInfo],
        toggleMinX: Double?,
        visibleMaxX: Double?,
        hasNotch: Bool
    ) -> MenuBarDiscoverySnapshot {
        let scan = MenuBarItemScanner.summarize(
            items: details.map { MenuBarItemScanner.Item(windowID: $0.windowID, frame: $0.frame) },
            toggleMinX: toggleMinX,
            visibleMaxX: visibleMaxX,
            hasNotch: hasNotch
        )
        let detailsByID = Dictionary(uniqueKeysWithValues: details.map { ($0.windowID, $0) })
        let items = scan.items.compactMap { item in
            detailsByID[item.windowID].map(Self.discoveredItem)
        }

        return MenuBarDiscoverySnapshot(
            items: items,
            hideableItemCount: scan.hideableItemCount,
            leftmostMinX: scan.leftmostMinX,
            hasNotch: scan.hasNotch,
            anyItemHiddenPastEdge: scan.anyItemHiddenPastEdge
        )
    }

    func discoverItems(on display: MenuBarDisplayHandle) -> [MenuBarDiscoveredItem] {
        guard let screen = NSScreen.menuBarScreen(for: display) else {
            return []
        }
        return MenuBarItemScanner.detailedItems(screen: screen).map(Self.discoveredItem)
    }

    private static func discoveredItem(from info: MenuBarWindowInfo) -> MenuBarDiscoveredItem {
        MenuBarDiscoveredItem(
            handle: MenuBarItemHandle(windowID: info.windowID),
            ownerPID: info.ownerPID,
            ownerName: info.ownerName ?? "Unknown",
            title: info.title ?? "",
            displayName: info.displayName,
            frame: info.frame
        )
    }
}

@MainActor
final class LiveMenuBarPlacementService: MenuBarItemPlacing {
    typealias DisplayExists = (MenuBarDisplayHandle) -> Bool
    typealias MoveOperation = (
        CGWindowID,
        MenuBarItemMover.Destination,
        Bool
    ) async throws -> Void

    private let isMovementEnabled: () -> Bool
    private let displayExists: DisplayExists
    private let move: MoveOperation

    init(
        isMovementEnabled: @escaping () -> Bool,
        displayExists: @escaping DisplayExists = { NSScreen.menuBarScreen(for: $0) != nil },
        move: @escaping MoveOperation = { windowID, destination, enabled in
            try await MenuBarItemMover.move(
                windowID: windowID,
                to: destination,
                enabled: enabled
            )
        }
    ) {
        self.isMovementEnabled = isMovementEnabled
        self.displayExists = displayExists
        self.move = move
    }

    func place(_ request: MenuBarPlacementRequest) async throws {
        guard request.desiredLane == .visible else {
            throw MenuBarPlacementError.unsupportedLane(request.desiredLane)
        }
        guard displayExists(request.targetDisplay) else {
            throw MenuBarPlacementError.targetUnavailable
        }

        let destination: MenuBarItemMover.Destination = switch request.anchor {
        case .leftOf(let anchor):
            .leftOf(targetWindowID: anchor.windowID)
        case .rightOf(let anchor):
            .rightOf(targetWindowID: anchor.windowID)
        }
        do {
            try await move(request.item.windowID, destination, isMovementEnabled())
        } catch MenuBarItemMover.MoveError.notEnabled {
            throw MenuBarPlacementError.movementDisabled
        } catch MenuBarItemMover.MoveError.notMovable {
            throw MenuBarPlacementError.itemNotMovable
        } catch MenuBarItemMover.MoveError.missingTarget {
            throw MenuBarPlacementError.targetUnavailable
        } catch {
            throw MenuBarPlacementError.failed(String(describing: error))
        }
    }
}

@MainActor
final class LiveMenuBarActivationService: MenuBarItemActivating {
    private let placement: any MenuBarItemPlacing
    private let isMovementEnabled: () -> Bool

    init(
        placement: any MenuBarItemPlacing,
        isMovementEnabled: @escaping () -> Bool
    ) {
        self.placement = placement
        self.isMovementEnabled = isMovementEnabled
    }

    func activate(_ request: MenuBarActivationRequest) async -> MenuBarActivationOutcome {
        guard isMovementEnabled() else {
            return .unsupported(reason: "experimental_item_movement_disabled")
        }

        do {
            try await placement.place(
                MenuBarPlacementRequest(
                    item: request.item,
                    targetDisplay: request.targetDisplay,
                    desiredLane: .visible,
                    anchor: .rightOf(request.visibleAnchor)
                )
            )
            return .revealedForActivation
        } catch MenuBarPlacementError.itemNotMovable {
            return .unsupported(reason: "item_not_movable")
        } catch MenuBarPlacementError.movementDisabled {
            return .unsupported(reason: "experimental_item_movement_disabled")
        } catch {
            return .failed(reason: String(describing: error))
        }
    }

    func usesPlacementOwner(_ expected: LiveMenuBarPlacementService) -> Bool {
        (placement as? LiveMenuBarPlacementService) === expected
    }
}

@MainActor
final class LiveMenuBarCaptureService: MenuBarItemCapturing {
    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem] {
        guard let screen = NSScreen.menuBarScreen(for: display) else {
            return items.map { MenuBarCapturedItem(item: $0, image: nil, scale: 1) }
        }

        let windowInfo = items.compactMap { MenuBarWindowInfo.read(windowID: $0.handle.windowID) }
        let captured = await MenuBarItemImageCapture.capture(items: windowInfo, on: screen)
        return Self.merge(
            items: items,
            captured: captured,
            scale: Double(screen.backingScaleFactor)
        )
    }

    static func merge(
        items: [MenuBarDiscoveredItem],
        captured: [MenuBarItemImageCapture.CapturedItem],
        scale: Double
    ) -> [MenuBarCapturedItem] {
        let capturedByWindowID = Dictionary(uniqueKeysWithValues: captured.map { ($0.windowID, $0) })
        return items.map { item in
            MenuBarCapturedItem(
                item: item,
                image: capturedByWindowID[item.handle.windowID]?.image,
                scale: scale
            )
        }
    }
}

@MainActor
final class LiveMenuBarDiagnosticsRecorder: MenuBarDiagnosticsRecording {
    func record(_ event: MenuBarDiagnosticEvent) {
        let rendered = Self.render(event)
        let logger = Self.logger(for: event.category)

        switch event.level {
        case .debug:
            logger.debug(
                "\(rendered.name, privacy: .public) \(rendered.publicFields, privacy: .public) \(rendered.privateFields, privacy: .private)"
            )
        case .info:
            logger.info(
                "\(rendered.name, privacy: .public) \(rendered.publicFields, privacy: .public) \(rendered.privateFields, privacy: .private)"
            )
        case .warning:
            logger.warning(
                "\(rendered.name, privacy: .public) \(rendered.publicFields, privacy: .public) \(rendered.privateFields, privacy: .private)"
            )
        case .error:
            logger.error(
                "\(rendered.name, privacy: .public) \(rendered.publicFields, privacy: .public) \(rendered.privateFields, privacy: .private)"
            )
        }
    }

    static func render(_ event: MenuBarDiagnosticEvent) -> MenuBarDiagnosticRenderedEvent {
        MenuBarDiagnosticRenderedEvent(
            category: event.category,
            name: event.name,
            publicFields: renderFields(event.publicFields),
            privateFields: renderFields(event.privateFields)
        )
    }

    private static func renderFields(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func logger(for category: MenuBarDiagnosticCategory) -> Logger {
        switch category {
        case .appLifecycle:
            HiddenMenuBarTelemetry.appLifecycle
        case .menuBar:
            HiddenMenuBarTelemetry.menuBar
        case .windowing:
            HiddenMenuBarTelemetry.windowing
        case .commandExecution:
            HiddenMenuBarTelemetry.commandExecution
        }
    }
}

@MainActor
extension MenuBarServices {
    static func live(preferencesStore: PreferencesStore) -> MenuBarServices {
        let movementEnabled = { @MainActor in
            preferencesStore.config.isExperimentalItemMovementEnabled
        }
        let placement = LiveMenuBarPlacementService(isMovementEnabled: movementEnabled)
        return MenuBarServices(
            discovery: LiveMenuBarDiscoveryService(),
            placement: placement,
            activation: LiveMenuBarActivationService(
                placement: placement,
                isMovementEnabled: movementEnabled
            ),
            capture: LiveMenuBarCaptureService(),
            diagnostics: LiveMenuBarDiagnosticsRecorder()
        )
    }

    func compositionReport() -> MenuBarServiceCompositionReport {
        let ownerTypes = [
            "activation": String(describing: type(of: activation)),
            "capture": String(describing: type(of: capture)),
            "diagnostics": String(describing: type(of: diagnostics)),
            "discovery": String(describing: type(of: discovery)),
            "placement": String(describing: type(of: placement)),
        ]
        let usesExpectedLiveOwners = discovery is LiveMenuBarDiscoveryService
            && placement is LiveMenuBarPlacementService
            && activation is LiveMenuBarActivationService
            && capture is LiveMenuBarCaptureService
            && diagnostics is LiveMenuBarDiagnosticsRecorder
        let activationUsesRegisteredPlacement: Bool = {
            guard
                let placement = placement as? LiveMenuBarPlacementService,
                let activation = activation as? LiveMenuBarActivationService
            else {
                return false
            }
            return activation.usesPlacementOwner(placement)
        }()
        return MenuBarServiceCompositionReport(
            ownerTypes: ownerTypes,
            usesExpectedLiveOwners: usesExpectedLiveOwners,
            activationUsesRegisteredPlacement: activationUsesRegisteredPlacement
        )
    }
}

extension NSScreen {
    fileprivate static func menuBarScreen(for handle: MenuBarDisplayHandle) -> NSScreen? {
        screens.first { $0.displayID == handle.rawValue }
    }
}
