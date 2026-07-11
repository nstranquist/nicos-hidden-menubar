import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures images of menu bar items so the IceBar can render hidden items in a
/// popover instead of cramming them back into the menu bar. Same idea as Ice's
/// `MenuBarItemImageCache`, using the modern one-shot `SCScreenshotManager`.
///
/// Requires Screen Recording permission. Callers degrade gracefully to text
/// labels when capture is unavailable.
enum MenuBarItemImageCapture {
    struct CapturedItem: Sendable {
        var info: MenuBarItemInfo
        var displayName: String
        var windowID: CGWindowID
        var frame: CGRect
        var image: CGImage?
    }

    /// True when Screen Recording permission is granted (required for capture).
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission (shows the system prompt once).
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Capture images for the given items on `screen`. Returns items in input
    /// order; `image` is nil for any item that couldn't be captured.
    @MainActor
    static func capture(items: [MenuBarWindowInfo], on screen: NSScreen) async -> [CapturedItem] {
        guard hasScreenRecordingPermission(), !items.isEmpty else {
            return items.map {
                CapturedItem(info: $0.info, displayName: $0.displayName, windowID: $0.windowID, frame: $0.frame, image: nil)
            }
        }

        let displayID = screen.displayID
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            HiddenMenuBarTelemetry.menuBar.error("SCShareableContent failed: \(error.localizedDescription)")
            return items.map {
                CapturedItem(info: $0.info, displayName: $0.displayName, windowID: $0.windowID, frame: $0.frame, image: nil)
            }
        }

        let scWindowsByID = Dictionary(
            content.windows.map { (CGWindowID($0.windowID), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let scale = screen.backingScaleFactor

        var results: [CapturedItem] = []
        for item in items {
            var image: CGImage?
            if let scWindow = scWindowsByID[item.windowID] {
                image = await captureWindow(scWindow, scale: scale)
            }
            results.append(
                CapturedItem(
                    info: item.info,
                    displayName: item.displayName,
                    windowID: item.windowID,
                    frame: item.frame,
                    image: image
                )
            )
        }
        _ = displayID
        return results
    }

    @MainActor
    private static func captureWindow(_ window: SCWindow, scale: CGFloat) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }
}
