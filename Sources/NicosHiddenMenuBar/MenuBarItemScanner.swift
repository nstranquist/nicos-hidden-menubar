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
        /// True when at least one hideable item is fully past the visible right
        /// edge — i.e. a collapse actually hid something.
        var anyItemHiddenPastEdge: Bool
    }

    // MARK: Live scan

    /// Enumerate the real menu bar items intersecting `screen`.
    @MainActor
    static func scan(screen: NSScreen, toggleMinX: Double?) -> Scan {
        let screenFrame = screen.frame
        let visibleMaxX = Double(screen.visibleFrame.maxX)
        let rawItems: [Item] = MenuBarBridging.onScreenMenuBarWindowIDs().compactMap { windowID in
            guard let frame = MenuBarBridging.frame(for: windowID) else {
                return nil
            }
            // CGS frames are in flipped (top-left origin) global space; only the x
            // axis matters for our left/right reasoning, and it lines up with
            // NSScreen.frame x. Keep items that horizontally belong to this screen.
            guard frame.midX >= screenFrame.minX, frame.midX <= screenFrame.maxX else {
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

    /// Enriched scan: every on-screen menu bar item on `screen` with owner app,
    /// title, and identity, sorted left→right. Feeds the IceBar, search, and the
    /// section model. Read-only.
    @MainActor
    static func detailedItems(screen: NSScreen) -> [MenuBarWindowInfo] {
        let screenFrame = screen.frame
        return MenuBarBridging.onScreenMenuBarWindowIDs()
            .compactMap { MenuBarWindowInfo.read(windowID: $0) }
            .filter { $0.frame.midX >= screenFrame.minX && $0.frame.midX <= screenFrame.maxX }
            .sorted { $0.frame.minX < $1.frame.minX }
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

        // After a collapse the spacer shoves hidden items rightward, past the
        // visible edge — so check every item, not just the pre-collapse hideable
        // subset (those items are no longer left of the toggle once pushed out).
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
