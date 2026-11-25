import AppKit
import CoreGraphics
import Foundation

/// Reads the real menu bar via the window server and answers the questions the
/// spacer-collapse mechanism actually needs: how many items exist, where the
/// leftmost one starts, and whether a collapse genuinely pushed items off the
/// visible edge.
///
/// This is the capability Ice has and the classic Hidden Bar trick lacks. We use
/// it read-only — to make collapse decisions from ground truth instead of from
/// our own NSStatusItem window frames, which lag and misreport under the notch.
enum MenuBarItemScanner {
    struct Item: Equatable, Sendable {
        var windowID: CGWindowID
        var frame: CGRect
    }

    struct Scan: Equatable, Sendable {
        /// All on-screen menu bar items on the target screen, sorted left→right.
        var items: [Item]
        /// Items whose right edge sits left of the toggle (candidates to hide).
        var hideableItemCount: Int
        /// Minimum x of the leftmost item, in screen coordinates.
        var leftmostMinX: Double?
        /// True when the target screen has a notch (safe-area inset at top).
        var hasNotch: Bool
        /// Legacy placement observation: at least one item is parked past the
        /// visible right edge. Spacer collapse is verified by exact rendered
        /// window IDs instead.
        var anyItemHiddenPastEdge: Bool
    }

    // MARK: Live scan

    /// Enumerate the real menu bar items intersecting `screen`.
    @MainActor
    static func scan(screen: NSScreen, toggleMinX: Double?) -> Scan {
        let screenFrame = screen.frame
        let visibleMaxX = Double(screen.visibleFrame.maxX)
        let primaryMaxY = Double(NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY)
        let menuBarHeight = Double(max(screenFrame.maxY - screen.visibleFrame.maxY, 32))
        let rawItems: [Item] = MenuBarBridging.onScreenMenuBarWindowIDs().compactMap { windowID in
            guard let frame = MenuBarBridging.frame(for: windowID) else {
                return nil
            }
            guard Self.belongsToScreen(
                frame: frame,
                screenFrame: screenFrame,
                primaryScreenMaxY: primaryMaxY,
                menuBarHeight: menuBarHeight,
                includeParkedPastEdge: false,
                visibleMaxX: visibleMaxX
            ) else {
                return nil
            }
            return Item(windowID: windowID, frame: frame)
        }
        return summarize(
            items: rawItems,
            toggleMinX: toggleMinX,
            visibleMaxX: visibleMaxX,
            hasNotch: screenHasNotch(screen)
        )
    }

    @MainActor
    static func screenHasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Enriched scan: menu bar items for `screen` with owner app, title, and
    /// identity, sorted left→right. Includes items parked past the visible right
    /// edge (collapse-time placement hide) so the reveal panel can reach them.
    @MainActor
    static func detailedItems(screen: NSScreen, includeParkedPastEdge: Bool = true) -> [MenuBarWindowInfo] {
        let screenFrame = screen.frame
        let visibleMaxX = Double(screen.visibleFrame.maxX)
        let primaryMaxY = Double(NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY)
        let menuBarHeight = Double(max(screenFrame.maxY - screen.visibleFrame.maxY, 32))
        // Prefer full menu-bar list when we need parked (off-edge) items.
        let ids =
            includeParkedPastEdge
            ? MenuBarBridging.allMenuBarWindowIDs()
            : MenuBarBridging.onScreenMenuBarWindowIDs()
        return
            ids
            .compactMap { MenuBarWindowInfo.read(windowID: $0) }
            .filter { info in
                guard !info.isMenuBarBackdrop else {
                    return false
                }
                return Self.belongsToScreen(
                    frame: info.frame,
                    screenFrame: screenFrame,
                    primaryScreenMaxY: primaryMaxY,
                    menuBarHeight: menuBarHeight,
                    includeParkedPastEdge: includeParkedPastEdge,
                    visibleMaxX: visibleMaxX
                )
            }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Pure screen-membership filter for CGS top-left global coordinates.
    ///
    /// Rejects zero-sized macOS 26 Tahoe Control Center placeholder windows
    /// (`0x0`) and checks the flipped Quartz Y band so vertically stacked
    /// displays with overlapping X ranges never leak items across screens.
    static func belongsToScreen(
        frame: CGRect,
        screenFrame: CGRect,
        primaryScreenMaxY: Double,
        menuBarHeight: Double,
        includeParkedPastEdge: Bool,
        visibleMaxX: Double
    ) -> Bool {
        guard frame.width >= 1, frame.height >= 1 else {
            return false
        }
        let quartzTopY = primaryScreenMaxY - Double(screenFrame.maxY)
        let bandHeight = max(menuBarHeight, 44)
        let midY = Double(frame.midY)
        guard midY >= quartzTopY - 4, midY <= quartzTopY + bandHeight + 8 else {
            return false
        }
        let midX = Double(frame.midX)
        if midX >= Double(screenFrame.minX), midX <= Double(screenFrame.maxX) {
            return true
        }
        // Parked past the right edge of this display's menu bar.
        if includeParkedPastEdge, Double(frame.minX) >= visibleMaxX - 1 {
            return true
        }
        return false
    }

    // MARK: Pure core (unit-testable)

    /// Build a `Scan` from raw item frames. Pure so tests can exercise the
    /// notch / hide-detection logic without a live window server.
    static func summarize(
        items rawItems: [Item],
        toggleMinX: Double?,
        visibleMaxX: Double?,
        hasNotch: Bool
    ) -> Scan {
        let sorted = rawItems.sorted { $0.frame.minX < $1.frame.minX }
        let leftmost = sorted.first.map { Double($0.frame.minX) }

        let hideable = sorted.filter { item in
            guard let toggleMinX else {
                return false
            }
            return Double(item.frame.maxX) <= toggleMinX
        }

        // Explicit placement may park an item past the visible right edge.
        // Spacer collapse moves the lane left/off-screen and is intentionally
        // verified elsewhere using the pre-transition rendered window IDs.
        let anyHidden: Bool = {
            guard let visibleMaxX else {
                return false
            }
            return sorted.contains { Double($0.frame.minX) >= visibleMaxX }
        }()

        return Scan(
            items: sorted,
            hideableItemCount: hideable.count,
            leftmostMinX: leftmost,
            hasNotch: hasNotch,
            anyItemHiddenPastEdge: anyHidden
        )
    }
}
