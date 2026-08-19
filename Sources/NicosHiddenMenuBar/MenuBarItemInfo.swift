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

    /// Legacy `namespace:title` key retained for migration (ITEM-001-B).
    var legacyKey: String { "\(namespace):\(title)" }

    /// Versioned durable key (ITEM-001). Prefer `identity.key` when ordinal matters.
    var key: String { identity.key }

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
        "com.apple.controlcenter.clock"
    ]

    var isLikelyImmovable: Bool {
        MenuBarItemInfo.immovableNamespaces.contains(namespace)
    }
}

/// Window-server metadata for a single menu bar item window. Read-only.
struct MenuBarWindowInfo: Sendable {
    var windowID: CGWindowID
    var frame: CGRect
    var ownerPID: pid_t
    var ownerName: String?
    var title: String?
    var isOnScreen: Bool

    /// The Window Server publishes the full-width menu-bar backdrop in the
    /// private process-menu-bar list alongside real menu extras. It is chrome,
    /// not an actionable item, and must never participate in lane counts or
    /// collapse verification.
    var isMenuBarBackdrop: Bool {
        ownerName == "Window Server" && title == "Menubar"
    }

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
    ///
    /// `CGWindowListCreateDescriptionFromArray` is the primary path because,
    /// unlike `CGWindowListCopyWindowInfo(.optionIncludingWindow, ...)`, it
    /// preserves owner/title metadata for menu extras that are currently
    /// off-screen. This is the same distinction Ice relies on for its Ice Bar.
    ///
    /// Falls back to CGS frame-only when both public metadata paths miss the
    /// item. Those windows are still real menu-bar items and must appear in
    /// Overflow.
    static func read(windowID: CGWindowID) -> MenuBarWindowInfo? {
        let bridgedFrame = MenuBarBridging.frame(for: windowID)
        if let dict = descriptionDictionary(for: windowID)
            ?? copyWindowDictionary(for: windowID)
        {
            return decode(windowID: windowID, dictionary: dict, bridgedFrame: bridgedFrame)
        }

        // CGWindowList missed it — still readable via CGS (overflow under-gap case).
        guard let bridgedFrame, bridgedFrame.width >= 1 else {
            return nil
        }
        return MenuBarWindowInfo(
            windowID: windowID,
            frame: bridgedFrame,
            ownerPID: 0,
            ownerName: nil,
            title: nil,
            isOnScreen: false
        )
    }

    /// Pure decoder retained as an internal seam for off-screen metadata tests.
    static func decode(
        windowID: CGWindowID,
        dictionary: [String: Any],
        bridgedFrame: CGRect?
    ) -> MenuBarWindowInfo {
        let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        let ownerName = dictionary[kCGWindowOwnerName as String] as? String
        let title = dictionary[kCGWindowName as String] as? String
        let isOnScreen = (dictionary[kCGWindowIsOnscreen as String] as? Bool) ?? false

        var frame = CGRect.zero
        if let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
            let decoded = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        {
            frame = decoded
        } else if let bridgedFrame {
            frame = bridgedFrame
        }

        if frame.width < 1, let bridgedFrame {
            frame = bridgedFrame
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

    private static func descriptionDictionary(for windowID: CGWindowID) -> [String: Any]? {
        var pointer = UnsafeRawPointer(bitPattern: Int(windowID))
        guard
            let array = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil),
            let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [CFDictionary],
            let description = descriptions.first
        else {
            return nil
        }
        return description as? [String: Any]
    }

    private static func copyWindowDictionary(for windowID: CGWindowID) -> [String: Any]? {
        let infoList =
            CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                windowID
            ) as? [[String: Any]]
        return infoList?.first
    }
}
