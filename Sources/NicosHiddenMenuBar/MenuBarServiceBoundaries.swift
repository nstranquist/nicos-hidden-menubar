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
    var ownerName: String
    var title: String
    var frame: CGRect
}

enum MenuBarLane: String, Equatable, Sendable {
    case visible
    case hidden
    case alwaysHidden
}

struct MenuBarPlacementRequest: Equatable, Sendable {
    var item: MenuBarItemHandle
    var targetDisplay: MenuBarDisplayHandle
    var desiredLane: MenuBarLane
}

enum MenuBarActivationOutcome: Equatable, Sendable {
    case activated
    case permissionRequired
    case unsupported(reason: String)
    case failed(reason: String)
}

struct MenuBarCapturedImage: Equatable, Sendable {
    var pngData: Data
    var scale: Double
}

struct MenuBarDiagnosticEvent: Equatable, Sendable {
    var name: String
    var fields: [String: String]
}

protocol MenuBarItemDiscovering {
    func discoverItems(on display: MenuBarDisplayHandle) async throws -> [MenuBarDiscoveredItem]
}

protocol MenuBarItemPlacing {
    func place(_ request: MenuBarPlacementRequest) async throws
}

protocol MenuBarItemActivating {
    func activate(_ item: MenuBarItemHandle) async -> MenuBarActivationOutcome
}

protocol MenuBarItemCapturing {
    func capture(_ item: MenuBarItemHandle) async -> MenuBarCapturedImage?
}

protocol MenuBarDiagnosticsRecording {
    func record(_ event: MenuBarDiagnosticEvent)
}
