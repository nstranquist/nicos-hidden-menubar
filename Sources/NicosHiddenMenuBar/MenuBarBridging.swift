import CoreGraphics
import Foundation

/// Thin Swift wrapper over the private CGS window-server calls.
///
/// Mirrors the subset of `Bridging` from Ice (jordanbaird/Ice) that we need to
/// see the real menu bar: the on-screen menu bar window list and per-window
/// frames. Everything here is read-only — we observe ground truth but never
/// move other apps' items (that would require synthesized Cmd-drag events).
enum MenuBarBridging {
    private static func onScreenWindowCount() -> Int {
        var count: Int32 = 0
        _ = CGSGetOnScreenWindowCount(CGSMainConnectionID(), 0, &count)
        return Int(max(0, count))
    }

    private static func totalWindowCount() -> Int {
        var count: Int32 = 0
        _ = CGSGetWindowCount(CGSMainConnectionID(), 0, &count)
        return Int(max(0, count))
    }

    /// Full process menu-bar window list (includes items parked past the edge).
    static func allMenuBarWindowIDs() -> [CGWindowID] {
        let capacity = max(totalWindowCount(), onScreenWindowCount())
        guard capacity > 0 else {
            return []
        }
        var menuBarList = [CGWindowID](repeating: 0, count: capacity)
        var menuBarRealCount: Int32 = 0
        let menuBarResult = CGSGetProcessMenuBarWindowList(
            CGSMainConnectionID(),
            0,
            Int32(capacity),
            &menuBarList,
            &menuBarRealCount
        )
        guard menuBarResult == .success, menuBarRealCount > 0 else {
            return []
        }
        return Array(menuBarList[..<Int(menuBarRealCount)])
    }

    /// Window IDs for every menu bar item currently on screen.
    static func onScreenMenuBarWindowIDs() -> [CGWindowID] {
        let menuBarIDs = allMenuBarWindowIDs()
        guard !menuBarIDs.isEmpty else { return [] }

        let capacity = max(totalWindowCount(), onScreenWindowCount(), menuBarIDs.count)
        var onScreenList = [CGWindowID](repeating: 0, count: capacity)
        var onScreenRealCount: Int32 = 0
        let onScreenResult = CGSGetOnScreenWindowList(
            CGSMainConnectionID(),
            0,
            Int32(capacity),
            &onScreenList,
            &onScreenRealCount
        )
        guard onScreenResult == .success, onScreenRealCount > 0 else {
            return menuBarIDs
        }
        let onScreen = Set(onScreenList[..<Int(onScreenRealCount)])
        return menuBarIDs.filter(onScreen.contains)
    }

    /// Public WindowServer projection of windows that are actually rendered.
    /// CGS can retain one menu-extra ID in its on-screen list briefly after a
    /// spacer has made that item invisible, so collapse verification uses this
    /// stricter visual truth.
    static func renderedOnScreenWindowIDs() -> Set<CGWindowID>? {
        guard let rows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        return Set(rows.compactMap { row in
            (row[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
        })
    }

    /// Screen-coordinate frame for a single window ID, or `nil` if unreadable.
    static func frame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect)
        guard result == .success else {
            return nil
        }
        return rect
    }

    /// Best menu-bar item window under a screen point (for cross-bar ⌘-drag hide).
    /// Uses an expanded vertical hit rect — menu extras are short and easy to miss.
    static func windowIDAtScreenPoint(_ point: CGPoint, verticalSlop: CGFloat = 12) -> CGWindowID? {
        let ids = onScreenMenuBarWindowIDs()
        var best: (CGWindowID, CGFloat)?
        for id in ids {
            guard var frame = frame(for: id) else { continue }
            frame = frame.insetBy(dx: -4, dy: -verticalSlop)
            guard frame.contains(point) else { continue }
            // Prefer the nearest midX (thin overlapping frames).
            let dist = abs(frame.midX - point.x) + abs(frame.midY - point.y) * 0.25
            if best == nil || dist < best!.1 {
                best = (id, dist)
            }
        }
        if best != nil { return best?.0 }

        // Fallback: nearest on-screen menu-bar window by X in the menu-bar band.
        var nearest: (CGWindowID, CGFloat)?
        for id in ids {
            guard let frame = frame(for: id) else { continue }
            let dx = abs(frame.midX - point.x)
            let dy = abs(frame.midY - point.y)
            guard dy < 40 else { continue }
            let score = dx + dy * 0.5
            if nearest == nil || score < nearest!.1 {
                nearest = (id, score)
            }
        }
        return nearest?.0
    }

    /// True when `point` is in the system menu-bar strip of `screen`.
    static func isInMenuBarBand(_ point: CGPoint, screen: CGRect, visible: CGRect) -> Bool {
        // Cocoa coords: menu bar sits above visibleFrame.maxY up to frame.maxY.
        point.y >= visible.maxY - 2 && point.y <= screen.maxY + 2
            && point.x >= screen.minX && point.x <= screen.maxX
    }
}
