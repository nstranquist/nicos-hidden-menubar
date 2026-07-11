import AppKit
import CoreGraphics
import Foundation

/// Stable identity + display metadata for a menu bar item, derived from the
/// window server. Mirrors the role of Ice's `MenuBarItemInfo` / `WindowInfo`
/// pair, scoped to what our app needs: identify an item across scans, show it to
/// the user, and decide whether it may be hidden.
struct MenuBarItemInfo: Equatable, Hashable, Sendable, Codable {
    /// Owning application's bundle identifier (or owner name when unavailable).
    var namespace: String
    /// The item's title (often empty for image-only items).
    var title: String

    /// A stable key string for caching/dedupe.
    var key: String { "\(namespace):\(title)" }

    init(namespace: String, title: String) {
        self.namespace = namespace
        self.title = title
    }
}

extension MenuBarItemInfo {
    /// Items macOS won't let us move or that we must never hide. Matched on
    /// namespace so we never fight the system over the clock / Control Center /
    /// Siri / our own control items.
    static let immovableNamespaces: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.Siri",
    ]

    static let nonHideableNamespaces: Set<String> = [
        "com.apple.controlcenter.clock",
    ]

    var isLikelyImmovable: Bool {
        MenuBarItemInfo.immovableNamespaces.contains(namespace)
    }
}

/// Window-server metadata for a single menu bar item window, read via
/// `CGWindowListCopyWindowInfo`. Read-only.
struct MenuBarWindowInfo: Sendable {
    var windowID: CGWindowID
    var frame: CGRect
    var ownerPID: pid_t
    var ownerName: String?
    var title: String?
    var isOnScreen: Bool

    var info: MenuBarItemInfo {
        let namespace = MenuBarWindowInfo.bundleIdentifier(forPID: ownerPID) ?? ownerName ?? "unknown"
        return MenuBarItemInfo(namespace: namespace, title: title ?? "")
    }

    /// Human-facing label for the item.
    var displayName: String {
        if let app = NSRunningApplication(processIdentifier: ownerPID), let name = app.localizedName {
            if let title, !title.isEmpty, title != name {
                return "\(name) — \(title)"
            }
            return name
        }
        if let title, !title.isEmpty { return title }
        return ownerName ?? "Unknown"
    }

    private static func bundleIdentifier(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Builds metadata for a window ID using public CoreGraphics window info.
    static func read(windowID: CGWindowID) -> MenuBarWindowInfo? {
        guard
            let infoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
            let dict = infoList.first
        else {
            return nil
        }
        let ownerPID = (dict[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        let ownerName = dict[kCGWindowOwnerName as String] as? String
        let title = dict[kCGWindowName as String] as? String
        let isOnScreen = (dict[kCGWindowIsOnscreen as String] as? Bool) ?? false

        var frame = CGRect.zero
        if let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
           let cf = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            frame = cf
        } else if let bridged = MenuBarBridging.frame(for: windowID) {
            frame = bridged
        }

        return MenuBarWindowInfo(
            windowID: windowID,
            frame: frame,
            ownerPID: ownerPID,
            ownerName: ownerName,
            title: title,
            isOnScreen: isOnScreen
        )
    }
}
