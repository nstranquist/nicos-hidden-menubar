import CoreGraphics
import Foundation

struct MenuBarDisplayHandle: Hashable, Sendable {
    var rawValue: UInt32
}

struct MenuBarItemHandle: Hashable, Sendable {
    // Transient until ITEM-001 introduces versioned stable identity.
    var windowID: UInt32
}

struct MenuBarDiscoveredItem: Equatable, Sendable {
    var handle: MenuBarItemHandle
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
    case failed(String)
}

struct MenuBarActivationRequest: Equatable, Sendable {
    var item: MenuBarItemHandle
    var targetDisplay: MenuBarDisplayHandle
    var visibleAnchor: MenuBarItemHandle
}

enum MenuBarActivationOutcome: Equatable, Sendable {
    case revealedForActivation
    case permissionRequired
    case unsupported(reason: String)
    case failed(reason: String)
}

struct MenuBarCapturedItem: Equatable, Sendable {
    var item: MenuBarDiscoveredItem
    var pngData: Data?
    var scale: Double
}

enum MenuBarDiagnosticLevel: String, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

struct MenuBarDiagnosticEvent: Equatable, Sendable {
    var name: String
    var level: MenuBarDiagnosticLevel
    var fields: [String: String]

    init(
        name: String,
        level: MenuBarDiagnosticLevel = .info,
        fields: [String: String] = [:]
    ) {
        self.name = name
        self.level = level
        self.fields = fields
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
    func capture(
        _ items: [MenuBarDiscoveredItem],
        on display: MenuBarDisplayHandle
    ) async -> [MenuBarCapturedItem]
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
