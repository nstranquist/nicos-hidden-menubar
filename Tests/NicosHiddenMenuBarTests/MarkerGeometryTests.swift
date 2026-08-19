import XCTest
@testable import NicosHiddenMenuBar

final class MarkerGeometryTests: XCTestCase {
    func testCompactMinXMakesRepeatedCollapseMeasurementIdempotent() {
        XCTAssertEqual(
            MarkerGeometry.compactMinX(currentMinX: 950, currentWidth: 280, compactWidth: 8),
            1_222
        )
        XCTAssertEqual(
            MarkerGeometry.compactMinX(currentMinX: 1_222, currentWidth: 8, compactWidth: 8),
            1_222
        )
    }

    func testCompactMinXRejectsUnreadableWidths() {
        XCTAssertNil(MarkerGeometry.compactMinX(currentMinX: 100, currentWidth: nil, compactWidth: 8))
        XCTAssertNil(MarkerGeometry.compactMinX(currentMinX: 100, currentWidth: -1, compactWidth: 8))
    }

    func testStatusItemAnchorRejectsLaunchPlaceholderOnAnyDisplayOrigin() {
        XCTAssertFalse(
            MarkerGeometry.isReadyStatusItemAnchor(
                24, screenMinX: 0, screenMidX: 748, screenMaxX: 1_496
            ))
        XCTAssertTrue(
            MarkerGeometry.isReadyStatusItemAnchor(
                1_295, screenMinX: 0, screenMidX: 748, screenMaxX: 1_496
            ))
        XCTAssertTrue(
            MarkerGeometry.isReadyStatusItemAnchor(
                -120, screenMinX: -1_496, screenMidX: -748, screenMaxX: 0
            ))
    }

    func testCompactFallbackOnlyAppliesToFailedBelowMenuBarCollapse() {
        XCTAssertTrue(
            MarkerGeometry.shouldUseCompactFallback(
                revealsBelowMenuBar: true,
                collapseHidItems: false
            ))
        XCTAssertFalse(
            MarkerGeometry.shouldUseCompactFallback(
                revealsBelowMenuBar: false,
                collapseHidItems: false
            ))
        XCTAssertFalse(
            MarkerGeometry.shouldUseCompactFallback(
                revealsBelowMenuBar: true,
                collapseHidItems: true
            ))
        XCTAssertFalse(
            MarkerGeometry.shouldUseCompactFallback(
                revealsBelowMenuBar: true,
                collapseHidItems: nil
            ))
    }

    func testCollapsedWidthUsesFrozenFormulaAndClamp() {
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1440, primaryMinX: 1420), 32.0)
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1512, primaryMinX: 1012), 500.0)
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 12050, primaryMinX: 10), 10000.0)
    }

    func testCollapsedWidthUsesGlobalRightEdgeForOffsetDisplays() {
        XCTAssertEqual(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 4147, primaryMinX: -3611), 7758.0)
    }

    func testPreferredVisibleFrameMaxXPrefersReadableCandidatesInOrder() {
        XCTAssertEqual(
            MarkerGeometry.preferredVisibleFrameMaxX(
                primaryMinX: 1176,
                preferredVisibleFrameMaxX: [1956, 1728],
                fallbackVisibleFrameMaxX: [1728, 1956]
            ),
            1956
        )
    }

    func testPreferredVisibleFrameMaxXFallsBackToLargestReadableCandidate() {
        XCTAssertEqual(
            MarkerGeometry.preferredVisibleFrameMaxX(
                primaryMinX: 1176,
                preferredVisibleFrameMaxX: [nil, 1000],
                fallbackVisibleFrameMaxX: [1728, 1956]
            ),
            1956
        )
    }

    func testCollapsedWidthReturnsNilWhenGeometryIsUnreadable() {
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: nil, primaryMinX: 120))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 1512, primaryMinX: nil))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 300, primaryMinX: 300))
        XCTAssertNil(MarkerGeometry.collapsedWidth(visibleFrameMaxX: 300, primaryMinX: 301))
        XCTAssertNil(
            MarkerGeometry.preferredVisibleFrameMaxX(
                primaryMinX: 300,
                preferredVisibleFrameMaxX: [nil, 300],
                fallbackVisibleFrameMaxX: [299, 300]
            )
        )
    }

    func testMarkerOrderPredicateOneSeparator() {
        XCTAssertTrue(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 800, secondaryX: nil, alwaysHiddenEnabled: false))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 800, primaryX: 800, secondaryX: nil, alwaysHiddenEnabled: false))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: nil, primaryX: 800, secondaryX: nil, alwaysHiddenEnabled: false))
    }

    func testMarkerOrderPredicateTwoSeparators() {
        XCTAssertTrue(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 850, secondaryX: 800, alwaysHiddenEnabled: true))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 850, secondaryX: 860, alwaysHiddenEnabled: true))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: nil, secondaryX: 800, alwaysHiddenEnabled: true))
        XCTAssertFalse(MarkerGeometry.isValidOrder(toggleX: 900, primaryX: 850, secondaryX: nil, alwaysHiddenEnabled: true))
    }

    func testMenuBarBandMatchesOnlyTheTopStripAboveVisibleFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1091)

        XCTAssertTrue(
            MarkerGeometry.isPointInMenuBarBand(
                CGPoint(x: 300, y: 1108),
                frame: frame,
                visibleFrame: visibleFrame
            )
        )
        XCTAssertFalse(
            MarkerGeometry.isPointInMenuBarBand(
                CGPoint(x: 300, y: 1080),
                frame: frame,
                visibleFrame: visibleFrame
            )
        )
    }

    func testMarkersOnScreenRejectsLiveOffScreenAutosaveDrift() {
        // Live diagnostics class: markers at ≈ −3780 on a single 0…1496 display.
        XCTAssertFalse(
            MarkerGeometry.markersOnScreen(
                toggleX: -3_772,
                primaryX: -3_780,
                secondaryX: -3_850,
                alwaysHiddenEnabled: false,
                screenMinX: 0,
                screenMaxX: 1_496
            )
        )
        XCTAssertTrue(
            MarkerGeometry.markersOnScreen(
                toggleX: 1_420,
                primaryX: 1_300,
                secondaryX: nil,
                alwaysHiddenEnabled: false,
                screenMinX: 0,
                screenMaxX: 1_496
            )
        )
    }

    func testSafeCollapsedWidthRejectsOffScreenPrimaryAndCapsToVisibleWidth() {
        XCTAssertNil(
            MarkerGeometry.safeCollapsedWidth(
                visibleFrameMaxX: 1_496,
                primaryMinX: -3_780,
                screenMinX: 0,
                screenMaxX: 1_496
            )
        )
        XCTAssertEqual(
            MarkerGeometry.safeCollapsedWidth(
                visibleFrameMaxX: 1_496,
                primaryMinX: 1_200,
                screenMinX: 0,
                screenMaxX: 1_496
            ),
            296
        )
        // Width is the primary→visible-edge span, never larger than the visible band.
        XCTAssertEqual(
            MarkerGeometry.safeCollapsedWidth(
                visibleFrameMaxX: 1_496,
                primaryMinX: 10,
                screenMinX: 0,
                screenMaxX: 1_496
            ),
            1_486
        )
    }

    func testCollapsePlannerRejectsOffScreenMarkersAndNothingToHide() {
        let offScreen = MenuBarCollapseInputs(
            toggleX: -3_772,
            primaryX: -3_780,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496,
            screenVisibleMaxX: 1_496,
            hideableItemCount: 0,
            revealsBelowMenuBar: true,
            spacerStickyOnDisplay: false,
            primaryExpandedLength: 8,
            secondaryExpandedLength: 0
        )
        XCTAssertEqual(
            MenuBarCollapsePlanner.assess(offScreen),
            .reject(.markersOffScreen)
        )

        let nothingToHide = MenuBarCollapseInputs(
            toggleX: 1_400,
            primaryX: 1_300,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496,
            screenVisibleMaxX: 1_496,
            hideableItemCount: 0,
            revealsBelowMenuBar: true,
            spacerStickyOnDisplay: false,
            primaryExpandedLength: 8,
            secondaryExpandedLength: 0
        )
        // Never claim compact "success" with zero hideables (notch or inline).
        XCTAssertEqual(
            MenuBarCollapsePlanner.assess(nothingToHide),
            .reject(.nothingToHide)
        )
    }

    func testCollapsePlannerUsesSpacerOnBelowMenuBarThenFailsClosedAfterStickyFailure() {
        let below = MenuBarCollapseInputs(
            toggleX: 1_400,
            primaryX: 1_200,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496,
            screenVisibleMaxX: 1_496,
            hideableItemCount: 3,
            revealsBelowMenuBar: true,
            spacerStickyOnDisplay: false,
            primaryExpandedLength: 8,
            secondaryExpandedLength: 0
        )
        guard case .trySpacer(let plan) = MenuBarCollapsePlanner.assess(below) else {
            return XCTFail("expected verified spacer first on below-menu-bar")
        }
        XCTAssertEqual(plan.hideMechanism, .spacer)
        XCTAssertFalse(plan.useCompactFallback)
        XCTAssertEqual(plan.primaryLength, 296)

        // Sticky only after verified spacer failure — not global lastCollapseHidItems.
        var sticky = below
        sticky.revealsBelowMenuBar = false
        sticky.spacerStickyOnDisplay = true
        XCTAssertEqual(MenuBarCollapsePlanner.assess(sticky), .reject(.hideUnavailable))
    }

    func testSpacerVerifierRequiresEveryPlannedVisibleItemToHide() {
        let samples = [
            MenuBarSpacerVisibilitySample(windowID: 1, isOnScreen: false),
            MenuBarSpacerVisibilitySample(windowID: 2, isOnScreen: true),
        ]

        XCTAssertEqual(
            MenuBarSpacerVerifier.unhiddenIDs(samples: samples, planned: [1, 2]),
            [2]
        )
        XCTAssertFalse(MenuBarSpacerVerifier.allHidden(samples: samples, planned: [1, 2]))
        XCTAssertTrue(MenuBarSpacerVerifier.allHidden(samples: samples, planned: [1, 3]))
        XCTAssertFalse(MenuBarSpacerVerifier.allHidden(samples: samples, planned: []))
    }

    func testCollapsePlannerAcceptsSpacerWhenInlineGeometryHealthy() {
        let inputs = MenuBarCollapseInputs(
            toggleX: 1_400,
            primaryX: 1_200,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496,
            screenVisibleMaxX: 1_496,
            hideableItemCount: 2,
            revealsBelowMenuBar: false,
            spacerStickyOnDisplay: false,
            primaryExpandedLength: 8,
            secondaryExpandedLength: 0
        )
        guard case .trySpacer(let plan) = MenuBarCollapsePlanner.assess(inputs) else {
            return XCTFail("expected spacer attempt")
        }
        XCTAssertEqual(plan.hideMechanism, .spacer)
        XCTAssertFalse(plan.useCompactFallback)
        XCTAssertEqual(plan.primaryLength, 296)
    }

    func testCollapseHidePlannerSelectsMovableHiddenLaneItems() {
        let bounds = MenuBarLaneBounds(
            toggleX: 1_400,
            primaryX: 1_200,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        let plan = MenuBarCollapseHidePlanner.plan(
            candidates: [
                MenuBarCollapseHideCandidate(windowID: 1, midX: 1_100, isMovable: true),
                MenuBarCollapseHideCandidate(windowID: 2, midX: 1_250, isMovable: true),
                MenuBarCollapseHideCandidate(windowID: 3, midX: 1_450, isMovable: true),
                MenuBarCollapseHideCandidate(windowID: 4, midX: 1_220, isMovable: false),
            ],
            laneBounds: bounds,
            visibleMaxX: 1_496,
            parkY: 900
        )
        XCTAssertEqual(plan.windowIDs, [1, 2])
        XCTAssertEqual(plan.parkPastX, 1_496 + 36)
        // All planned must be past edge — one of two is not enough.
        XCTAssertFalse(
            MenuBarCollapseHidePlanner.allParkedPastEdge(
                frames: [(1, 1_510), (2, 1_200)],
                planned: plan.windowIDs,
                visibleMaxX: 1_496
            )
        )
        XCTAssertEqual(
            MenuBarCollapseHidePlanner.unparkedIDs(
                frames: [(1, 1_510), (2, 1_200)],
                planned: plan.windowIDs,
                visibleMaxX: 1_496
            ),
            [2]
        )
        XCTAssertTrue(
            MenuBarCollapseHidePlanner.allParkedPastEdge(
                frames: [(1, 1_510), (2, 1_520)],
                planned: plan.windowIDs,
                visibleMaxX: 1_496
            )
        )
        XCTAssertTrue(
            MenuBarCollapseHidePlanner.unparkedIDs(
                frames: [(1, 1_510), (2, 1_520)],
                planned: plan.windowIDs,
                visibleMaxX: 1_496
            ).isEmpty
        )
        // Missing frame for a planned ID fails all-parked.
        XCTAssertFalse(
            MenuBarCollapseHidePlanner.allParkedPastEdge(
                frames: [(1, 1_510)],
                planned: plan.windowIDs,
                visibleMaxX: 1_496
            )
        )
    }

    func testLaneBoundsClassifyHiddenAndAlwaysHidden() {
        let bounds = MenuBarLaneBounds(
            toggleX: 1_400,
            primaryX: 1_200,
            secondaryX: 1_100,
            alwaysHiddenEnabled: true,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        XCTAssertTrue(bounds.geometryUsable)
        XCTAssertEqual(bounds.lane(forItemMidX: 1_050), .alwaysHidden)
        XCTAssertEqual(bounds.lane(forItemMidX: 1_250), .hidden)
        XCTAssertEqual(bounds.lane(forItemMidX: 1_450), .visible)
        XCTAssertTrue(bounds.isRevealCandidate(itemMinX: 1_240, itemMaxX: 1_260, itemMidX: 1_250))
        XCTAssertFalse(bounds.isRevealCandidate(itemMinX: 1_440, itemMaxX: 1_460, itemMidX: 1_450))
    }

    func testLaneBoundsUnusableWhenMarkersOffScreen() {
        let bounds = MenuBarLaneBounds(
            toggleX: -3_772,
            primaryX: -3_780,
            secondaryX: nil,
            alwaysHiddenEnabled: false,
            screenMinX: 0,
            screenMaxX: 1_496
        )
        XCTAssertFalse(bounds.geometryUsable)
    }

    // MARK: - Accessibility gate + restore queue (HB-001/002/003)

    func testAccessibilityGatePlacementRequiresTrust() {
        XCTAssertTrue(AccessibilityGatePolicy.canAttemptPlacementHide(trusted: true))
        XCTAssertFalse(AccessibilityGatePolicy.canAttemptPlacementHide(trusted: false))
    }

    func testAccessibilityGatePromptOncePerSession() {
        XCTAssertTrue(
            AccessibilityGatePolicy.shouldPromptOnCollapseRejection(
                trusted: false,
                alreadyPromptedThisSession: false
            )
        )
        XCTAssertFalse(
            AccessibilityGatePolicy.shouldPromptOnCollapseRejection(
                trusted: false,
                alreadyPromptedThisSession: true
            )
        )
        XCTAssertFalse(
            AccessibilityGatePolicy.shouldPromptOnCollapseRejection(
                trusted: true,
                alreadyPromptedThisSession: false
            )
        )
    }

    func testParkRestoreQueueEnqueueTakeRequeue() {
        var q = ParkRestoreQueue()
        q.enqueue([10, 20, 10])  // dedupe
        XCTAssertEqual(q.pending, [10, 20])
        XCTAssertTrue(ParkRestoreQueue.canDrain(accessibilityTrusted: true, pendingCount: q.pending.count))
        XCTAssertFalse(ParkRestoreQueue.canDrain(accessibilityTrusted: false, pendingCount: q.pending.count))

        let batch = q.takeAll()
        XCTAssertEqual(batch, [10, 20])
        XCTAssertTrue(q.isEmpty)

        // Failed drain requeues (e.g. AX missing).
        q.requeue([20])
        XCTAssertEqual(q.pending, [20])
        q.enqueue([30])
        XCTAssertEqual(q.pending, [20, 30])
    }

    // MARK: - Drain policy (adapter decisions — no thrash / no silent loss)

    func testDrainPreflightAXDeniedDefersWholeBatch() {
        let batch: [UInt32] = [1, 2, 3]
        let pf = ParkRestoreDrainPolicy.preflight(
            batchCount: batch.count,
            accessibilityTrusted: false,
            hasAnchor: true
        )
        XCTAssertEqual(pf, .deferred(.accessibilityRequired))
        let outcome = ParkRestoreDrainPolicy.outcomeForPreflight(pf, batch: batch)!
        XCTAssertEqual(outcome.requeue, batch)
        XCTAssertFalse(outcome.allowAutoReschedule)
        XCTAssertEqual(outcome.deferred, .accessibilityRequired)
        // Pending stays; must not auto-loop.
        XCTAssertFalse(
            ParkRestoreDrainPolicy.shouldAutoReschedule(outcome: outcome, queueHasPending: true)
        )
    }

    func testDrainPreflightNoAnchorDefersNoAutoReschedule() {
        let batch: [UInt32] = [9]
        let pf = ParkRestoreDrainPolicy.preflight(
            batchCount: 1,
            accessibilityTrusted: true,
            hasAnchor: false
        )
        let outcome = ParkRestoreDrainPolicy.outcomeForPreflight(pf, batch: batch)!
        XCTAssertEqual(outcome.deferred, .noAnchor)
        XCTAssertFalse(outcome.allowAutoReschedule)
        XCTAssertFalse(
            ParkRestoreDrainPolicy.shouldAutoReschedule(outcome: outcome, queueHasPending: true)
        )
    }

    func testDrainCancelMidBatchRequeuesUnmovedOnly() {
        let batch: [UInt32] = [10, 20, 30]
        // First item restored; cancel before 20/30.
        let outcome = ParkRestoreDrainPolicy.outcomeAfterMoves(
            batch: batch,
            succeededIndices: [0],
            cancelled: true
        )
        XCTAssertEqual(outcome.requeue, [20, 30])
        XCTAssertEqual(outcome.restoredCount, 1)
        XCTAssertFalse(outcome.allowAutoReschedule)
        XCTAssertFalse(
            ParkRestoreDrainPolicy.shouldAutoReschedule(outcome: outcome, queueHasPending: true)
        )
    }

    func testDrainMoveFailuresRequeueFailedNoBusyLoop() {
        let batch: [UInt32] = [1, 2, 3]
        // 0 and 2 succeed; 1 fails.
        let outcome = ParkRestoreDrainPolicy.outcomeAfterMoves(
            batch: batch,
            succeededIndices: [0, 2],
            cancelled: false
        )
        XCTAssertEqual(outcome.requeue, [2])  // wait: indices 0 and 2 succeeded, index 1 is id 2
        // batch[0]=1 ok, batch[1]=2 fail, batch[2]=3 ok → requeue [2]
        XCTAssertEqual(Set(outcome.requeue), Set([UInt32(2)]))
        XCTAssertEqual(outcome.restoredCount, 2)
        XCTAssertFalse(outcome.allowAutoReschedule)
        // Simulate adapter requeue into queue then ask for auto-reschedule → false.
        var q = ParkRestoreQueue()
        q.requeue(outcome.requeue)
        XCTAssertFalse(
            ParkRestoreDrainPolicy.shouldAutoReschedule(
                outcome: outcome,
                queueHasPending: !q.isEmpty
            )
        )
    }

    func testDrainAllRestoredAllowsCoalesceWhenNewPending() {
        let outcome = ParkRestoreDrainPolicy.outcomeAfterMoves(
            batch: [1, 2],
            succeededIndices: [0, 1],
            cancelled: false
        )
        XCTAssertTrue(outcome.requeue.isEmpty)
        XCTAssertTrue(outcome.allowAutoReschedule)
        XCTAssertTrue(
            ParkRestoreDrainPolicy.shouldAutoReschedule(outcome: outcome, queueHasPending: true)
        )
        XCTAssertFalse(
            ParkRestoreDrainPolicy.shouldAutoReschedule(outcome: outcome, queueHasPending: false)
        )
    }

    func testMayStartDrainBlocksWhenDeferredUnlessExplicitRetry() {
        XCTAssertFalse(
            ParkRestoreDrainPolicy.mayStartDrain(
                reason: "restore_coalesce",
                queueHasPending: true,
                isDeferredLatched: true,
                workerAlreadyRunning: false
            )
        )
        XCTAssertTrue(
            ParkRestoreDrainPolicy.mayStartDrain(
                reason: "menu_retry",
                queueHasPending: true,
                isDeferredLatched: true,
                workerAlreadyRunning: false
            )
        )
        XCTAssertTrue(
            ParkRestoreDrainPolicy.mayStartDrain(
                reason: "after_accessibility_prompt",
                queueHasPending: true,
                isDeferredLatched: true,
                workerAlreadyRunning: false
            )
        )
        // AX-denied path: one deferred outcome then latch — no second auto start.
        XCTAssertFalse(
            ParkRestoreDrainPolicy.mayStartDrain(
                reason: "restore_coalesce",
                queueHasPending: true,
                isDeferredLatched: true,
                workerAlreadyRunning: false
            )
        )
        XCTAssertFalse(
            ParkRestoreDrainPolicy.mayStartDrain(
                reason: "menu_retry",
                queueHasPending: true,
                isDeferredLatched: true,
                workerAlreadyRunning: true
            )
        )
    }

    /// End-to-end pure simulation of the adapter loop the skeptic required:
    /// take → AX deny → requeue once → no auto-reschedule thrash.
    func testSimulatedDrainAdapterAXDeniedKeepsPendingOnce() {
        var q = ParkRestoreQueue()
        var deferredLatch = false
        var autoStarts = 0

        func tryStart(reason: String) -> Bool {
            let may = ParkRestoreDrainPolicy.mayStartDrain(
                reason: reason,
                queueHasPending: !q.isEmpty,
                isDeferredLatched: deferredLatch,
                workerAlreadyRunning: false
            )
            guard may else { return false }
            autoStarts += 1
            if ParkRestoreDrainPolicy.isExplicitRetryReason(reason) {
                deferredLatch = false
            }
            // one drain
            let batch = q.takeAll()
            let pf = ParkRestoreDrainPolicy.preflight(
                batchCount: batch.count,
                accessibilityTrusted: false,
                hasAnchor: true
            )
            let outcome = ParkRestoreDrainPolicy.outcomeForPreflight(pf, batch: batch)!
            q.requeue(outcome.requeue)
            if outcome.deferred != nil { deferredLatch = true }
            if ParkRestoreDrainPolicy.shouldAutoReschedule(
                outcome: outcome,
                queueHasPending: !q.isEmpty
            ) {
                _ = tryStart(reason: "restore_coalesce")
            }
            return true
        }

        q.enqueue([100, 200])
        XCTAssertTrue(tryStart(reason: "expand_restore"))
        XCTAssertEqual(q.pending, [100, 200])
        XCTAssertTrue(deferredLatch)
        XCTAssertEqual(autoStarts, 1)
        // Coalesce must not thrash.
        XCTAssertFalse(tryStart(reason: "restore_coalesce"))
        XCTAssertEqual(autoStarts, 1)
        XCTAssertEqual(q.pending, [100, 200])
    }
}
