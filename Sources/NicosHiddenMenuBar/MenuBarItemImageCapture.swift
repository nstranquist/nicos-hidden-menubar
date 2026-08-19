import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

/// Captures images of menu bar items so the RevealPanel can render icons.
/// Uses ScreenCaptureKit when permission and a matching window are available;
/// otherwise returns nil so the UI uses SF Symbols / app icons.
enum MenuBarItemImageCapture {
    struct CapturedItem: Sendable {
        var info: MenuBarItemInfo
        var displayName: String
        var windowID: CGWindowID
        var frame: CGRect
        var image: CGImage?
    }

    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @MainActor
    static func capture(items: [MenuBarWindowInfo], on screen: NSScreen) async -> [CapturedItem] {
        guard !items.isEmpty else { return [] }

        // Always attempt the permission path even if preflight is flaky; when
        // denied the UI falls back to symbols/app icons.
        if !hasScreenRecordingPermission() {
            // Kick the TCC prompt once so the user can enable Screen Recording.
            _ = requestScreenRecordingPermission()
        }

        let scale = screen.backingScaleFactor
        var scWindowsByID: [CGWindowID: SCWindow] = [:]
        if hasScreenRecordingPermission() {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                scWindowsByID = Dictionary(
                    content.windows.map { (CGWindowID($0.windowID), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            } catch {
                HiddenMenuBarTelemetry.menuBar.error(
                    "SCShareableContent failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        var results: [CapturedItem] = []
        results.reserveCapacity(items.count)
        for item in items {
            let image: CGImage? =
                if let scWindow = scWindowsByID[item.windowID] {
                    await captureWindowSC(scWindow, scale: scale)
                } else {
                    nil
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
            await Task.yield()
        }
        return results
    }

    @MainActor
    private static func captureWindowSC(_ window: SCWindow, scale: CGFloat) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Menu bar items are tiny — oversample so icons stay sharp.
        let w = max(24, Int(window.frame.width * scale * 2))
        let h = max(24, Int(window.frame.height * scale * 2))
        config.width = w
        config.height = h
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            HiddenMenuBarTelemetry.menuBar.debug("SC capture failed for window")
            return nil
        }
    }

}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }
}
