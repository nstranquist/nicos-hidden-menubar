import CoreGraphics
import Foundation

struct MenuBarDisplayHandle: Hashable, Sendable {
    var rawValue: UInt32
}

struct MenuBarItemHandle: Hashable, Sendable {
    var windowID: UInt32
    /// Durable identity when known; windowID remains the live handle.
    var identity: MenuBarItemIdentity?

    init(windowID: UInt32, identity: MenuBarItemIdentity? = nil) {
        self.windowID = windowID
        self.identity = identity
    }
}

struct MenuBarDiscoveredItem: Equatable, Sendable {
    var handle: MenuBarItemHandle
    var identity: MenuBarItemIdentity
    var ownerPID: Int32
    var ownerName: String
    var title: String
    var displayName: String
    var frame: CGRect
}

struct MenuBarDiscoverySnapshot: Equatable, Sendable {
    var items: [MenuBarDiscoveredItem]
    var hideableItemCount: Int
    var leftmostMinX: Double?
    var hasNotch: Bool
    var anyItemHiddenPastEdge: Bool
}

enum MenuBarLane: String, Equatable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

enum MenuBarPlacementAnchor: Equatable, Sendable {
    case leftOf(MenuBarItemHandle)
    case rightOf(MenuBarItemHandle)
}

struct MenuBarPlacementRequest: Equatable, Sendable {
    var item: MenuBarItemHandle
    var targetDisplay: MenuBarDisplayHandle
    var desiredLane: MenuBarLane
    var anchor: MenuBarPlacementAnchor
}

enum MenuBarPlacementError: Error, Equatable, Sendable {
    case movementDisabled
    case itemNotMovable
    case targetUnavailable
    case unsupportedLane(MenuBarLane)
    case timedOut
    case cancelled
    case failed(String)
}

struct MenuBarActivationRequest: Equatable, Sendable {
    var item: MenuBarItemHandle
    var targetDisplay: MenuBarDisplayHandle
    var visibleAnchor: MenuBarItemHandle
    /// Prefer opening the item where it is (panel path). When false and
    /// experimental movement is on, may relocate into the visible lane first.
    var preferInPlace: Bool

    init(
        item: MenuBarItemHandle,
        targetDisplay: MenuBarDisplayHandle,
        visibleAnchor: MenuBarItemHandle,
        preferInPlace: Bool = true
    ) {
        self.item = item
        self.targetDisplay = targetDisplay
        self.visibleAnchor = visibleAnchor
        self.preferInPlace = preferInPlace
    }
}

/// Explicit panel-activation outcomes (item-lifecycle ACT-001 contract).
enum MenuBarActivationOutcome: Equatable, Sendable {
    /// Selected menu opened in place.
    case activated
    /// Item was moved into the visible lane so the user can click it.
    case revealedForActivation
    /// Named permission is missing; UI should offer repair.
    case permissionRequired(permission: String)
    /// Not safely activatable; reason is operator-facing.
    case unsupported(reason: String)
    /// Failed; caller should treat state as recovered / non-destructive.
    case failedRecovered(reason: String)

    /// Legacy alias used by older diagnostics.
    static func failed(reason: String) -> MenuBarActivationOutcome {
        .failedRecovered(reason: reason)
    }
}

struct MenuBarCapturedItem: Sendable {
    var item: MenuBarDiscoveredItem
    var image: CGImage?
    var scale: Double
    var isPlaceholder: Bool

    init(
        item: MenuBarDiscoveredItem,
        image: CGImage? = nil,
        scale: Double = 1,
        isPlaceholder: Bool = false
    ) {
        self.item = item
        self.image = image
        self.scale = scale
        self.isPlaceholder = isPlaceholder
    }
}

enum MenuBarDiagnosticCategory: String, Equatable, Sendable {
    case appLifecycle
    case menuBar
    case windowing
    case commandExecution
}

enum MenuBarDiagnosticLevel: String, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

struct MenuBarDiagnosticEvent: Equatable, Sendable {
    var name: String
    var category: MenuBarDiagnosticCategory
    var level: MenuBarDiagnosticLevel
    var publicFields: [String: String]
    var privateFields: [String: String]

    init(
        name: String,
        category: MenuBarDiagnosticCategory = .menuBar,
        level: MenuBarDiagnosticLevel = .info,
        publicFields: [String: String] = [:],
        privateFields: [String: String] = [:]
    ) {
        self.name = name
        self.category = category
        self.level = level
        self.publicFields = publicFields
        self.privateFields = privateFields
    }
}

struct MenuBarDiagnosticRenderedEvent: Equatable, Sendable {
    var category: MenuBarDiagnosticCategory
    var name: String
    var publicFields: String
    var privateFields: String
}

struct MenuBarServiceCompositionReport: Equatable, Sendable {
    var ownerTypes: [String: String]
    var usesExpectedLiveOwners: Bool
    var activationUsesRegisteredPlacement: Bool

    var ok: Bool {
        usesExpectedLiveOwners && activationUsesRegisteredPlacement
    }

    var detail: String {
        let owners = ownerTypes
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "liveOwners=\(usesExpectedLiveOwners) sharedPlacement=\(activationUsesRegisteredPlacement) \(owners)"
    }
}

@MainActor
protocol MenuBarItemDiscovering {
    func snapshot(
        on display: MenuBarDisplayHandle,
        toggleMinX: Double?
    ) -> MenuBarDiscoverySnapshot?

    func discoverItems(on display: MenuBarDisplayHandle) -> [MenuBarDiscoveredItem]
}

@MainActor
protocol MenuBarItemPlacing {
    func place(_ request: MenuBarPlacementRequest) async throws
}

@MainActor
protocol MenuBarItemActivating {
    func activate(_ request: MenuBarActivationRequest) async -> MenuBarActivationOutcome
}

@MainActor
protocol MenuBarItemCapturing {
    /// Full batch capture (blocking until complete). Prefer `captureIncremental`.
    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem]

    /// Shell-first: emit placeholders immediately, then fill icons as ready.
    func captureIncremental(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle,
        onUpdate: @escaping @MainActor ([MenuBarCapturedItem]) -> Void
    ) async
}

@MainActor
protocol MenuBarDiagnosticsRecording {
    func record(_ event: MenuBarDiagnosticEvent)
}

@MainActor
struct MenuBarServices {
    let discovery: any MenuBarItemDiscovering
    let placement: any MenuBarItemPlacing
    let activation: any MenuBarItemActivating
    let capture: any MenuBarItemCapturing
    let diagnostics: any MenuBarDiagnosticsRecording
}

/// Default incremental path for capturers that only implement batch capture.
extension MenuBarItemCapturing {
    func captureIncremental(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle,
        onUpdate: @escaping @MainActor ([MenuBarCapturedItem]) -> Void
    ) async {
        let placeholders = items.map {
            MenuBarCapturedItem(item: $0, image: nil, scale: 1, isPlaceholder: true)
        }
        onUpdate(placeholders)
        let final = await capture(items, on: display)
        onUpdate(final)
    }
}
