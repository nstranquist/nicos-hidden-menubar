import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class StatusSectionController: NSObject {
    private static let deferredCollapseRetryDelay: TimeInterval = 0.75

    private let preferencesStore: PreferencesStore
    private let profileStore: ProfileStore
    private let services: MenuBarServices
    private let openSettings: () -> Void
    private let openDiagnostics: () -> Void
    private let openOnboarding: () -> Void

    private var toggleItem: NSStatusItem
    private var primarySeparatorItem: NSStatusItem
    private var secondarySeparatorItem: NSStatusItem
    private let contextMenu = NSMenu()
    private var didAttemptMarkerAutoRepair = false

    private var stateMachine = MenuBarStateMachine()
    private var toggleState: MenuBarSectionMode { stateMachine.state.mode }
    private var lastToggleAt = Date.distantPast
    private var lastScan: MenuBarDiscoverySnapshot?
    private lazy var revealPanel = RevealPanel(
        discovery: services.discovery,
        capture: services.capture,
        onActivate: { [weak self] windowID in
            self?.activateHiddenItem(windowID)
        },
        onReorder: { [weak self] draggedID, beforeID in
            self?.applyRevealPanelReorder(draggedID: draggedID, beforeID: beforeID)
        },
        onUnhide: { [weak self] windowID, completion in
            self?.applyRevealPanelUnhide(windowID: windowID, completion: completion)
                ?? completion(false)
        },
        onHideFromMenuBar: { [weak self] windowID in
            self?.applyRevealPanelHideFromMenuBar(windowID: windowID)
        },
        onOpenSettings: { [weak self] in
            self?.openSettingsFromPanel()
        },
        onPerformance: { [weak self] sample in
            self?.preferencesStore.recordRevealPerformance(sample)
        }
    )
    private var autoCollapseWorkItem: DispatchWorkItem?
    private var revealWorkItem: DispatchWorkItem?
    private var geometryRefreshWorkItem: DispatchWorkItem?
    /// Displays where spacer hide was *verified* to hide nothing — sticky until repair.
    private var spacerStickyDisplayIDs: Set<CGDirectDisplayID> = []
    /// Pure ownership machine for collapse-time placement hide (AC1 atomicity).
    private var placementHideSession = PlacementHideSession()
    /// Committed parked IDs (only set via session `.commitCollapse` effect).
    private var parkedHideWindowIDs: [CGWindowID] = []
    private var collapseHideTask: Task<Void, Never>?
    /// Serial restore of parks (HB-002/003 — no fire-and-forget races).
    private var parkRestoreQueue = ParkRestoreQueue()
    private var parkRestoreTask: Task<Void, Never>?
    /// When true, auto-drain is suppressed until explicit retry / AX grant (no thrash).
    private var parkRestoreDeferredLatched = false
    /// One AX prompt per process for collapse-reject (HB-001).
    private var didPromptAccessibilityThisSession = false
    private var cancellables: Set<AnyCancellable> = []
    /// Ice parity: while the user ⌘-drags in the system menu bar, keep markers
    /// revealed and do not re-apply collapse geometry mid-drag.
    private var isUserDraggingMenuBarItems = false
    private var userMenuBarDragGlobalMonitor: Any?
    private var userMenuBarDragLocalMonitor: Any?

    init(
        preferencesStore: PreferencesStore = .shared,
        profileStore: ProfileStore = .shared,
        services: MenuBarServices,
        openSettings: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void,
        openOnboarding: @escaping () -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.profileStore = profileStore
        self.services = services
        self.openSettings = openSettings
        self.openDiagnostics = openDiagnostics
        self.openOnboarding = openOnboarding
        // Seed control-item positions before creating the status items so macOS
        // restores a stable layout on first run, then persists user drags via
        // autosaveName (the position-persistence Ice relies on).
        ControlSection.allCases.forEach(StatusItemDefaults.seedIfNeeded)
        self.toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.primarySeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.secondarySeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.toggleItem.autosaveName = ControlSection.visible.autosaveName
        self.primarySeparatorItem.autosaveName = ControlSection.hidden.autosaveName
        self.secondarySeparatorItem.autosaveName = ControlSection.alwaysHidden.autosaveName
        super.init()

        configureStatusItems()
        configureMenu()
        bindConfig()
        applyCurrentConfiguration()
        installUserMenuBarCommandDragMonitors()
        record("status_items_configured")
    }

    func toggle() {
        guard Date().timeIntervalSince(lastToggleAt) >= 0.2 else {
            record("toggle_ignored", level: .debug, publicFields: ["reason": "debounce"])
            return
        }
        lastToggleAt = Date()
        record("toggle_requested")
        perform(stateMachine.handle(.toggleRequested))
    }

    /// User-facing reveal action. Below-menu-bar: **only** open/close the Reveal
    /// Panel — never run synthetic Cmd-drag placement hide on the click path.
    /// Those moves warp the real cursor (top of screen) and were glitching the pointer.
    /// Panel lists lane / parked items via discovery without parking on open.
    func toggleReveal() {
        let screen = revealTargetScreen()
        if shouldRevealBelowMenuBar(on: screen) {
            guard Date().timeIntervalSince(lastToggleAt) >= 0.2 else {
                record("reveal_ignored", level: .debug, publicFields: ["reason": "debounce"])
                return
            }
            lastToggleAt = Date()

            // Abort any in-flight park so a prior hide can't keep thrashing the cursor.
            cancelPlacementHide(rollback: true)
            MouseCursorBridge.forceRestore(to: MouseCursorBridge.location)

            // Second click while panel is open → dismiss.
            if revealPanel.isVisible {
                revealPanel.hide()
                record("reveal_panel_dismissed")
                preferencesStore.recordDogfoodRevealDismiss()
                return
            }

            openRevealPanel(on: screen)
            preferencesStore.recordDogfoodRevealOpen()
            record("reveal_panel_open_no_auto_park")
            if !PrivacyPermissions.isAccessibilityTrusted {
                revealPanel.presentStatus(PrivacyPermissions.untrustedUserHint)
            }
        } else {
            toggle()
        }
    }

    func expand() {
        perform(stateMachine.handle(.expandRequested))
    }

    /// Called when the app activates (e.g. returning from System Settings).
    /// Soft re-check AX; retry deferred restores; refresh chevron tint/menu.
    func accessibilityTrustMayHaveChanged() {
        let trusted = PrivacyPermissions.isAccessibilityTrusted
        if trusted {
            didPromptAccessibilityThisSession = false
            parkRestoreDeferredLatched = false
            scheduleParkRestoreDrain(reason: "after_accessibility_prompt")
        }
        configureMenu()
        updateToggleAppearance()
        record(
            "accessibility_trust_rechecked",
            level: .debug,
            publicFields: ["trusted": trusted ? "true" : "false"]
        )
        preferencesStore.recordDogfoodAccessibilitySample(trusted: trusted)
    }

    private func applyExpandedState() {
        autoCollapseWorkItem?.cancel()
        record("section_expanding")
        // Cancels in-flight placement session (restore owned parks) + committed parks.
        restoreParkedItems()
        applyExpandedLengths()
        updateToggleAppearance()
        configureMenu()
        let orderValid = currentMarkerOrderValid()
        preferencesStore.recordMarkerOrder(valid: orderValid)
        preferencesStore.recordGeometryReadable(
            orderValid,
            reason: orderValid ? nil : MenuBarCollapseFailure.markersOffScreen.rawValue
        )
        if !orderValid {
            scheduleMarkerRepair()
        }
        let profile = profileStore.activeProfile
        let shouldUseRegularActivation = preferencesStore.config.useRegularActivationOnExpand || profile.useRegularActivationOnExpand
        NSApplication.shared.setActivationPolicy(shouldUseRegularActivation ? .regular : .accessory)
        scheduleAutoCollapseIfNeeded()
    }

    @discardableResult
    func collapse(openPanelOnSuccess: Bool = false) -> Bool {
        let config = preferencesStore.config
        let geometrySnapshot = currentGeometrySnapshot()
        preferencesStore.recordGeometrySnapshot(geometrySnapshot)

        let targetScreen = toggleItem.button?.window?.screen ?? activeMouseScreen()
        let revealsBelow = shouldRevealBelowMenuBar(on: targetScreen)
        let screenMinX = asDouble(targetScreen?.frame.minX)
        let screenMaxX = asDouble(targetScreen?.frame.maxX)
        let screenVisibleMaxX = MarkerGeometry.preferredVisibleFrameMaxX(
            primaryMinX: geometrySnapshot.primaryMinX,
            preferredVisibleFrameMaxX: [
                geometrySnapshot.toggleScreenVisibleMaxX,
                geometrySnapshot.primaryScreenVisibleMaxX,
                geometrySnapshot.mouseScreenVisibleMaxX,
            ],
            fallbackVisibleFrameMaxX: geometrySnapshot.allScreenVisibleMaxX
        ) ?? asDouble(targetScreen?.visibleFrame.maxX)

        let inputs = MenuBarCollapseInputs(
            toggleX: geometrySnapshot.toggleMinX,
            primaryX: geometrySnapshot.primaryMinX,
            secondaryX: geometrySnapshot.secondaryMinX,
            alwaysHiddenEnabled: config.lanes.alwaysHiddenEnabled,
            screenMinX: screenMinX,
            screenMaxX: screenMaxX,
            screenVisibleMaxX: screenVisibleMaxX,
            hideableItemCount: geometrySnapshot.realHideableItemCount ?? 0,
            revealsBelowMenuBar: revealsBelow,
            spacerStickyOnDisplay: targetScreen.map { spacerStickyDisplayIDs.contains($0.displayID) } ?? false,
            primaryExpandedLength: Double(primaryExpandedLength(for: config)),
            secondaryExpandedLength: Double(secondaryExpandedLength(for: config))
        )

        switch MenuBarCollapsePlanner.assess(inputs) {
        case .reject(let failure):
            rejectCollapse(failure)
            return false

        case .trySpacer(var plan):
            preferencesStore.recordMarkerOrder(valid: true)
            preferencesStore.recordGeometryReadable(true)
            plan.targetDisplayID = targetScreen?.displayID
            plan.verificationWindowIDs = spacerVerificationWindowIDs(on: targetScreen)
            perform(stateMachine.handle(.collapseSucceeded(plan)))
            return true

        case .tryPlacement(var plan):
            plan.targetDisplayID = targetScreen?.displayID
            return beginPlacementHide(
                plan: plan,
                screen: targetScreen,
                visibleMaxX: screenVisibleMaxX,
                openPanelOnSuccess: openPanelOnSuccess
            )
        }
    }

    private func rejectCollapse(_ failure: MenuBarCollapseFailure) {
        // Geometry "needs repair" is only for real marker/geometry failures —
        // accessibility_required was polluting diagnostics (valid markers, AX off).
        let geometryFailure: Bool = {
            switch failure {
            case .invalidMarkerOrder, .markersOffScreen, .unreadableGeometry, .reconciliationFailed:
                return true
            case .accessibilityRequired, .nothingToHide, .hideUnavailable:
                return false
            }
        }()
        if geometryFailure {
            let orderLooksValid = failure != .invalidMarkerOrder && failure != .markersOffScreen
            preferencesStore.recordMarkerOrder(valid: orderLooksValid)
            preferencesStore.recordGeometryReadable(false, reason: failure.rawValue)
        } else if failure == .accessibilityRequired {
            // Keep last real geometry snapshot; surface AX separately in the menu.
            preferencesStore.recordGeometryReadable(
                currentMarkerOrderValid(),
                reason: nil
            )
        }
        preferencesStore.recordCollapseHidItems(false)
        record("collapse_rejected", level: .warning, publicFields: ["reason": failure.rawValue])
        if failure == .markersOffScreen {
            scheduleMarkerRepair()
        }
        if failure == .accessibilityRequired {
            // Soft guide once per session — no system modal spam on every click.
            if AccessibilityGatePolicy.shouldPromptOnCollapseRejection(
                trusted: PrivacyPermissions.isAccessibilityTrusted,
                alreadyPromptedThisSession: didPromptAccessibilityThisSession
            ) {
                didPromptAccessibilityThisSession = true
                PrivacyPermissions.guideToAccessibilitySettingsIfNeeded(openSettings: true)
            }
        }
        perform(stateMachine.handle(.collapseRejected(failure)))
        configureMenu()
        updateToggleAppearance()
    }

    /// Collapse-time placement hide — I/O adapter over pure `PlacementHideSession`.
    /// Commit only occurs via session `.commitCollapse` (full ownership + verify).
    @discardableResult
    private func beginPlacementHide(
        plan: MenuBarCollapsePlan,
        screen: NSScreen?,
        visibleMaxX: Double?,
        openPanelOnSuccess: Bool
    ) -> Bool {
        guard AccessibilityGatePolicy.canAttemptPlacementHide(
            trusted: PrivacyPermissions.isAccessibilityTrusted
        ) else {
            rejectCollapse(.accessibilityRequired)
            return false
        }
        guard let screen, let visibleMaxX else {
            rejectCollapse(.unreadableGeometry)
            return false
        }

        let bounds = currentLaneBounds(screen: screen)
        let discovered = services.discovery.discoverItems(on: MenuBarDisplayHandle(rawValue: screen.displayID))
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let controlWindowIDs = ownControlWindowIDs()
        let candidates = discovered.map { item in
            MenuBarCollapseHideCandidate(
                windowID: item.handle.windowID,
                midX: Double(item.frame.midX),
                isMovable: !MenuBarItemInfo(
                    namespace: item.identity.namespace,
                    title: item.title
                ).isLikelyImmovable
                    && item.ownerPID != ownPID
                    && !controlWindowIDs.contains(CGWindowID(item.handle.windowID))
            )
        }
        let hidePlan = MenuBarCollapseHidePlanner.plan(
            candidates: candidates,
            laneBounds: bounds,
            visibleMaxX: visibleMaxX,
            parkY: Double(screen.frame.maxY - 12)
        )

        // Cancel prior I/O task; session.start restores any owned parks.
        collapseHideTask?.cancel()
        collapseHideTask = nil
        applyPlacementHideTransition(
            placementHideSession.handle(.start(planned: hidePlan.windowIDs)),
            collapsePlan: plan,
            screen: screen,
            openPanelOnSuccess: false
        )
        guard placementHideSession.isActive else {
            // start rejected empty plan
            return false
        }

        preferencesStore.recordMarkerOrder(valid: true)
        preferencesStore.recordGeometryReadable(true)
        let generation = placementHideSession.generation
        record(
            "placement_hide_started",
            publicFields: [
                "count": String(hidePlan.windowIDs.count),
                "generation": String(generation),
            ]
        )
        preferencesStore.recordDogfoodHideStart()

        let toggleID = toggleItem.button?.window.map { CGWindowID($0.windowNumber) }
        // Prefer parking past the physical screen edge when larger than visibleMaxX.
        let parkX = max(hidePlan.parkPastX, Double(screen.frame.maxX) + 12)

        collapseHideTask = Task { [weak self] in
            guard let self else { return }
            var moved = 0
            var failed = 0
            for windowID in hidePlan.windowIDs {
                if Task.isCancelled {
                    // cancelPlacementHide already fed .cancel into the session.
                    return
                }
                let ok = await self.parkOneItemForHide(
                    windowID: windowID,
                    parkX: parkX,
                    parkY: hidePlan.parkY,
                    toggleID: toggleID
                )
                if !ok {
                    failed += 1
                    self.record(
                        "placement_hide_item_failed",
                        level: .warning,
                        publicFields: ["reason": "unobserved_after_retries"],
                        privateFields: ["window_id": String(windowID)]
                    )
                    await MainActor.run {
                        MouseCursorBridge.forceRestore(to: MouseCursorBridge.location)
                        self.preferencesStore.recordDogfoodHideOutcome(succeeded: false, reason: "item_unobserved")
                        self.applyPlacementHideTransition(
                            self.placementHideSession.handle(
                                .fail(reason: "item_move_failed", generation: generation)
                            ),
                            collapsePlan: plan,
                            screen: screen,
                            openPanelOnSuccess: openPanelOnSuccess
                        )
                    }
                    return
                }
                moved += 1
                // Always feed park through the session — even if cancelled mid-move.
                // Stale generation / cancelled phase → restore effect, never commit.
                await MainActor.run {
                    self.applyPlacementHideTransition(
                        self.placementHideSession.handle(
                            .parkRecorded(windowID: windowID, generation: generation)
                        ),
                        collapsePlan: plan,
                        screen: screen,
                        openPanelOnSuccess: false
                    )
                }
            }

            try? await Task.sleep(for: .milliseconds(280))

            let frames: [(windowID: UInt32, minX: Double)] = hidePlan.windowIDs.compactMap { id in
                guard let frame = MenuBarBridging.frame(for: id) else { return nil }
                return (id, Double(frame.minX))
            }
            let allHidden = MenuBarCollapseHidePlanner.allParkedPastEdge(
                frames: frames,
                planned: hidePlan.windowIDs,
                visibleMaxX: visibleMaxX
            )
            let stillVisible = MenuBarCollapseHidePlanner.unparkedIDs(
                frames: frames,
                planned: hidePlan.windowIDs,
                visibleMaxX: visibleMaxX
            )
            if !allHidden {
                self.record(
                    "placement_hide_failed",
                    level: .warning,
                    publicFields: [
                        "reason": "partial_or_unverified",
                        "unparked": String(stillVisible.count),
                        "moved": String(moved),
                        "failed": String(failed),
                    ]
                )
            }

            // Late cancel between verify compute and this hop: session returns noop.
            await MainActor.run {
                self.collapseHideTask = nil
                // Always free the cursor after a hide batch (success or fail).
                MouseCursorBridge.forceRestore(to: MouseCursorBridge.location)
                self.preferencesStore.recordDogfoodHideOutcome(
                    succeeded: allHidden,
                    reason: allHidden ? "verified" : "partial_or_unverified"
                )
                self.applyPlacementHideTransition(
                    self.placementHideSession.handle(
                        .verify(allHidden: allHidden, generation: generation)
                    ),
                    collapsePlan: plan,
                    screen: screen,
                    openPanelOnSuccess: openPanelOnSuccess
                )
            }
        }
        return true
    }

    /// Absolute park with stepped destinations. Relative left-of-toggle only when
    /// the item is currently in the visible lane (right of chevron).
    @MainActor
    private func parkOneItemForHide(
        windowID: CGWindowID,
        parkX: Double,
        parkY: Double,
        toggleID: CGWindowID?
    ) async -> Bool {
        // Single extra step only — multi-step parks were thrashing the real cursor.
        let parkTargets: [Double] = [parkX, parkX + 64]
        for x in parkTargets {
            do {
                try await MenuBarItemMover.move(
                    windowID: windowID,
                    to: .absolute(x: x, y: parkY),
                    enabled: true,
                    options: .placementHide
                )
                return true
            } catch {
                record(
                    "placement_hide_absolute_attempt",
                    level: .debug,
                    publicFields: ["reason": String(describing: error)]
                )
            }
        }
        // Visible-lane straggler: pull left of chevron first, then re-park absolute.
        if let toggleID,
           let itemFrame = MenuBarBridging.frame(for: windowID),
           let toggleFrame = MenuBarBridging.frame(for: toggleID),
           itemFrame.midX > toggleFrame.midX
        {
            try? await MenuBarItemMover.move(
                windowID: windowID,
                to: .leftOf(targetWindowID: toggleID),
                enabled: true,
                options: .placementHide
            )
            do {
                try await MenuBarItemMover.move(
                    windowID: windowID,
                    to: .absolute(x: parkTargets.last ?? parkX, y: parkY),
                    enabled: true,
                    options: .placementHide
                )
                return true
            } catch {
                return false
            }
        }
        return false
    }

    /// Apply pure session effects. Commit is only possible via `.commitCollapse`.
    private func applyPlacementHideTransition(
        _ transition: PlacementHideSession.Transition,
        collapsePlan: MenuBarCollapsePlan,
        screen: NSScreen?,
        openPanelOnSuccess: Bool
    ) {
        placementHideSession = transition.session
        for effect in transition.effects {
            switch effect {
            case .noop:
                continue
            case .restore(let ids):
                restoreWindowIDs(ids, reason: "session_restore")
            case .reject(let failure):
                preferencesStore.recordCollapseHidItems(false)
                record("placement_hide_failed", level: .warning, publicFields: ["reason": failure.rawValue])
                rejectCollapse(failure)
                // User-initiated reveal: hide failed after cursor warps — keep panel up.
                if openPanelOnSuccess {
                    openRevealPanel(on: screen)
                    revealPanel.presentStatus(
                        "Couldn’t fully hide extras (\(failure.rawValue)). Panel still open."
                    )
                }
            case .commitCollapse(let parked):
                // Session already enforced full ownership + not cancelled.
                guard !parked.isEmpty else {
                    // Empty commit is a bug in the reducer path — fail closed.
                    preferencesStore.recordCollapseHidItems(false)
                    rejectCollapse(.hideUnavailable)
                    if openPanelOnSuccess {
                        openRevealPanel(on: screen)
                    }
                    continue
                }
                parkedHideWindowIDs = parked
                preferencesStore.recordCollapseHidItems(true)
                var applied = collapsePlan
                applied.hideMechanism = .placement
                perform(stateMachine.handle(.collapseSucceeded(applied)))
                record(
                    "placement_hide_succeeded",
                    publicFields: ["parked": String(parked.count)]
                )
                // Always refresh/show when user asked for the panel (or it’s already open).
                if openPanelOnSuccess || revealPanel.isVisible {
                    openRevealPanel(on: screen)
                    revealPanel.presentStatus("Hidden \(parked.count) item(s).")
                }
            }
        }
    }

    /// Cancel in-flight placement I/O and feed `.cancel` into the pure session
    /// (ownership transfer + restore effects happen in the reducer).
    private func cancelPlacementHide(rollback: Bool) {
        let task = collapseHideTask
        collapseHideTask = nil
        task?.cancel()
        MouseCursorBridge.forceRestore(to: MouseCursorBridge.location)
        guard rollback else { return }
        applyPlacementHideTransition(
            placementHideSession.handle(.cancel),
            collapsePlan: MenuBarCollapsePlan(
                primaryLength: 8,
                secondaryLength: 0,
                useCompactFallback: true,
                toggleMinX: nil,
                targetDisplayID: nil,
                hideMechanism: .placement
            ),
            screen: nil,
            openPanelOnSuccess: false
        )
    }

    private func restoreParkedItems() {
        // Cancel any in-flight hide (session restores owned parks).
        cancelPlacementHide(rollback: true)
        let ids = parkedHideWindowIDs
        parkedHideWindowIDs = []
        guard !ids.isEmpty else {
            // Still drain any leftover pending queue from a prior failed restore.
            scheduleParkRestoreDrain(reason: "expand_restore_pending")
            return
        }
        enqueueParkRestore(ids, reason: "expand_restore")
    }

    private func restoreWindowIDs(_ ids: [CGWindowID], reason: String) {
        enqueueParkRestore(ids, reason: reason)
    }

    private func enqueueParkRestore(_ ids: [CGWindowID], reason: String) {
        guard !ids.isEmpty else { return }
        parkRestoreQueue.enqueue(ids.map { UInt32($0) })
        scheduleParkRestoreDrain(reason: reason)
    }

    private func scheduleParkRestoreDrain(reason: String) {
        let mayStart = ParkRestoreDrainPolicy.mayStartDrain(
            reason: reason,
            queueHasPending: !parkRestoreQueue.isEmpty,
            isDeferredLatched: parkRestoreDeferredLatched,
            workerAlreadyRunning: parkRestoreTask != nil
        )
        guard mayStart else { return }
        // Explicit retry clears the deferred latch so preflight can run again.
        if ParkRestoreDrainPolicy.isExplicitRetryReason(reason) {
            parkRestoreDeferredLatched = false
        }
        parkRestoreTask = Task { [weak self] in
            await self?.drainParkRestoreQueue(reason: reason)
        }
    }

    /// Adapter over pure `ParkRestoreDrainPolicy` — one taken batch per worker start.
    /// Deferred / cancel / move-fail requeue without auto-thrash.
    private func drainParkRestoreQueue(reason: String) async {
        let outcome: ParkRestoreDrainPolicy.Outcome = await performOneParkRestoreDrain(reason: reason)

        await MainActor.run {
            if !outcome.requeue.isEmpty {
                self.parkRestoreQueue.requeue(outcome.requeue)
            }
            if outcome.deferred != nil {
                self.parkRestoreDeferredLatched = true
            } else if outcome.requeue.isEmpty {
                self.parkRestoreDeferredLatched = false
            } else {
                // Partial failure: keep pending, no auto-loop.
                self.parkRestoreDeferredLatched = true
            }
            self.parkRestoreTask = nil

            if outcome.restoredCount > 0 {
                self.record(
                    "placement_hide_restored",
                    publicFields: [
                        "count": String(outcome.restoredCount),
                        "reason": reason,
                        "requeued": String(outcome.requeue.count),
                    ]
                )
            }
            if let deferred = outcome.deferred {
                self.record(
                    "placement_restore_deferred",
                    level: .warning,
                    publicFields: [
                        "reason": deferred.rawValue,
                        "count": String(outcome.requeue.count),
                        "origin": reason,
                    ]
                )
                if deferred == .accessibilityRequired,
                   AccessibilityGatePolicy.shouldPromptOnCollapseRejection(
                       trusted: PrivacyPermissions.isAccessibilityTrusted,
                       alreadyPromptedThisSession: self.didPromptAccessibilityThisSession
                   )
                {
                    self.didPromptAccessibilityThisSession = true
                    PrivacyPermissions.guideToAccessibilitySettingsIfNeeded(openSettings: true)
                }
            }

            // Only auto-reschedule when policy allows (new work after clean success).
            if ParkRestoreDrainPolicy.shouldAutoReschedule(
                outcome: outcome,
                queueHasPending: !self.parkRestoreQueue.isEmpty
            ) {
                self.scheduleParkRestoreDrain(reason: "restore_coalesce")
            }
        }
    }

    /// Single drain attempt: takeAll → preflight → moves with requeue remainder.
    private func performOneParkRestoreDrain(reason: String) async -> ParkRestoreDrainPolicy.Outcome {
        let batch: [UInt32] = await MainActor.run { self.parkRestoreQueue.takeAll() }
        let trusted = await MainActor.run { PrivacyPermissions.isAccessibilityTrusted }
        let anchorID: CGWindowID? = await MainActor.run {
            self.primarySeparatorItem.button?.window.map { CGWindowID($0.windowNumber) }
                ?? self.toggleItem.button?.window.map { CGWindowID($0.windowNumber) }
        }

        let preflight = ParkRestoreDrainPolicy.preflight(
            batchCount: batch.count,
            accessibilityTrusted: trusted,
            hasAnchor: anchorID != nil
        )
        if let early = ParkRestoreDrainPolicy.outcomeForPreflight(preflight, batch: batch) {
            return early
        }
        guard let primaryWindowID = anchorID else {
            // Defensive — preflight should have caught this.
            return .deferred(batch: batch, reason: .noAnchor)
        }

        var succeeded = Set<Int>()
        for (idx, windowID) in batch.enumerated() {
            if Task.isCancelled {
                return ParkRestoreDrainPolicy.outcomeAfterMoves(
                    batch: batch,
                    succeededIndices: succeeded,
                    cancelled: true
                )
            }
            do {
                try await MenuBarItemMover.move(
                    windowID: CGWindowID(windowID),
                    to: .leftOf(targetWindowID: primaryWindowID),
                    enabled: true
                )
                succeeded.insert(idx)
            } catch {
                // Leave this index out of succeeded → requeued by policy.
                await MainActor.run {
                    self.record(
                        "placement_restore_item_failed",
                        level: .warning,
                        publicFields: ["reason": String(describing: error)],
                        privateFields: ["window_id": String(windowID)]
                    )
                }
            }
        }
        return ParkRestoreDrainPolicy.outcomeAfterMoves(
            batch: batch,
            succeededIndices: succeeded,
            cancelled: false
        )
    }

    /// Reset corrupted preferred positions and recreate control status items so
    /// macOS places them back on the active menu bar.
    func repairMarkers() {
        record("marker_repair_requested")
        // Clear sticky spacer failure so inline can be retried after repair.
        spacerStickyDisplayIDs.removeAll()
        preferencesStore.recordCollapseHidItems(nil)
        StatusItemDefaults.resetAllToSeed()
        recreateStatusItems()
        applyExpandedLengths()
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
        let valid = currentMarkerOrderValid()
        preferencesStore.recordMarkerOrder(valid: valid)
        preferencesStore.recordGeometryReadable(valid, reason: valid ? nil : "markers_off_screen")
        record("marker_repair_completed", publicFields: ["order_valid": valid ? "true" : "false"])
    }

    private func scheduleMarkerRepair() {
        guard !didAttemptMarkerAutoRepair else { return }
        didAttemptMarkerAutoRepair = true
        DispatchQueue.main.async { [weak self] in
            self?.repairMarkers()
        }
    }

    private func recreateStatusItems() {
        NSStatusBar.system.removeStatusItem(toggleItem)
        NSStatusBar.system.removeStatusItem(primarySeparatorItem)
        NSStatusBar.system.removeStatusItem(secondarySeparatorItem)

        StatusItemDefaults.resetAllToSeed()

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        primarySeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        secondarySeparatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = ControlSection.visible.autosaveName
        primarySeparatorItem.autosaveName = ControlSection.hidden.autosaveName
        secondarySeparatorItem.autosaveName = ControlSection.alwaysHidden.autosaveName

        configureStatusItems()
        updateToggleAppearance()
        updateMarkerTitles()
        configureMenu()
    }

    private func applyCollapsedState(_ plan: MenuBarCollapsePlan) {
        autoCollapseWorkItem?.cancel()
        switch plan.hideMechanism {
        case .placement:
            record("section_collapsing_via_placement")
        case .spacer:
            record(plan.useCompactFallback ? "compact_notch_fallback_applied" : "section_collapsing")
        }
        primarySeparatorItem.length = CGFloat(plan.primaryLength)
        secondarySeparatorItem.length = CGFloat(plan.secondaryLength)
        updateMarkerTitles()
        updateToggleAppearance()
        configureMenu()
        NSApplication.shared.setActivationPolicy(.accessory)
        // Only spacer path needs async verification; placement already verified.
        if plan.hideMechanism == .spacer, !plan.useCompactFallback {
            let targetScreen = NSScreen.screens.first { $0.displayID == plan.targetDisplayID }
            scheduleCollapseVerification(
                windowIDs: plan.verificationWindowIDs,
                screen: targetScreen
            )
        }
    }

    /// After a spacer collapse, verify every item that was visibly in a hidden
    /// lane is now off-screen. On failure, stick spacer-off for this display
    /// and remain expanded (do not leave a blank spacer or a fake collapsed
    /// state).
    private func scheduleCollapseVerification(windowIDs: [UInt32], screen: NSScreen?) {
        let target = screen ?? activeMouseScreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.toggleState == .collapsed else { return }
            guard !windowIDs.isEmpty else {
                self.preferencesStore.recordCollapseHidItems(false)
                self.record(
                    "collapse_verification_failed",
                    level: .warning,
                    publicFields: [
                        "reason": "nothing_to_hide",
                        "notch": String(target.map(MenuBarItemScanner.screenHasNotch) ?? false),
                    ]
                )
                self.failSpacer(on: target)
                return
            }

            guard let onScreenIDs = MenuBarBridging.renderedOnScreenWindowIDs() else {
                self.preferencesStore.recordCollapseHidItems(false)
                self.record(
                    "collapse_verification_failed",
                    level: .warning,
                    publicFields: ["reason": MenuBarCollapseFailure.unreadableGeometry.rawValue]
                )
                self.failSpacer(on: target)
                return
            }
            let samples = windowIDs.map { windowID in
                MenuBarSpacerVisibilitySample(
                    windowID: windowID,
                    isOnScreen: onScreenIDs.contains(CGWindowID(windowID))
                )
            }
            let unhidden = MenuBarSpacerVerifier.unhiddenIDs(
                samples: samples,
                planned: windowIDs
            )
            let allHidden = MenuBarSpacerVerifier.allHidden(
                samples: samples,
                planned: windowIDs
            )
            self.preferencesStore.recordCollapseHidItems(allHidden)
            if allHidden {
                self.record(
                    "collapse_verification_succeeded",
                    publicFields: [
                        "hidden": String(windowIDs.count),
                        "mechanism": MenuBarHideMechanism.spacer.rawValue,
                    ]
                )
            } else {
                self.record(
                    "collapse_verification_failed",
                    level: .warning,
                    publicFields: [
                        "notch": String(target.map(MenuBarItemScanner.screenHasNotch) ?? false),
                        "unhidden": String(unhidden.count),
                        "unhidden_ids": unhidden.map(String.init).joined(separator: ","),
                    ]
                )
                self.failSpacer(on: target)
            }
        }
    }

    /// Snapshot only items that are both on-screen and assigned to a hidden
    /// lane. Items already obscured by the notch are not evidence that this
    /// spacer transition hid anything.
    private func spacerVerificationWindowIDs(on screen: NSScreen?) -> [UInt32] {
        guard let screen else { return [] }
        let bounds = currentLaneBounds(screen: screen)
        guard bounds.geometryUsable else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let controlWindowIDs = ownControlWindowIDs()
        guard let onScreenIDs = MenuBarBridging.renderedOnScreenWindowIDs() else {
            return []
        }
        return services.discovery
            .discoverItems(on: MenuBarDisplayHandle(rawValue: screen.displayID))
            .filter { item in
                guard item.ownerPID != ownPID else { return false }
                guard !controlWindowIDs.contains(CGWindowID(item.handle.windowID)) else {
                    return false
                }
                let lane = bounds.lane(forItemMidX: Double(item.frame.midX))
                guard lane == .hidden || lane == .alwaysHidden else { return false }
                return onScreenIDs.contains(CGWindowID(item.handle.windowID))
            }
            .map(\.handle.windowID)
    }

    private func ownControlWindowIDs() -> Set<CGWindowID> {
        Set([
            toggleItem.button?.window.map { CGWindowID($0.windowNumber) },
            primarySeparatorItem.button?.window.map { CGWindowID($0.windowNumber) },
            secondarySeparatorItem.button?.window.map { CGWindowID($0.windowNumber) },
        ].compactMap { $0 })
    }

    private func failSpacer(on target: NSScreen?) {
        if let target {
            spacerStickyDisplayIDs.insert(target.displayID)
        }
        record("ineffective_spacer_released")
        applyExpandedLengths()
        // Leave expanded machine state via repair. The next collapse rejects
        // fail-closed on this display until a fresh app session retries spacer.
        perform(stateMachine.handle(.collapseRejected(.hideUnavailable)))
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
    }

    /// Open the Reveal Panel of hidden items (always **show**, never toggle-off).
    func openRevealPanel() {
        openRevealPanel(on: revealTargetScreen())
    }

    func dismissRevealPanel() {
        guard revealPanel.isVisible else { return }
        revealPanel.hide()
        record("reveal_panel_dismissed", publicFields: ["source": "command"])
        preferencesStore.recordDogfoodRevealDismiss()
    }

    private func openRevealPanel(on screen: NSScreen?, retryCount: Int = 0) {
        guard let screen else { return }
        let anchor = asDouble(toggleItem.button?.window?.frame.midX)
        let screenMinX = Double(screen.frame.minX)
        let screenMidX = Double(screen.frame.midX)
        let screenMaxX = Double(screen.frame.maxX)
        let bounds = currentLaneBounds(screen: screen)
        // Off-screen markers never become "ready" anchors — repair and open
        // the panel against screen mid so the user still gets a reveal surface.
        if !bounds.geometryUsable {
            if !didAttemptMarkerAutoRepair {
                scheduleMarkerRepair()
            }
            record("reveal_panel_opening", publicFields: [
                "mode": "repair_fallback",
                "notch_support": preferencesStore.config.isNotchSupportEnabled ? "on" : "off",
            ])
            presentRevealPanel(
                near: Double(screen.frame.midX),
                on: screen,
                laneBounds: bounds,
                forceShow: true
            )
            return
        }
        let anchorIsReady = MarkerGeometry.isReadyStatusItemAnchor(
            anchor,
            screenMinX: screenMinX,
            screenMidX: screenMidX,
            screenMaxX: screenMaxX
        )
        guard anchorIsReady else {
            if retryCount < 8 {
                // Don't wait forever silently — show immediately at mid, then refine.
                if retryCount == 0 {
                    presentRevealPanel(
                        near: Double(screen.frame.midX),
                        on: screen,
                        laneBounds: bounds,
                        forceShow: true
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.openRevealPanel(on: self.revealTargetScreen(), retryCount: retryCount + 1)
                }
            } else {
                record("reveal_deferred", level: .warning, publicFields: ["reason": "anchor_not_ready"])
                presentRevealPanel(
                    near: Double(screen.frame.midX),
                    on: screen,
                    laneBounds: bounds,
                    forceShow: true
                )
            }
            return
        }
        record("reveal_panel_opening", publicFields: [
            "notch_support": preferencesStore.config.isNotchSupportEnabled ? "on" : "off",
            "has_notch_band": currentNotchGeometry(screen: screen) == nil ? "false" : "true",
        ])
        presentRevealPanel(near: anchor, on: screen, laneBounds: bounds, forceShow: true)
    }

    /// Apply a panel ⌘-drag reorder to the live menu bar (Cmd-drag park path).
    /// Panel order is already updated by `RevealPanelModel.reorder` before this runs.
    private func applyRevealPanelReorder(draggedID: CGWindowID, beforeID: CGWindowID?) {
        guard PrivacyPermissions.isAccessibilityTrusted else {
            revealPanel.presentStatus("Panel order updated. Enable Accessibility to move the real menu bar icons.")
            return
        }
        record(
            "reveal_panel_reorder",
            publicFields: [
                "has_before": beforeID == nil ? "false" : "true",
            ],
            privateFields: [
                "dragged": String(draggedID),
                "before": beforeID.map(String.init) ?? "end",
            ]
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                if let beforeID {
                    // Insert immediately left of the neighbor tile.
                    try await MenuBarItemMover.move(
                        windowID: draggedID,
                        to: .leftOf(targetWindowID: beforeID),
                        enabled: true
                    )
                } else if let toggleID = self.toggleItem.button?.window.map({
                    CGWindowID($0.windowNumber)
                }) {
                    // End of panel list = rightmost hidden item = just left of the chevron.
                    try await MenuBarItemMover.move(
                        windowID: draggedID,
                        to: .leftOf(targetWindowID: toggleID),
                        enabled: true
                    )
                } else if let primaryWindowID = self.primarySeparatorItem.button?.window.map({
                    CGWindowID($0.windowNumber)
                }) {
                    try await MenuBarItemMover.move(
                        windowID: draggedID,
                        to: .rightOf(targetWindowID: primaryWindowID),
                        enabled: true
                    )
                } else {
                    await MainActor.run {
                        self.revealPanel.presentStatus("Could not find a reorder anchor.")
                    }
                    return
                }
                await MainActor.run {
                    self.revealPanel.presentStatus("Reordered.")
                    self.record("reveal_panel_reorder_succeeded")
                }
            } catch {
                await MainActor.run {
                    self.revealPanel.presentStatus("Reorder failed — item may be immovable.")
                    self.record(
                        "reveal_panel_reorder_failed",
                        level: .warning,
                        publicFields: ["reason": String(describing: error)]
                    )
                }
            }
        }
    }

    /// Panel → visible menu bar (right of toggle).
    /// Invokes `completion(true)` only after a successful live move so the panel
    /// can drop the tile; failures leave the tile in place.
    private func applyRevealPanelUnhide(windowID: CGWindowID, completion: @escaping (Bool) -> Void) {
        guard PrivacyPermissions.isAccessibilityTrusted else {
            revealPanel.presentStatus("Enable Accessibility to move items into the menu bar.")
            completion(false)
            return
        }
        guard let toggleID = toggleItem.button?.window.map({ CGWindowID($0.windowNumber) }) else {
            revealPanel.presentStatus("Could not find the chevron anchor.")
            completion(false)
            return
        }
        Task { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            do {
                try await MenuBarItemMover.move(
                    windowID: windowID,
                    to: .rightOf(targetWindowID: toggleID),
                    enabled: true
                )
                await MainActor.run {
                    self.parkedHideWindowIDs.removeAll { $0 == windowID }
                    self.revealPanel.presentStatus("Moved to menu bar.")
                    self.record("reveal_panel_unhide_succeeded")
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    self.revealPanel.presentStatus("Could not unhide — item may be immovable.")
                    self.record(
                        "reveal_panel_unhide_failed",
                        level: .warning,
                        publicFields: ["reason": String(describing: error)]
                    )
                    completion(false)
                }
            }
        }
    }

    /// Regular menu bar → hidden lane (left of toggle) via ⌘-drag into panel.
    private func applyRevealPanelHideFromMenuBar(windowID: CGWindowID) {
        guard PrivacyPermissions.isAccessibilityTrusted else {
            revealPanel.presentStatus("Enable Accessibility to hide menu bar items into the panel.")
            return
        }
        // Don't park our own control markers.
        let ownIDs: Set<CGWindowID> = Set(
            [toggleItem, primarySeparatorItem, secondarySeparatorItem].compactMap {
                $0.button?.window.map { CGWindowID($0.windowNumber) }
            }
        )
        guard !ownIDs.contains(windowID) else {
            revealPanel.presentStatus("Can't hide Hidden Bar's own markers.")
            return
        }
        guard let toggleID = toggleItem.button?.window.map({ CGWindowID($0.windowNumber) }) else {
            revealPanel.presentStatus("Could not find the chevron anchor.")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await MenuBarItemMover.move(
                    windowID: windowID,
                    to: .leftOf(targetWindowID: toggleID),
                    enabled: true
                )
                await MainActor.run {
                    if !self.parkedHideWindowIDs.contains(windowID) {
                        self.parkedHideWindowIDs.append(windowID)
                    }
                    self.revealPanel.presentStatus("Hidden into lane — reopen panel to refresh.")
                    self.record("reveal_panel_hide_from_bar_succeeded")
                    // Refresh panel contents.
                    if let screen = self.revealTargetScreen() {
                        self.presentRevealPanel(
                            near: self.asDouble(self.toggleItem.button?.window?.frame.midX),
                            on: screen,
                            laneBounds: self.currentLaneBounds(screen: screen),
                            forceShow: false
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.revealPanel.presentStatus("Could not hide — item may be immovable.")
                    self.record(
                        "reveal_panel_hide_from_bar_failed",
                        level: .warning,
                        publicFields: ["reason": String(describing: error)]
                    )
                }
            }
        }
    }

    private func openSettingsFromPanel() {
        revealPanel.hide()
        openSettings()
    }

    /// Activate an item chosen in the RevealPanel through the injected owner (ACT-001).
    /// Outcomes are explicit — silent expand-only fallback is no longer accepted.
    private func activateHiddenItem(_ windowID: CGWindowID) {
        guard
            let screen = revealTargetScreen(),
            let toggleWindowID = toggleItem.button?.window.map({ CGWindowID($0.windowNumber) })
        else {
            record("item_activation_failed", level: .warning, publicFields: ["reason": "missing_target"])
            revealPanel.presentStatus("Could not target that item — try expanding inline.")
            return
        }

        let request = MenuBarActivationRequest(
            item: MenuBarItemHandle(windowID: windowID),
            targetDisplay: MenuBarDisplayHandle(rawValue: screen.displayID),
            visibleAnchor: MenuBarItemHandle(windowID: toggleWindowID),
            preferInPlace: true
        )
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.services.activation.activate(request)
            switch outcome {
            case .activated:
                self.record("item_activated", privateFields: ["window_id": String(windowID)])
                self.revealPanel.hide()
            case .revealedForActivation:
                self.record("item_revealed_for_activation", privateFields: ["window_id": String(windowID)])
                self.revealPanel.hide()
                self.revealPanel.presentStatus("Moved into the menu bar — click it there to open.")
                // Item was relocated into view; leave it for a real click (menus need focus).
                self.expand()
            case .permissionRequired(let permission):
                self.record(
                    "item_activation_permission_required",
                    level: .warning,
                    publicFields: ["permission": permission]
                )
                self.revealPanel.presentStatus(Self.permissionRepairMessage(permission))
                if permission == "accessibility" {
                    PrivacyPermissions.requestAccessibilityAccessAndShowSettings()
                }
            case .unsupported(let reason):
                self.record("item_activation_unsupported", level: .info, publicFields: ["reason": reason])
                self.revealPanel.presentStatus(Self.unsupportedActivationMessage(reason))
            case .failedRecovered(let reason):
                self.record("item_activation_failed_recovered", level: .error, publicFields: ["reason": reason])
                self.revealPanel.presentStatus("Could not open that item. Menu bar left unchanged.")
            }
        }
    }

    private static func permissionRepairMessage(_ permission: String) -> String {
        switch permission {
        case "accessibility":
            return "Grant Accessibility in System Settings → Privacy to open items from the panel."
        case "screen_recording":
            return "Screen Recording is optional for icons only — activation still needs Accessibility."
        default:
            return "Missing permission: \(permission). Open System Settings → Privacy to repair."
        }
    }

    private static func unsupportedActivationMessage(_ reason: String) -> String {
        switch reason {
        case "item_not_movable":
            return "System-owned extra — open it from the menu bar (can't relocate)."
        case "item_missing", "item_frame_unreadable":
            return "Item disappeared from the menu bar — refresh and try again."
        case "experimental_item_movement_disabled":
            return "Could not open in place. Enable experimental movement in Settings to relocate it."
        default:
            return "Cannot activate: \(reason)"
        }
    }

    func recomputeGeometry() {
        record("geometry_recomputing", level: .debug)
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
        if toggleState == .collapsed {
            _ = collapse()
        } else {
            let isValid = currentMarkerOrderValid()
            preferencesStore.recordMarkerOrder(valid: isValid)
            if !isValid {
                perform(stateMachine.handle(.repairRequested(.reconciliationFailed)))
            } else {
                preferencesStore.recordGeometryReadable(true)
            }
        }
        let targetScreen = revealTargetScreen()
        if let targetScreen {
            presentRevealPanel(
                near: asDouble(toggleItem.button?.window?.frame.midX),
                on: targetScreen,
                laneBounds: currentLaneBounds(screen: targetScreen),
                forceShow: false
            )
        }
        scheduleGeometryRefresh()
    }

    func temporarilyRevealMarkers() {
        revealWorkItem?.cancel()
        let shouldRestoreCollapsed = (toggleState == .collapsed)
        record("markers_temporarily_revealed")
        expand()
        openOnboarding()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if shouldRestoreCollapsed {
                self.attemptRevealCollapse()
            }
        }
        revealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }

    private func configureStatusItems() {
        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(handleToggleButton(_:))
            // leftMouseUp for primary action; rightMouseUp for context menu.
            // (Do not also register leftMouseDown — would double-fire toggleReveal.)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        if let primaryButton = primarySeparatorItem.button {
            primaryButton.isBordered = false
        }
        if let secondaryButton = secondarySeparatorItem.button {
            secondaryButton.isBordered = false
        }
    }

    private func configureMenu() {
        contextMenu.removeAllItems()
        contextMenu.addItem(hostedMenuItem(
            HiddenMenuSummaryRow(
                profileName: profileStore.activeProfileName,
                toggleState: toggleState == .collapsed ? "collapsed" : "expanded",
                autoCollapseText: autoCollapseSummary()
            )
        ))
        let axOK = PrivacyPermissions.isAccessibilityTrusted
        let geoOK = preferencesStore.diagnostics.geometryReadable
        let geometryLabel: String = {
            if !axOK { return "ok (Accessibility off)" }
            return geoOK ? "readable" : "needs repair"
        }()
        contextMenu.addItem(hostedMenuItem(
            HiddenMenuDiagnosticsRow(
                markerStatus: preferencesStore.diagnostics.markerOrderStatus.rawValue,
                geometryStatus: geometryLabel,
                bridgeStatus: HammerspoonBridge.shared.status.code.rawValue
            )
        ))
        if !axOK {
            // Sticky top of menu — this is the real blocker, not geometry.
            let axItem = NSMenuItem(
                title: "⚠ Accessibility OFF — enable for hide & ⌘-drag…",
                action: #selector(menuRequestAccessibility),
                keyEquivalent: ""
            )
            contextMenu.addItem(axItem)
        }
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Expand Inline", action: #selector(menuExpand), keyEquivalent: "e"))
        contextMenu.addItem(NSMenuItem(title: "Collapse", action: #selector(menuCollapse), keyEquivalent: "c"))
        contextMenu.addItem(NSMenuItem(title: "Show Below Menu Bar", action: #selector(menuOpenRevealPanel), keyEquivalent: "i"))
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Open Settings", action: #selector(menuOpenSettings), keyEquivalent: ","))
        contextMenu.addItem(NSMenuItem(title: "Open Diagnostics", action: #selector(menuOpenDiagnostics), keyEquivalent: "d"))
        contextMenu.addItem(NSMenuItem(title: "Reveal Markers", action: #selector(menuRevealMarkers), keyEquivalent: "r"))
        contextMenu.addItem(NSMenuItem(title: "Repair Marker Positions", action: #selector(menuRepairMarkers), keyEquivalent: ""))
        if !parkRestoreQueue.isEmpty {
            contextMenu.addItem(NSMenuItem(
                title: "Retry Restore Hidden Items (\(parkRestoreQueue.pending.count))",
                action: #selector(menuRetryParkRestore),
                keyEquivalent: ""
            ))
        }
        contextMenu.addItem(.separator())
        contextMenu.addItem(NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q"))
        contextMenu.items.forEach { item in
            if item.action != nil {
                item.target = self
            }
        }
        record("context_menu_rebuilt", level: .debug)
    }

    private func bindConfig() {
        preferencesStore.$config
            .sink { [weak self] _ in
                self?.applyCurrentConfiguration()
                self?.configureMenu()
            }
            .store(in: &cancellables)

        profileStore.$activeProfileName
            .sink { [weak self] _ in
                self?.configureMenu()
            }
            .store(in: &cancellables)
    }

    private func applyCurrentConfiguration() {
        preferencesStore.recordGeometrySnapshot(currentGeometrySnapshot())
        perform(stateMachine.handle(.reapplyRequested))
        scheduleAutoCollapseIfNeeded()
        updateToggleAppearance()
        updateMarkerTitles()
        scheduleGeometryRefresh()
    }

    private func applyExpandedLengths() {
        let config = preferencesStore.config
        primarySeparatorItem.length = primaryExpandedLength(for: config)
        secondarySeparatorItem.length = secondaryExpandedLength(for: config)
        updateMarkerTitles()
    }

    private func primaryExpandedLength(for config: HiddenBarConfig) -> CGFloat {
        config.lanes.primarySeparatorVisibleWhenExpanded ? 8.0 : 0.0
    }

    private func secondaryExpandedLength(for config: HiddenBarConfig) -> CGFloat {
        guard config.lanes.alwaysHiddenEnabled else {
            return 0.0
        }
        return config.lanes.secondarySeparatorVisibleWhenExpanded ? 8.0 : 0.0
    }

    private func hostedMenuItem<Content: View>(_ content: Content) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuItemHostingView(rootView: AnyView(content))
        return item
    }

    private func autoCollapseSummary() -> String {
        let profile = profileStore.activeProfile
        if profile.autoCollapseEnabled {
            return "auto-collapse \(profile.autoCollapseSeconds)s"
        }
        return "manual collapse"
    }

    private func updateToggleAppearance() {
        guard let button = toggleItem.button else {
            return
        }
        let revealsBelow = revealAppearanceUsesBelowMenuBar
        let axOK = PrivacyPermissions.isAccessibilityTrusted
        let symbolName = revealsBelow ? "chevron.down" : ((toggleState == .collapsed) ? "chevron.right" : "chevron.left")
        let preferred = preferencesStore.config.resolvedChevronColor
        let color = Self.nsColor(for: preferred, axTrusted: axOK)
        button.image = Self.menuBarChevronImage(symbolName: symbolName, color: color)
        button.imagePosition = .imageOnly
        button.appearsDisabled = false
        button.contentTintColor = nil
        if !axOK {
            button.toolTip = "Accessibility OFF (warning tint). Your chevron color returns when trust is restored."
        } else {
            button.toolTip = revealsBelow
                ? "Show hidden items (⌘-drag to reorder · top strip unhides)"
                : ((toggleState == .collapsed) ? "Expand hidden menu items" : "Collapse menu items")
        }
    }

    private static func nsColor(for preference: ChevronIconColor, axTrusted: Bool) -> NSColor {
        if !axTrusted { return .systemOrange }
        switch preference {
        case .white: return .white
        case .blue: return .systemBlue
        case .yellow: return .systemYellow
        case .orange: return .systemOrange
        case .system: return .labelColor
        }
    }

    /// Solid-color chevron for the menu bar (not a template — always visible).
    private static func menuBarChevronImage(symbolName: String, color: NSColor) -> NSImage {
        let pointSize: CGFloat = 13
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Hidden Bar Toggle")?
            .withSymbolConfiguration(config)
        let src = symbol ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        let pad: CGFloat = 2
        let size = NSSize(
            width: max(16, ceil(src.size.width) + pad),
            height: max(16, ceil(src.size.height) + pad)
        )
        let image = NSImage(size: size, flipped: false) { rect in
            let dest = NSRect(
                x: (rect.width - src.size.width) / 2,
                y: (rect.height - src.size.height) / 2,
                width: src.size.width,
                height: src.size.height
            )
            src.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func updateMarkerTitles() {
        // The primary item becomes a wide invisible spacer while collapsed.
        // Drawing the divider then centers it inside the empty region, which
        // looks like a stray marker in the middle of the display.
        let hideMarkers = toggleState == .collapsed
            || (preferencesStore.config.hideMarkersWhileExpanded && toggleState == .expanded)
        primarySeparatorItem.button?.title = hideMarkers ? "" : "¦"
        secondarySeparatorItem.button?.title = hideMarkers ? "" : "¦"
    }

    private func scheduleAutoCollapseIfNeeded() {
        autoCollapseWorkItem?.cancel()
        let profile = profileStore.activeProfile
        guard toggleState == .expanded, profile.autoCollapseEnabled else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptAutoCollapse()
        }
        autoCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(profile.autoCollapseSeconds), execute: workItem)
    }

    private func attemptAutoCollapse() {
        guard toggleState == .expanded else {
            return
        }
        guard !shouldPauseCollapseForInteraction() else {
            record("auto_collapse_delayed", level: .debug, publicFields: ["reason": "pointer_interaction"])
            scheduleAutoCollapseRetry()
            return
        }
        _ = collapse()
    }

    private func scheduleAutoCollapseRetry(after delay: TimeInterval? = nil) {
        autoCollapseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptAutoCollapse()
        }
        autoCollapseWorkItem = workItem
        let retryDelay = delay ?? Self.deferredCollapseRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
    }

    private func attemptRevealCollapse() {
        guard toggleState == .expanded else {
            return
        }
        guard !shouldPauseCollapseForInteraction() else {
            scheduleRevealCollapseRetry()
            return
        }
        _ = collapse()
    }

    private func scheduleRevealCollapseRetry(after delay: TimeInterval? = nil) {
        revealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptRevealCollapse()
        }
        revealWorkItem = workItem
        let retryDelay = delay ?? Self.deferredCollapseRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: workItem)
    }

    private func currentMarkerOrderValid() -> Bool {
        let primaryX = compactPrimaryMinX()
        let toggleX = asDouble(toggleItem.button?.window?.frame.minX)
        let secondaryX = asDouble(secondarySeparatorItem.button?.window?.frame.minX)
        let alwaysHidden = preferencesStore.config.lanes.alwaysHiddenEnabled
        guard MarkerGeometry.isValidOrder(
            toggleX: toggleX,
            primaryX: primaryX,
            secondaryX: secondaryX,
            alwaysHiddenEnabled: alwaysHidden
        ) else {
            return false
        }
        let screen = toggleItem.button?.window?.screen ?? activeMouseScreen()
        guard let screen else { return false }
        return MarkerGeometry.markersOnScreen(
            toggleX: toggleX,
            primaryX: primaryX,
            secondaryX: secondaryX,
            alwaysHiddenEnabled: alwaysHidden,
            screenMinX: Double(screen.frame.minX),
            screenMaxX: Double(screen.frame.maxX)
        )
    }

    private func currentLaneBounds(screen: NSScreen?) -> MenuBarLaneBounds {
        MenuBarLaneBounds(
            toggleX: asDouble(toggleItem.button?.window?.frame.minX),
            primaryX: compactPrimaryMinX(),
            secondaryX: asDouble(secondarySeparatorItem.button?.window?.frame.minX),
            alwaysHiddenEnabled: preferencesStore.config.lanes.alwaysHiddenEnabled,
            screenMinX: asDouble(screen?.frame.minX),
            screenMaxX: asDouble(screen?.frame.maxX)
        )
    }

    /// Notch band for the reveal panel when overflow support is enabled.
    private func currentNotchGeometry(screen: NSScreen) -> NotchBandGeometry? {
        guard preferencesStore.config.isNotchSupportEnabled else { return nil }
        return NotchBandGeometry.forScreen(screen)
    }

    private func currentOverflowLayout(screen: NSScreen) -> MenuBarOverflowLayout? {
        guard preferencesStore.config.isNotchSupportEnabled else { return nil }
        return MenuBarOverflowLayout.forScreen(screen)
    }

    /// - Parameter forceShow: when true, always `show` (never toggle-off). Chevron
    ///   open paths must use forceShow so a re-entrant call can’t dismiss the panel.
    private func presentRevealPanel(
        near anchor: Double?,
        on screen: NSScreen,
        laneBounds: MenuBarLaneBounds,
        forceShow: Bool
    ) {
        let notch = currentNotchGeometry(screen: screen)
        let overflow = currentOverflowLayout(screen: screen)
        let notchOn = preferencesStore.config.isNotchSupportEnabled
        let alwaysShow = Set(preferencesStore.config.resolvedPanelAlwaysShowNamespaces)
        if forceShow {
            revealPanel.show(
                near: anchor,
                on: screen,
                laneBounds: laneBounds,
                parkedWindowIDs: parkedHideWindowIDs,
                notch: notch,
                overflow: overflow,
                notchSupportEnabled: notchOn,
                alwaysShowNamespaces: alwaysShow
            )
        } else {
            revealPanel.refreshIfVisible(
                near: anchor,
                on: screen,
                laneBounds: laneBounds,
                parkedWindowIDs: parkedHideWindowIDs,
                notch: notch,
                overflow: overflow,
                notchSupportEnabled: notchOn,
                alwaysShowNamespaces: alwaysShow
            )
        }
    }

    private func asDouble(_ value: CGFloat?) -> Double? {
        value.map(Double.init)
    }

    private func currentGeometrySnapshot() -> HiddenBarGeometrySnapshot {
        let toggleX = asDouble(toggleItem.button?.window?.frame.minX)
        // Normalize to the compact divider position. Without this, every
        // geometry refresh while collapsed treats the already-inflated
        // spacer's minX as a new baseline and grows it again.
        let primaryX = compactPrimaryMinX()
        let secondaryX = asDouble(secondarySeparatorItem.button?.window?.frame.minX)
        let toggleScreen = toggleItem.button?.window?.screen
        let primaryScreen = primarySeparatorItem.button?.window?.screen
        let mouseScreen = activeMouseScreen()
        let toggleScreenVisibleWidth = asDouble(toggleScreen?.visibleFrame.width)
        let primaryScreenVisibleWidth = asDouble(primaryScreen?.visibleFrame.width)
        let mouseScreenVisibleWidth = asDouble(mouseScreen?.visibleFrame.width)
        let toggleScreenVisibleMaxX = asDouble(toggleScreen?.visibleFrame.maxX)
        let primaryScreenVisibleMaxX = asDouble(primaryScreen?.visibleFrame.maxX)
        let mouseScreenVisibleMaxX = asDouble(mouseScreen?.visibleFrame.maxX)

        func rawWidth(_ visibleMaxX: Double?, _ primaryMinX: Double?) -> Double? {
            guard let visibleMaxX, let primaryMinX else {
                return nil
            }
            return visibleMaxX - primaryMinX
        }

        let scan = scanScreen(toggleScreen ?? mouseScreen, toggleMinX: toggleX)

        return HiddenBarGeometrySnapshot(
            toggleMinX: toggleX,
            primaryMinX: primaryX,
            secondaryMinX: secondaryX,
            toggleScreenName: toggleScreen?.localizedName,
            primaryScreenName: primaryScreen?.localizedName,
            mouseScreenName: mouseScreen?.localizedName,
            toggleScreenVisibleWidth: toggleScreenVisibleWidth,
            primaryScreenVisibleWidth: primaryScreenVisibleWidth,
            mouseScreenVisibleWidth: mouseScreenVisibleWidth,
            toggleScreenVisibleMaxX: toggleScreenVisibleMaxX,
            primaryScreenVisibleMaxX: primaryScreenVisibleMaxX,
            mouseScreenVisibleMaxX: mouseScreenVisibleMaxX,
            allScreenVisibleWidths: NSScreen.screens.map { Double($0.visibleFrame.width) },
            allScreenVisibleMaxX: NSScreen.screens.map { Double($0.visibleFrame.maxX) },
            rawWidthFromToggleScreen: rawWidth(toggleScreenVisibleMaxX, primaryX),
            rawWidthFromPrimaryScreen: rawWidth(primaryScreenVisibleMaxX, primaryX),
            rawWidthFromMouseScreen: rawWidth(mouseScreenVisibleMaxX, primaryX),
            realItemCount: scan?.items.count,
            realHideableItemCount: scan?.hideableItemCount,
            realLeftmostMinX: scan?.leftmostMinX,
            notchDetected: scan?.hasNotch
        )
    }

    private func compactPrimaryMinX() -> Double? {
        MarkerGeometry.compactMinX(
            currentMinX: asDouble(primarySeparatorItem.button?.window?.frame.minX),
            currentWidth: asDouble(primarySeparatorItem.button?.window?.frame.width),
            compactWidth: Double(primaryExpandedLength(for: preferencesStore.config))
        )
    }

    @discardableResult
    private func scanScreen(_ screen: NSScreen?, toggleMinX: Double?) -> MenuBarDiscoverySnapshot? {
        guard let screen else {
            return nil
        }
        let scan = services.discovery.snapshot(
            on: MenuBarDisplayHandle(rawValue: screen.displayID),
            toggleMinX: toggleMinX
        )
        lastScan = scan
        return scan
    }

    private func activeMouseScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }

    private func revealTargetScreen() -> NSScreen? {
        // The status item window is authoritative when macOS has placed the
        // menu extra on a display. Mouse/main are only startup fallbacks.
        toggleItem.button?.window?.screen ?? activeMouseScreen() ?? NSScreen.main
    }

    private func shouldRevealBelowMenuBar(on screen: NSScreen?) -> Bool {
        let hasNotch: Bool
        if let screen {
            hasNotch = scanScreen(screen, toggleMinX: asDouble(toggleItem.button?.window?.frame.minX))?.hasNotch ?? false
        } else {
            hasNotch = false
        }
        return preferencesStore.config.resolvedRevealMode(hasNotch: hasNotch) == .belowMenuBar
    }

    private var revealAppearanceUsesBelowMenuBar: Bool {
        switch preferencesStore.config.configuredRevealMode {
        case .belowMenuBar:
            return true
        case .inline:
            return false
        case .automatic:
            return lastScan?.hasNotch ?? false
        }
    }

    private func shouldPauseCollapseForInteraction() -> Bool {
        if isUserDraggingMenuBarItems {
            return true
        }
        if NSEvent.pressedMouseButtons != 0 {
            return true
        }
        return isMouseInMenuBarBand()
    }

    private func isMouseInMenuBarBand() -> Bool {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            MarkerGeometry.isPointInMenuBarBand(
                mouseLocation,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    /// Always-on monitors (Ice: show all sections on ⌘-drag). Shrink spacer
    /// markers so native menu-bar rearrange works; never run synthetic park
    /// restore mid-drag (that would fight the user's mouse).
    private func installUserMenuBarCommandDragMonitors() {
        guard userMenuBarDragGlobalMonitor == nil else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleUserMenuBarCommandDragEvent(event)
        }
        userMenuBarDragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            handler(event)
        }
        userMenuBarDragLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            handler(event)
            return event
        }
    }

    private func handleUserMenuBarCommandDragEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            let command = event.modifierFlags.contains(.command)
            let inBand = isMouseInMenuBarBand()
            guard UserMenuBarCommandDragPolicy.shouldRevealMarkersForCommandDrag(
                isCommand: command,
                isInMenuBarBand: inBand
            ) else { return }
            if !isUserDraggingMenuBarItems {
                isUserDraggingMenuBarItems = true
                autoCollapseWorkItem?.cancel()
                // Soft reveal only — lengths, not placement restore.
                applyExpandedLengths()
                updateToggleAppearance()
                record("user_menubar_cmd_drag_began")
            }
        case .leftMouseUp:
            guard isUserDraggingMenuBarItems else { return }
            isUserDraggingMenuBarItems = false
            record("user_menubar_cmd_drag_ended")
            // If still logically collapsed, re-apply hide after the drag settles.
            if toggleState == .collapsed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, !self.isUserDraggingMenuBarItems, self.toggleState == .collapsed else {
                        return
                    }
                    _ = self.collapse()
                }
            } else {
                scheduleAutoCollapseIfNeeded()
            }
        default:
            break
        }
    }

    private func scheduleGeometryRefresh() {
        geometryRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if UserMenuBarCommandDragPolicy.shouldSuppressCollapseReapply(
                isUserDragging: self.isUserDraggingMenuBarItems
            ) {
                return
            }
            self.preferencesStore.recordGeometrySnapshot(self.currentGeometrySnapshot())
            if self.toggleState == .collapsed {
                _ = self.collapse()
            } else {
                let isValid = self.currentMarkerOrderValid()
                self.preferencesStore.recordMarkerOrder(valid: isValid)
                self.preferencesStore.recordGeometryReadable(isValid, reason: isValid ? nil : "geometry_unreadable")
            }
        }
        geometryRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func applyRepairState(_ failure: MenuBarCollapseFailure) {
        autoCollapseWorkItem?.cancel()
        // Accessibility is not a marker-geometry failure — log distinctly.
        if failure == .accessibilityRequired {
            record(
                "accessibility_required_staying_expanded",
                level: .warning,
                publicFields: ["reason": failure.rawValue]
            )
        } else {
            record("marker_repair_entered", level: .warning, publicFields: ["reason": failure.rawValue])
        }
        applyExpandedLengths()
        updateToggleAppearance()
    }

    private func perform(_ transition: MenuBarTransition) {
        for effect in transition.effects {
            switch effect {
            case .attemptCollapse:
                _ = collapse()
            case .applyExpanded:
                applyExpandedState()
            case .reapplyExpanded:
                applyExpandedLengths()
            case .applyCollapsed(let plan):
                applyCollapsedState(plan)
            case .enterRepair(let failure):
                applyRepairState(failure)
            }
        }
    }

    private func record(
        _ name: String,
        category: MenuBarDiagnosticCategory = .menuBar,
        level: MenuBarDiagnosticLevel = .info,
        publicFields: [String: String] = [:],
        privateFields: [String: String] = [:]
    ) {
        services.diagnostics.record(
            MenuBarDiagnosticEvent(
                name: name,
                category: category,
                level: level,
                publicFields: publicFields,
                privateFields: privateFields
            )
        )
    }

    @objc private func handleToggleButton(_ sender: Any?) {
        // Ensure left-click always runs even if currentEvent is missing/odd.
        let event = NSApp.currentEvent
        // Never toggle when the user is (or just finished) ⌘-dragging menu-bar items.
        if isUserDraggingMenuBarItems || event?.modifierFlags.contains(.command) == true {
            return
        }
        let isRight: Bool = {
            guard let event else { return false }
            return event.type == .rightMouseUp
                || event.type == .rightMouseDown
                || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        }()
        if isRight {
            configureMenu()
            toggleItem.menu = contextMenu
            // Present menu without relying on performClick re-entry.
            if let button = toggleItem.button {
                contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
            toggleItem.menu = nil
            return
        }
        if let event, event.modifierFlags.contains(.option) {
            temporarilyRevealMarkers()
            return
        }
        record("toggle_button_left_click", level: .debug)
        toggleReveal()
    }

    @objc private func menuExpand() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "expand"])
        expand()
    }

    @objc private func menuCollapse() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "collapse"])
        _ = collapse()
    }

    @objc private func menuOpenRevealPanel() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "open_ice_bar"])
        openRevealPanel()
    }

    @objc private func menuOpenSettings() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "open_settings"])
        openSettings()
    }

    @objc private func menuOpenDiagnostics() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "open_diagnostics"])
        openDiagnostics()
    }

    @objc private func menuRequestAccessibility() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "request_accessibility"])
        didPromptAccessibilityThisSession = true
        PrivacyPermissions.requestAccessibilityAccessAndShowSettings()
        // After user may grant, attempt any deferred restore.
        scheduleParkRestoreDrain(reason: "after_accessibility_prompt")
    }

    @objc private func menuRetryParkRestore() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "retry_park_restore"])
        scheduleParkRestoreDrain(reason: "menu_retry")
    }

    @objc private func menuRevealMarkers() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "reveal_markers"])
        temporarilyRevealMarkers()
    }

    @objc private func menuRepairMarkers() {
        record("context_menu_command", category: .commandExecution, publicFields: ["command": "repair_markers"])
        didAttemptMarkerAutoRepair = false
        repairMarkers()
    }

    @objc private func menuQuit() {
        record("context_menu_command", category: .appLifecycle, publicFields: ["command": "quit"])
        NSApplication.shared.terminate(nil)
    }
}
