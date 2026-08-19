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
        let ordered = scan.items.compactMap { detailsByID[$0.windowID] }
        let items = Self.discoveredItems(from: ordered)

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
        return Self.discoveredItems(from: MenuBarItemScanner.detailedItems(screen: screen))
    }

    /// Assigns versioned identities with ordinal disambiguation (ITEM-001) and
    /// enriches empty extra titles via one Accessibility extras-menu pass.
    static func discoveredItems(from details: [MenuBarWindowInfo]) -> [MenuBarDiscoveredItem] {
        let pids = Set(details.map(\.ownerPID))
        let axLabels = MenuBarAccessibilityCatalog.labeledFrames(forPIDs: pids)
        return discoveredItems(from: details, axLabels: axLabels) { pid in
            guard pid != 0 else { return nil }
            return NSRunningApplication(processIdentifier: pid)?.localizedName
        }
    }

    /// Same assignment the reveal panel uses after the one-scan AX fetch.
    /// Hidden and Overflow share this path — no section-specific names.
    nonisolated static func discoveredItems(
        from details: [MenuBarWindowInfo],
        axLabels: [MenuBarAccessibilityCatalog.LabeledFrame],
        appNameForPID: (pid_t) -> String?
    ) -> [MenuBarDiscoveredItem] {
        let extras = details.map { info in
            MenuBarExtraLabelAssigner.Extra(
                pid: info.ownerPID,
                frame: info.frame,
                windowTitle: (info.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                ownerName: info.ownerName ?? "",
                appName: appNameForPID(info.ownerPID)
            )
        }
        let assigned = MenuBarExtraLabelAssigner.assign(extras: extras, axLabels: axLabels)

        let raw = zip(details, assigned).map { info, assignment -> (namespace: String, title: String) in
            let namespace =
                MenuBarWindowInfo.bundleIdentifier(forPID: info.ownerPID)
                ?? info.ownerName
                ?? "unknown"
            return (namespace, assignment.title)
        }
        let identities = MenuBarItemIdentity.resolveScan(raw)

        var result: [MenuBarDiscoveredItem] = []
        result.reserveCapacity(details.count)
        for index in details.indices {
            let info = details[index]
            let assignment = assigned[index]
            let identity = identities[index]
            let displayName = Self.panelDisplayName(
                assignment: assignment,
                identity: identity
            )
            result.append(
                MenuBarDiscoveredItem(
                    handle: MenuBarItemHandle(windowID: info.windowID, identity: identity),
                    identity: identity,
                    ownerPID: info.ownerPID,
                    ownerName: info.ownerName ?? "Unknown",
                    title: assignment.title,
                    displayName: displayName,
                    frame: info.frame
                )
            )
        }
        return result
    }

    /// Control Center keeps module names; everyone else uses the assigner.
    nonisolated static func panelDisplayName(
        assignment: MenuBarExtraLabelAssigner.Assignment,
        identity: MenuBarItemIdentity
    ) -> String {
        if let ccName = ControlCenterModules.displayName(
            forModuleID: identity.moduleID,
            title: assignment.title,
            ordinal: identity.ordinal
        ),
            identity.namespace.lowercased().contains("controlcenter")
                || identity.namespace == ControlCenterModules.controlCenterNamespace
        {
            return ccName
        }
        return assignment.displayName
    }
}

extension MenuBarWindowInfo {
    fileprivate static func bundleIdentifier(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
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
        try await place(request, forceEnabled: false)
    }

    /// - Parameter forceEnabled: When true, allow the move even if experimental
    ///   free-rearrange is off (used for activation relocate / unhide).
    func place(_ request: MenuBarPlacementRequest, forceEnabled: Bool) async throws {
        guard request.desiredLane == .visible else {
            throw MenuBarPlacementError.unsupportedLane(request.desiredLane)
        }
        guard displayExists(request.targetDisplay) else {
            throw MenuBarPlacementError.targetUnavailable
        }

        let destination: MenuBarItemMover.Destination =
            switch request.anchor {
            case .leftOf(let anchor):
                .leftOf(targetWindowID: anchor.windowID)
            case .rightOf(let anchor):
                .rightOf(targetWindowID: anchor.windowID)
            }
        let enabled = forceEnabled || isMovementEnabled()
        do {
            try await move(request.item.windowID, destination, enabled)
        } catch MenuBarItemMover.MoveError.notEnabled {
            throw MenuBarPlacementError.movementDisabled
        } catch MenuBarItemMover.MoveError.notMovable {
            throw MenuBarPlacementError.itemNotMovable
        } catch MenuBarItemMover.MoveError.missingTarget {
            throw MenuBarPlacementError.targetUnavailable
        } catch MenuBarItemMover.MoveError.timedOut {
            throw MenuBarPlacementError.timedOut
        } catch MenuBarItemMover.MoveError.cancelled {
            throw MenuBarPlacementError.cancelled
        } catch {
            throw MenuBarPlacementError.failed(String(describing: error))
        }
    }
}

@MainActor
final class LiveMenuBarActivationService: MenuBarItemActivating {
    typealias OpenMenu = (CGWindowID) async throws -> Void

    private let placement: any MenuBarItemPlacing
    private let isMovementEnabled: () -> Bool
    private let openMenu: OpenMenu
    private let accessibilityGranted: () -> Bool

    init(
        placement: any MenuBarItemPlacing,
        isMovementEnabled: @escaping () -> Bool,
        openMenu: @escaping OpenMenu = { try await MenuBarItemActivator.openMenu(windowID: $0) },
        accessibilityGranted: @escaping () -> Bool = { MenuBarItemActivator.hasAccessibilityPermission() }
    ) {
        self.placement = placement
        self.isMovementEnabled = isMovementEnabled
        self.openMenu = openMenu
        self.accessibilityGranted = accessibilityGranted
    }

    func activate(_ request: MenuBarActivationRequest) async -> MenuBarActivationOutcome {
        let info = MenuBarWindowInfo.read(windowID: request.item.windowID)
        // Overflow / off-screen extras cannot receive a usable in-place click
        // (cursor jumps under the camera gap and menus never open).
        let needsRelocate = Self.itemNeedsRelocateForActivation(info)

        // Primary path: open in place when the item is already clickable.
        if request.preferInPlace, !needsRelocate {
            let inPlace = await attemptOpen(windowID: request.item.windowID)
            if case .activated = inPlace { return inPlace }
            if case .permissionRequired = inPlace { return inPlace }
            // Hard missing item — don't bother relocating a vanished window.
            if case .unsupported(let reason) = inPlace, reason == "item_missing" {
                return inPlace
            }
            // Recoverable open failure (incl. frame unreadable) → relocate when free-move is on.
            if !isMovementEnabled() { return inPlace }
        } else if needsRelocate {
            // Must relocate before open; not gated by experimental free-move.
        } else if !isMovementEnabled() {
            return .unsupported(reason: "experimental_item_movement_disabled")
        }

        // Secondary path: move into the visible lane, then open.
        do {
            try await placeForActivation(
                MenuBarPlacementRequest(
                    item: request.item,
                    targetDisplay: request.targetDisplay,
                    desiredLane: .visible,
                    anchor: .rightOf(request.visibleAnchor)
                ),
                forceEnabled: needsRelocate || isMovementEnabled()
            )
        } catch MenuBarPlacementError.itemNotMovable {
            let fallback = await attemptOpen(windowID: request.item.windowID)
            if case .activated = fallback { return .activated }
            return .unsupported(reason: "item_not_movable")
        } catch MenuBarPlacementError.movementDisabled {
            return .unsupported(reason: "experimental_item_movement_disabled")
        } catch MenuBarPlacementError.timedOut {
            return .failedRecovered(reason: "placement_timeout")
        } catch {
            return .failedRecovered(reason: String(describing: error))
        }

        let afterMove = await attemptOpen(windowID: request.item.windowID)
        if case .activated = afterMove {
            return .activated
        }
        return .revealedForActivation
    }

    /// Off-screen or zero-owner frames cannot be clicked in place.
    /// Missing info is not treated as relocate — openMenu reports missing item.
    static func itemNeedsRelocateForActivation(_ info: MenuBarWindowInfo?) -> Bool {
        guard let info else { return false }
        if !info.isOnScreen { return true }
        if info.ownerPID == 0 { return true }
        if info.frame.width < 1 || info.frame.height < 1 { return true }
        return false
    }

    private func placeForActivation(
        _ request: MenuBarPlacementRequest,
        forceEnabled: Bool
    ) async throws {
        if let live = placement as? LiveMenuBarPlacementService {
            try await live.place(request, forceEnabled: forceEnabled)
        } else {
            try await placement.place(request)
        }
    }

    private func attemptOpen(windowID: CGWindowID) async -> MenuBarActivationOutcome {
        if !accessibilityGranted() {
            return .permissionRequired(permission: "accessibility")
        }
        do {
            try await openMenu(windowID)
            return .activated
        } catch MenuBarItemActivator.ActivateError.accessibilityRequired {
            return .permissionRequired(permission: "accessibility")
        } catch MenuBarItemActivator.ActivateError.missingItem {
            return .unsupported(reason: "item_missing")
        } catch MenuBarItemActivator.ActivateError.missingFrame {
            return .unsupported(reason: "item_frame_unreadable")
        } catch {
            return .failedRecovered(reason: String(describing: error))
        }
    }

    func usesPlacementOwner(_ expected: LiveMenuBarPlacementService) -> Bool {
        (placement as? LiveMenuBarPlacementService) === expected
    }
}

@MainActor
final class LiveMenuBarCaptureService: MenuBarItemCapturing {
    private let cache: MenuBarIconCache

    init(cache: MenuBarIconCache = MenuBarIconCache()) {
        self.cache = cache
    }

    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem] {
        var result: [MenuBarCapturedItem] = []
        await captureIncremental(items, on: display) { result = $0 }
        return result
    }

    func captureIncremental(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle,
        onUpdate: @escaping @MainActor ([MenuBarCapturedItem]) -> Void
    ) async {
        guard let screen = NSScreen.menuBarScreen(for: display) else {
            onUpdate(items.map { MenuBarCapturedItem(item: $0, image: nil, scale: 1, isPlaceholder: true) })
            return
        }

        let scale = Double(screen.backingScaleFactor)
        var working = items.map { item -> MenuBarCapturedItem in
            let signature = MenuBarFrameSignature.make(item.frame, scale: scale)
            if let cached = cache.lookup(identityKey: item.identity.key, frameSignature: signature) {
                return MenuBarCapturedItem(item: item, image: cached.0, scale: cached.1, isPlaceholder: false)
            }
            return MenuBarCapturedItem(item: item, image: nil, scale: scale, isPlaceholder: true)
        }
        onUpdate(working)

        let needCapture = working.enumerated().compactMap { index, captured -> (Int, MenuBarDiscoveredItem)? in
            captured.image == nil ? (index, captured.item) : nil
        }
        guard !needCapture.isEmpty else { return }

        guard MenuBarItemImageCapture.hasScreenRecordingPermission() else {
            // Leave placeholders; text labels already usable.
            return
        }

        let windowInfos = needCapture.compactMap { _, item in
            MenuBarWindowInfo.read(windowID: item.handle.windowID)
        }
        let captured = await MenuBarItemImageCapture.capture(items: windowInfos, on: screen)
        let byWindow = Dictionary(uniqueKeysWithValues: captured.map { ($0.windowID, $0) })

        for (index, item) in needCapture {
            guard let shot = byWindow[item.handle.windowID], let image = shot.image else { continue }
            let signature = MenuBarFrameSignature.make(item.frame, scale: scale)
            cache.store(
                identityKey: item.identity.key,
                image: image,
                scale: scale,
                frameSignature: signature
            )
            working[index] = MenuBarCapturedItem(
                item: item,
                image: image,
                scale: scale,
                isPlaceholder: false
            )
            onUpdate(working)
        }
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
                scale: scale,
                isPlaceholder: capturedByWindowID[item.handle.windowID]?.image == nil
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
        let usesExpectedLiveOwners =
            discovery is LiveMenuBarDiscoveryService
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
