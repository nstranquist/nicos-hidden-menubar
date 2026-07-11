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

    /// Window IDs for every menu bar item currently on screen.
    static func onScreenMenuBarWindowIDs() -> [CGWindowID] {
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
        let menuBarIDs = Array(menuBarList[..<Int(menuBarRealCount)])

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

    /// Screen-coordinate frame for a single window ID, or `nil` if unreadable.
    static func frame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect)
        guard result == .success else {
            return nil
        }
        return rect
    }
}
