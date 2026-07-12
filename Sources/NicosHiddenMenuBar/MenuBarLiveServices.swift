import AppKit
import CoreGraphics
import Foundation

@MainActor
final class LiveMenuBarDiscoveryService: MenuBarItemDiscovering {
    func snapshot(
        on display: MenuBarDisplayHandle,
        toggleMinX: Double?
    ) -> MenuBarDiscoverySnapshot? {
        guard let screen = NSScreen.menuBarScreen(for: display) else {
            return nil
        }

        let scan = MenuBarItemScanner.scan(screen: screen, toggleMinX: toggleMinX)
        let details = Dictionary(
            uniqueKeysWithValues: MenuBarItemScanner.detailedItems(screen: screen).map {
                ($0.windowID, Self.discoveredItem(from: $0))
            }
        )
        let items = scan.items.map { item in
            details[item.windowID] ?? MenuBarDiscoveredItem(
                handle: MenuBarItemHandle(windowID: item.windowID),
                ownerPID: 0,
                ownerName: "Unknown",
                title: "",
                displayName: "Unknown",
                frame: item.frame
            )
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
    private let isMovementEnabled: () -> Bool

    init(isMovementEnabled: @escaping () -> Bool) {
        self.isMovementEnabled = isMovementEnabled
    }

    func place(_ request: MenuBarPlacementRequest) async throws {
        guard request.desiredLane == .visible else {
            throw MenuBarPlacementError.unsupportedLane(request.desiredLane)
        }
        guard NSScreen.menuBarScreen(for: request.targetDisplay) != nil else {
            throw MenuBarPlacementError.targetUnavailable
        }

        let destination: MenuBarItemMover.Destination = switch request.anchor {
        case .leftOf(let anchor):
            .leftOf(targetWindowID: anchor.windowID)
        case .rightOf(let anchor):
            .rightOf(targetWindowID: anchor.windowID)
        }
        do {
            try await MenuBarItemMover.move(
                windowID: request.item.windowID,
                to: destination,
                enabled: isMovementEnabled()
            )
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
}

@MainActor
final class LiveMenuBarCaptureService: MenuBarItemCapturing {
    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem] {
        guard let screen = NSScreen.menuBarScreen(for: display) else {
            return items.map { MenuBarCapturedItem(item: $0, pngData: nil, scale: 1) }
        }

        let windowInfo = items.compactMap { MenuBarWindowInfo.read(windowID: $0.handle.windowID) }
        let captured = await MenuBarItemImageCapture.capture(items: windowInfo, on: screen)
        let capturedByWindowID = Dictionary(uniqueKeysWithValues: captured.map { ($0.windowID, $0) })

        return items.map { item in
            let image = capturedByWindowID[item.handle.windowID]?.image
            let pngData = image.flatMap(Self.pngData)
            return MenuBarCapturedItem(
                item: item,
                pngData: pngData,
                scale: Double(screen.backingScaleFactor)
            )
        }
    }

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

@MainActor
final class LiveMenuBarDiagnosticsRecorder: MenuBarDiagnosticsRecording {
    func record(_ event: MenuBarDiagnosticEvent) {
        let fields = event.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        switch event.level {
        case .debug:
            HiddenMenuBarTelemetry.menuBar.debug(
                "\(event.name, privacy: .public) \(fields, privacy: .private(mask: .hash))"
            )
        case .info:
            HiddenMenuBarTelemetry.menuBar.info(
                "\(event.name, privacy: .public) \(fields, privacy: .private(mask: .hash))"
            )
        case .warning:
            HiddenMenuBarTelemetry.menuBar.warning(
                "\(event.name, privacy: .public) \(fields, privacy: .private(mask: .hash))"
            )
        case .error:
            HiddenMenuBarTelemetry.menuBar.error(
                "\(event.name, privacy: .public) \(fields, privacy: .private(mask: .hash))"
            )
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
}

extension NSScreen {
    fileprivate static func menuBarScreen(for handle: MenuBarDisplayHandle) -> NSScreen? {
        screens.first { $0.displayID == handle.rawValue }
    }
}
