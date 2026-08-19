import CoreGraphics
import Foundation

public enum MarkerGeometry {
    public static let minCollapseWidth: Double = 32.0
    public static let maxCollapseWidth: Double = 10000.0
    /// Menu extras live on the right half of a display. Anchors far outside the
    /// screen frame (e.g. −3.7k on a 1496-wide built-in) are corrupt placement.
    public static let markerOnScreenInset: Double = 1.0

    public struct Inputs {
        public var toggleX: Double?
        public var primaryX: Double?
        public var secondaryX: Double?
        public var alwaysHiddenEnabled: Bool

        public init(toggleX: Double?, primaryX: Double?, secondaryX: Double?, alwaysHiddenEnabled: Bool) {
            self.toggleX = toggleX
            self.primaryX = primaryX
            self.secondaryX = secondaryX
            self.alwaysHiddenEnabled = alwaysHiddenEnabled
        }
    }

    public static func isValidOrder(toggleX: Double?, primaryX: Double?, secondaryX: Double?, alwaysHiddenEnabled: Bool) -> Bool {
        guard let toggleX, let primaryX else {
            return false
        }

        if alwaysHiddenEnabled {
            guard let secondaryX else {
                return false
            }
            return secondaryX < primaryX && primaryX < toggleX
        }

        return primaryX < toggleX
    }

    /// True when a marker x sits inside the screen's horizontal range.
    public static func isMarkerOnScreen(
        _ x: Double?,
        screenMinX: Double,
        screenMaxX: Double
    ) -> Bool {
        guard let x else { return false }
        return x >= screenMinX - markerOnScreenInset && x <= screenMaxX + markerOnScreenInset
    }

    /// All active markers must share the target screen. Off-screen autosave
    /// drift (live evidence: minX ≈ −3780 on a single 0…1496 display) is fail-closed.
    public static func markersOnScreen(
        toggleX: Double?,
        primaryX: Double?,
        secondaryX: Double?,
        alwaysHiddenEnabled: Bool,
        screenMinX: Double,
        screenMaxX: Double
    ) -> Bool {
        guard isMarkerOnScreen(toggleX, screenMinX: screenMinX, screenMaxX: screenMaxX),
            isMarkerOnScreen(primaryX, screenMinX: screenMinX, screenMaxX: screenMaxX)
        else {
            return false
        }
        if alwaysHiddenEnabled {
            return isMarkerOnScreen(secondaryX, screenMinX: screenMinX, screenMaxX: screenMaxX)
        }
        return true
    }

    public static func collapsedWidth(visibleFrameMaxX: Double?, primaryMinX: Double?) -> Double? {
        guard let visibleFrameMaxX, let primaryMinX else {
            return nil
        }
        let rawWidth = visibleFrameMaxX - primaryMinX
        guard rawWidth > 0 else {
            return nil
        }
        return max(minCollapseWidth, min(rawWidth, maxCollapseWidth))
    }

    /// Collapse width that also requires the primary divider to sit on the
    /// target screen so a negative off-screen primary cannot invent a multi-k
    /// spacer.
    public static func safeCollapsedWidth(
        visibleFrameMaxX: Double?,
        primaryMinX: Double?,
        screenMinX: Double?,
        screenMaxX: Double?
    ) -> Double? {
        guard let primaryMinX,
            let visibleFrameMaxX,
            let screenMinX,
            let screenMaxX
        else {
            return nil
        }
        guard isMarkerOnScreen(primaryMinX, screenMinX: screenMinX, screenMaxX: screenMaxX) else {
            return nil
        }
        // Primary must still be left of the visible right edge to grow a spacer.
        guard primaryMinX < visibleFrameMaxX else {
            return nil
        }
        guard let width = collapsedWidth(visibleFrameMaxX: visibleFrameMaxX, primaryMinX: primaryMinX) else {
            return nil
        }
        // Never inflate past the visible menu-bar width of this display.
        let visibleWidth = max(0, visibleFrameMaxX - screenMinX)
        guard visibleWidth > 0 else {
            return nil
        }
        return max(minCollapseWidth, min(width, visibleWidth))
    }

    /// Recover the divider's compact-position x coordinate even while its
    /// status item is acting as an inflated spacer. NSStatusItem keeps the
    /// item's right edge anchored as its length changes, so using the raw
    /// `frame.minX` on a second collapse compounds the previous width.
    public static func compactMinX(
        currentMinX: Double?,
        currentWidth: Double?,
        compactWidth: Double
    ) -> Double? {
        guard let currentMinX, let currentWidth,
            currentWidth >= 0, compactWidth >= 0
        else {
            return nil
        }
        return currentMinX + max(0, currentWidth - compactWidth)
    }

    public static func isReadyStatusItemAnchor(
        _ anchorX: Double?,
        screenMinX: Double,
        screenMidX: Double,
        screenMaxX: Double
    ) -> Bool {
        guard let anchorX else { return false }
        // Menu extras occupy the right half of each display. During launch,
        // AppKit can briefly report a small placeholder x that is technically
        // inside the screen but is not the restored menu-extra position yet.
        return anchorX > screenMidX && anchorX < screenMaxX - 1 && anchorX >= screenMinX
    }

    static func shouldUseCompactFallback(
        revealsBelowMenuBar: Bool,
        collapseHidItems: Bool?
    ) -> Bool {
        revealsBelowMenuBar && collapseHidItems == false
    }

    public static func preferredVisibleFrameMaxX(
        primaryMinX: Double?,
        preferredVisibleFrameMaxX: [Double?],
        fallbackVisibleFrameMaxX: [Double]
    ) -> Double? {
        guard let primaryMinX else {
            return nil
        }

        for candidate in preferredVisibleFrameMaxX {
            guard let candidate else {
                continue
            }
            if collapsedWidth(visibleFrameMaxX: candidate, primaryMinX: primaryMinX) != nil {
                return candidate
            }
        }

        return
            fallbackVisibleFrameMaxX
            .filter { collapsedWidth(visibleFrameMaxX: $0, primaryMinX: primaryMinX) != nil }
            .max()
    }

    public static func menuBarBand(frame: CGRect, visibleFrame: CGRect) -> CGRect {
        let menuBarHeight = max(0, frame.maxY - visibleFrame.maxY)
        guard menuBarHeight > 0 else {
            return .null
        }
        return CGRect(
            x: frame.minX,
            y: visibleFrame.maxY,
            width: frame.width,
            height: menuBarHeight
        )
    }

    public static func isPointInMenuBarBand(_ point: CGPoint, frame: CGRect, visibleFrame: CGRect) -> Bool {
        menuBarBand(frame: frame, visibleFrame: visibleFrame).contains(point)
    }
}

// MARK: - Collapse planner (pure)

/// Inputs for a pure collapse decision — no AppKit.
struct MenuBarCollapseInputs: Equatable, Sendable {
    var toggleX: Double?
    var primaryX: Double?
    var secondaryX: Double?
    var alwaysHiddenEnabled: Bool
    var screenMinX: Double?
    var screenMaxX: Double?
    var screenVisibleMaxX: Double?
    var hideableItemCount: Int
    var revealsBelowMenuBar: Bool
    /// Sticky only after a *verified spacer failure* on this display — not a
    /// global lastCollapseHidItems latch (that deadlocked spacer recovery).
    var spacerStickyOnDisplay: Bool
    var primaryExpandedLength: Double
    var secondaryExpandedLength: Double
}

enum MenuBarCollapseAssessment: Equatable, Sendable {
    /// Inflate spacer; verify async that items moved past the edge.
    case trySpacer(MenuBarCollapsePlan)
    /// Move hidden-lane items past the visible edge (collapse-time placement).
    /// Markers stay compact — no blank multi-k spacer.
    case tryPlacement(MenuBarCollapsePlan)
    /// Stay expanded; surface a typed repair reason. Never claims collapsed.
    case reject(MenuBarCollapseFailure)
}

enum MenuBarCollapsePlanner {
    /// Decide how collapse should hide items. Never accepts a "compact success"
    /// that leaves hideable items visible — that was the notch product bug.
    static func assess(_ inputs: MenuBarCollapseInputs) -> MenuBarCollapseAssessment {
        let orderValid = MarkerGeometry.isValidOrder(
            toggleX: inputs.toggleX,
            primaryX: inputs.primaryX,
            secondaryX: inputs.secondaryX,
            alwaysHiddenEnabled: inputs.alwaysHiddenEnabled
        )
        guard orderValid else {
            return .reject(.invalidMarkerOrder)
        }

        guard
            let screenMinX = inputs.screenMinX,
            let screenMaxX = inputs.screenMaxX,
            let screenVisibleMaxX = inputs.screenVisibleMaxX
        else {
            return .reject(.unreadableGeometry)
        }

        let onScreen = MarkerGeometry.markersOnScreen(
            toggleX: inputs.toggleX,
            primaryX: inputs.primaryX,
            secondaryX: inputs.secondaryX,
            alwaysHiddenEnabled: inputs.alwaysHiddenEnabled,
            screenMinX: screenMinX,
            screenMaxX: screenMaxX
        )
        guard onScreen else {
            return .reject(.markersOffScreen)
        }

        guard inputs.hideableItemCount > 0 else {
            return .reject(.nothingToHide)
        }

        // Ice hides sections by expanding its divider on every display,
        // including notched MacBooks. The below-menu-bar panel is the reveal
        // surface, not a reason to bypass the proven hide mechanism.
        let spacerAllowed = !inputs.spacerStickyOnDisplay
        if spacerAllowed,
            let collapseWidth = MarkerGeometry.safeCollapsedWidth(
                visibleFrameMaxX: screenVisibleMaxX,
                primaryMinX: inputs.primaryX,
                screenMinX: screenMinX,
                screenMaxX: screenMaxX
            )
        {
            return .trySpacer(
                MenuBarCollapsePlan(
                    primaryLength: collapseWidth,
                    secondaryLength: inputs.secondaryExpandedLength,
                    useCompactFallback: false,
                    toggleMinX: inputs.toggleX,
                    targetDisplayID: nil,
                    hideMechanism: .spacer
                )
            )
        }

        // Absolute cursor parking is not a dependable hide mechanism and would
        // violate movement opt-in. If the spacer cannot be proven on a display,
        // remain expanded and report the capability failure.
        return .reject(.hideUnavailable)
    }
}

// MARK: - Spacer verification (pure)

struct MenuBarSpacerVisibilitySample: Equatable, Sendable {
    var windowID: UInt32
    var isOnScreen: Bool
}

enum MenuBarSpacerVerifier {
    /// IDs still visible after a spacer transition. A missing window is not
    /// visible (the owner may have quit during the bounded verification delay).
    static func unhiddenIDs(
        samples: [MenuBarSpacerVisibilitySample],
        planned: [UInt32]
    ) -> [UInt32] {
        let byID = Dictionary(uniqueKeysWithValues: samples.map { ($0.windowID, $0.isOnScreen) })
        return planned.filter { byID[$0] == true }
    }

    static func allHidden(
        samples: [MenuBarSpacerVisibilitySample],
        planned: [UInt32]
    ) -> Bool {
        !planned.isEmpty && unhiddenIDs(samples: samples, planned: planned).isEmpty
    }
}

// MARK: - Accessibility gate (pure)

/// When the product may attempt placement hide / when to prompt for trust.
/// Pure so tests cover fail-closed gates without AppKit/TCC.
enum AccessibilityGatePolicy {
    /// Placement park/restore needs Accessibility.
    static func canAttemptPlacementHide(trusted: Bool) -> Bool {
        trusted
    }

    /// Prompt at most once per process session when collapse is blocked by AX.
    static func shouldPromptOnCollapseRejection(
        trusted: Bool,
        alreadyPromptedThisSession: Bool
    ) -> Bool {
        !trusted && !alreadyPromptedThisSession
    }

    /// Soft prompt path for cold launch enroll without modal (TCC row only).
    static func shouldEnrollQuietlyOnLaunch(trusted: Bool) -> Bool {
        !trusted
    }
}

// MARK: - Park restore queue (pure)

/// Serializes expand/restore ownership so concurrent Tasks cannot drop parks.
struct ParkRestoreQueue: Equatable, Sendable {
    private(set) var pending: [UInt32] = []

    var isEmpty: Bool { pending.isEmpty }

    mutating func enqueue(_ ids: [UInt32]) {
        for id in ids where !pending.contains(id) {
            pending.append(id)
        }
    }

    /// Take all pending IDs for a drain attempt (queue empty until requeue).
    mutating func takeAll() -> [UInt32] {
        let ids = pending
        pending = []
        return ids
    }

    /// Re-queue IDs that could not be restored (e.g. AX missing mid-drain).
    mutating func requeue(_ ids: [UInt32]) {
        enqueue(ids)
    }

    static func canDrain(accessibilityTrusted: Bool, pendingCount: Int) -> Bool {
        accessibilityTrusted && pendingCount > 0
    }
}

// MARK: - Park restore drain policy (pure)

/// Decisions for the restore-drain adapter (HB-002/003 skeptic fixes).
///
/// Rules:
/// - AX-denied / no-anchor → requeue **entire** batch, **do not** auto-reschedule
///   (avoids infinite Task thrash while queue stays non-empty).
/// - Cancel mid-batch → requeue **unmoved** remainder (never drop parks).
/// - Per-item move failure → requeue that id (and any not-yet-attempted if policy says so).
/// - Auto-reschedule only when pending work exists **and** last outcome was not a
///   hard deferral (new enqueues during a successful drain, or explicit retry).
enum ParkRestoreDrainPolicy {
    enum DeferredReason: String, Equatable, Sendable {
        case accessibilityRequired
        case noAnchor
    }

    enum Preflight: Equatable, Sendable {
        case empty
        case ready
        case deferred(DeferredReason)
    }

    /// Result of one drain attempt over a taken batch.
    struct Outcome: Equatable, Sendable {
        /// IDs that must remain pending (failed / cancelled / deferred).
        var requeue: [UInt32]
        /// When false, adapter must leave work pending until AX/anchor/explicit retry.
        var allowAutoReschedule: Bool
        var deferred: DeferredReason?
        var restoredCount: Int

        static func deferred(batch: [UInt32], reason: DeferredReason) -> Outcome {
            Outcome(requeue: batch, allowAutoReschedule: false, deferred: reason, restoredCount: 0)
        }

        static func cancelled(unmoved: [UInt32], restoredCount: Int) -> Outcome {
            Outcome(
                requeue: unmoved,
                allowAutoReschedule: false,
                deferred: nil,
                restoredCount: restoredCount
            )
        }

        static func finished(failed: [UInt32], restoredCount: Int) -> Outcome {
            // Failed moves stay pending for **explicit** retry — no busy loop.
            Outcome(
                requeue: failed,
                allowAutoReschedule: false,
                deferred: nil,
                restoredCount: restoredCount
            )
        }

        static func allRestored(count: Int) -> Outcome {
            Outcome(requeue: [], allowAutoReschedule: true, deferred: nil, restoredCount: count)
        }
    }

    static func preflight(
        batchCount: Int,
        accessibilityTrusted: Bool,
        hasAnchor: Bool
    ) -> Preflight {
        guard batchCount > 0 else { return .empty }
        guard accessibilityTrusted else { return .deferred(.accessibilityRequired) }
        guard hasAnchor else { return .deferred(.noAnchor) }
        return .ready
    }

    /// After takeAll: apply preflight (may requeue whole batch without moving).
    static func outcomeForPreflight(_ preflight: Preflight, batch: [UInt32]) -> Outcome? {
        switch preflight {
        case .empty:
            return Outcome(requeue: [], allowAutoReschedule: false, deferred: nil, restoredCount: 0)
        case .ready:
            return nil  // proceed to move loop
        case .deferred(let reason):
            return .deferred(batch: batch, reason: reason)
        }
    }

    /// Split a batch after sequential attempts: `attempted` prefix was tried;
    /// `succeeded` subset restored; if `cancelled`, everything not succeeded requeues.
    static func outcomeAfterMoves(
        batch: [UInt32],
        /// Indices into `batch` that completed successfully (order preserved).
        succeededIndices: Set<Int>,
        /// True if Task/session cancelled before finishing the batch.
        cancelled: Bool
    ) -> Outcome {
        var failedOrUnmoved: [UInt32] = []
        var restored = 0
        for (idx, id) in batch.enumerated() {
            if succeededIndices.contains(idx) {
                restored += 1
            } else {
                failedOrUnmoved.append(id)
            }
        }
        if cancelled {
            return .cancelled(unmoved: failedOrUnmoved, restoredCount: restored)
        }
        if failedOrUnmoved.isEmpty {
            return .allRestored(count: restored)
        }
        return .finished(failed: failedOrUnmoved, restoredCount: restored)
    }

    /// Whether the adapter may start another drain Task automatically.
    ///
    /// - Deferred outcomes never auto-loop (AX/anchor stay broken).
    /// - After full success, auto-reschedule only if new pending arrived.
    /// - After partial failure/cancel, never auto-loop (explicit retry / new enqueue).
    static func shouldAutoReschedule(
        outcome: Outcome,
        queueHasPending: Bool
    ) -> Bool {
        guard queueHasPending else { return false }
        guard outcome.allowAutoReschedule else { return false }
        guard outcome.deferred == nil else { return false }
        return true
    }

    /// Explicit user/system retry reasons always allowed to schedule even if last was deferred.
    static func isExplicitRetryReason(_ reason: String) -> Bool {
        switch reason {
        case "menu_retry",
            "after_accessibility_prompt",
            "expand_restore",
            "expand_restore_pending",
            "session_restore":
            return true
        default:
            // restore_coalesce only OK when not deferred — handled by allowAutoReschedule
            return false
        }
    }

    /// May we start a drain for this reason given deferred latch?
    static func mayStartDrain(
        reason: String,
        queueHasPending: Bool,
        isDeferredLatched: Bool,
        workerAlreadyRunning: Bool
    ) -> Bool {
        guard queueHasPending, !workerAlreadyRunning else { return false }
        if isDeferredLatched {
            return isExplicitRetryReason(reason)
        }
        return true
    }
}

// MARK: - Collapse hide candidates (pure)

struct MenuBarCollapseHideCandidate: Equatable, Sendable {
    var windowID: UInt32
    var midX: Double
    var isMovable: Bool
}

struct MenuBarCollapseHidePlan: Equatable, Sendable {
    /// Movable hidden-lane items, left→right, to park past the visible edge.
    var windowIDs: [UInt32]
    /// Destination x past which an item is considered hidden.
    var parkPastX: Double
    var parkY: Double
}

enum MenuBarCollapseHidePlanner {
    /// Select movable items in the hidden / always-hidden lanes for off-edge park.
    static func plan(
        candidates: [MenuBarCollapseHideCandidate],
        laneBounds: MenuBarLaneBounds,
        visibleMaxX: Double,
        parkY: Double
    ) -> MenuBarCollapseHidePlan {
        let movable =
            candidates
            .filter(\.isMovable)
            .filter { laneBounds.isRevealCandidate(itemMinX: $0.midX, itemMaxX: $0.midX, itemMidX: $0.midX) }
            .sorted { $0.midX < $1.midX }
            .map(\.windowID)
        // Park well past the visible edge — tiny offsets were easy for WindowServer
        // to "succeed" without a durable off-screen settle.
        return MenuBarCollapseHidePlan(
            windowIDs: movable,
            parkPastX: visibleMaxX + 36,
            parkY: parkY
        )
    }

    /// True when **every** planned window sits past the visible edge (with a small
    /// slop for frame quantization). Partial park is not success — leftover
    /// on-screen hideables violate AC1.
    static func allParkedPastEdge(
        frames: [(windowID: UInt32, minX: Double)],
        planned: [UInt32],
        visibleMaxX: Double,
        slop: Double = 6
    ) -> Bool {
        guard !planned.isEmpty else { return false }
        let byID = Dictionary(uniqueKeysWithValues: frames.map { ($0.windowID, $0.minX) })
        return planned.allSatisfy { id in
            guard let minX = byID[id] else { return false }
            return minX >= visibleMaxX - slop
        }
    }

    /// Planned IDs still on-screen (missing frame or minX left of visible edge − slop).
    static func unparkedIDs(
        frames: [(windowID: UInt32, minX: Double)],
        planned: [UInt32],
        visibleMaxX: Double,
        slop: Double = 6
    ) -> [UInt32] {
        let byID = Dictionary(uniqueKeysWithValues: frames.map { ($0.windowID, $0.minX) })
        return planned.filter { id in
            guard let minX = byID[id] else { return true }
            return minX < visibleMaxX - slop
        }
    }
}

// MARK: - Section lane model (pure)

/// Ice-style lanes derived from control markers. Pure so panel + scanner share
/// one definition of "hidden".
enum MenuBarSectionLane: String, Equatable, Sendable {
    case alwaysHidden
    case hidden
    case visible
    case control
}

struct MenuBarLaneBounds: Equatable, Sendable {
    var toggleX: Double?
    var primaryX: Double?
    var secondaryX: Double?
    var alwaysHiddenEnabled: Bool
    var screenMinX: Double?
    var screenMaxX: Double?

    var geometryUsable: Bool {
        guard let screenMinX, let screenMaxX else { return false }
        return MarkerGeometry.isValidOrder(
            toggleX: toggleX,
            primaryX: primaryX,
            secondaryX: secondaryX,
            alwaysHiddenEnabled: alwaysHiddenEnabled
        )
            && MarkerGeometry.markersOnScreen(
                toggleX: toggleX,
                primaryX: primaryX,
                secondaryX: secondaryX,
                alwaysHiddenEnabled: alwaysHiddenEnabled,
                screenMinX: screenMinX,
                screenMaxX: screenMaxX
            )
    }

    func lane(forItemMidX midX: Double) -> MenuBarSectionLane {
        guard geometryUsable, let toggleX, let primaryX else {
            // Unusable markers: treat nothing as "hidden by lane" so callers
            // can fall back to repair or a full on-screen browse list.
            return .visible
        }
        if alwaysHiddenEnabled, let secondaryX, midX < secondaryX {
            return .alwaysHidden
        }
        // Hidden section lives between the primary divider and the toggle.
        if midX < toggleX && midX >= primaryX {
            return .hidden
        }
        // Items fully left of primary (no always-hidden lane) are also "to hide".
        if midX < primaryX {
            return alwaysHiddenEnabled ? .alwaysHidden : .hidden
        }
        return .visible
    }

    /// Whether an item frame belongs in the reveal panel.
    func isRevealCandidate(itemMinX: Double, itemMaxX: Double, itemMidX: Double) -> Bool {
        switch lane(forItemMidX: itemMidX) {
        case .hidden, .alwaysHidden:
            return true
        case .visible, .control:
            // Classic fallback: fully left of toggle (spacer-era hideable set).
            if geometryUsable, let toggleX {
                return itemMaxX <= toggleX
            }
            return false
        }
    }
}
