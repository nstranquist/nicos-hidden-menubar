import CoreGraphics
import XCTest
@testable import NicosHiddenMenuBar

final class OverflowRescuePlannerTests: XCTestCase {
    /// Matches NotchGeometryTests live-like 1496-pt built-in: left aux maxX≈668, right 828…1496.
    private let liveLikeNotch = NotchBandGeometry(
        leftUsableMaxX: 668,
        rightUsableMinX: 828,
        rightUsableMaxX: 1_496,
        screenMinX: 0,
        screenMaxX: 1_496
    )

    private let liveLikeOverflow = MenuBarOverflowLayout(
        leftUsableMaxX: 668,
        rightUsableMinX: 828,
        rightUsableMaxX: 1_496,
        visibleMaxX: 1_496,
        screenMinX: 0,
        screenMaxX: 1_496
    )

    private let liveLikeLanes = MenuBarLaneBounds(
        toggleX: 1_300,
        primaryX: 1_260,
        secondaryX: nil,
        alwaysHiddenEnabled: false,
        screenMinX: 0,
        screenMaxX: 1_496
    )

    func testShippedClassifierStillTreatsMidGapAsOverflowAndRightStripAsHidden() {
        XCTAssertTrue(
            liveLikeOverflow.isOverflow(itemMinX: 753, itemMaxX: 790, itemMidX: 771.5)
        )
        XCTAssertTrue(
            liveLikeNotch.isUnderNotch(itemMinX: 753, itemMaxX: 790, itemMidX: 771.5)
        )
        XCTAssertFalse(
            liveLikeOverflow.isOverflow(itemMinX: 871, itemMaxX: 895, itemMidX: 883)
        )
        let hiddenSection = RevealPanelClassifier.section(
            itemMinX: 852,
            itemMaxX: 890,
            itemMidX: 871,
            laneBounds: liveLikeLanes,
            notch: liveLikeNotch,
            overflow: liveLikeOverflow,
            notchSupportEnabled: true,
            isParked: false
        )
        XCTAssertEqual(hiddenSection, .hidden)
        XCTAssertFalse(
            liveLikeOverflow.isOverflow(itemMinX: 1_200, itemMaxX: 1_224, itemMidX: 1_212)
        )
        XCTAssertFalse(
            RevealPanelItemQuality.isUsablePanelItem(
                ownerName: "Menubar",
                namespace: "Menubar",
                displayName: "Menubar",
                frameWidth: 400,
                frameHeight: 24
            )
        )
    }

    func testOptInOffYieldsNoCandidates() {
        let snapshot = enabledSnapshot(items: [underGapScratchpad()])
        var off = snapshot
        off.rescueEnabled = false
        let decision = OverflowRescuePlanner.decide(off)
        XCTAssertTrue(decision.candidates.isEmpty)
        XCTAssertEqual(decision.refusals.map(\.reason), [.optInOff])
    }

    func testMovementDisabledPermissionsMissingGeometryUnreadableYieldNoCandidates() {
        let item = underGapScratchpad()
        var movement = enabledSnapshot(items: [item])
        movement.movementEnabled = false
        XCTAssertTrue(OverflowRescuePlanner.decide(movement).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(movement).refusals.first?.reason, .movementDisabled)

        var perms = enabledSnapshot(items: [item])
        perms.permissionsGranted = false
        XCTAssertTrue(OverflowRescuePlanner.decide(perms).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(perms).refusals.first?.reason, .permissionsMissing)

        var geometry = enabledSnapshot(items: [item])
        geometry.geometryReadable = false
        XCTAssertTrue(OverflowRescuePlanner.decide(geometry).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(geometry).refusals.first?.reason, .geometryUnreadable)

        var missingBands = enabledSnapshot(items: [item])
        missingBands.overflow = nil
        missingBands.hideSeparatorX = nil
        XCTAssertTrue(OverflowRescuePlanner.decide(missingBands).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(missingBands).refusals.first?.reason, .geometryUnreadable)
    }

    func testUnderGap753IsRescueCandidateWhenOptedIn() {
        let item = underGapScratchpad()
        let decision = OverflowRescuePlanner.decide(enabledSnapshot(items: [item]))
        XCTAssertEqual(decision.candidates.map(\.identityKey), [item.identityKey])
        XCTAssertEqual(decision.candidates.first?.windowID, item.windowID)
        XCTAssertEqual(decision.candidates.first?.destination.hideSeparatorX, 1_260)
        XCTAssertLessThan(decision.candidates.first?.destination.expectedMaxX ?? 0, 1_260)
        XCTAssertGreaterThanOrEqual(decision.candidates.first?.destination.expectedMinX ?? 0, 828 - 3)
    }

    func testSuccessfulHiddenLaneFrameIsNotACandidateAndCountsAsSuccess() {
        let rescued = hiddenLaneItem()
        let decision = OverflowRescuePlanner.decide(enabledSnapshot(items: [rescued]))
        XCTAssertTrue(decision.candidates.isEmpty)
        XCTAssertTrue(decision.refusals.contains { $0.identityKey == rescued.identityKey && $0.reason == .alreadyInRightStrip })
        XCTAssertTrue(
            OverflowRescuePlanner.isSuccessfulRescue(
                postMove: rescued.frame,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch
            )
        )
        XCTAssertEqual(
            OverflowRescuePlanner.evaluateAttempt(
                postMove: rescued.frame,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch
            ),
            .success
        )
    }

    func testPostMoveStillInGapRequiresRollback() {
        let stillGap = CGRect(x: 753, y: 4, width: 37, height: 24)
        XCTAssertFalse(
            OverflowRescuePlanner.isSuccessfulRescue(
                postMove: stillGap,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch
            )
        )
        XCTAssertEqual(
            OverflowRescuePlanner.evaluateAttempt(
                postMove: stillGap,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch
            ),
            .rollbackRequired
        )
        XCTAssertEqual(
            OverflowRescuePlanner.evaluateAttempt(
                postMove: nil,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch
            ),
            .unverified
        )
    }

    func testVisibleLaneOvershootIsNotSuccessfulRescue() throws {
        let dest = try XCTUnwrap(
            OverflowRescuePlanner.hiddenLaneDestination(
                itemWidth: 37,
                hideSeparatorX: 1_260,
                overflow: liveLikeOverflow
            )
        )
        let visible = CGRect(x: 1_350, y: 4, width: 37, height: 24)
        XCTAssertTrue(
            OverflowRescuePlanner.isSuccessfulRescue(
                postMove: visible,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch
            ),
            "without a planned band, right-strip visible is still 'not overflow'"
        )
        XCTAssertFalse(
            OverflowRescuePlanner.isSuccessfulRescue(
                postMove: visible,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch,
                destination: dest
            ),
            "rescue success requires the hidden-lane band, not any right-strip landing"
        )
        XCTAssertEqual(
            OverflowRescuePlanner.evaluateAttempt(
                postMove: visible,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch,
                destination: dest
            ),
            .rollbackRequired
        )
        let inLane = CGRect(x: 1_220, y: 4, width: 37, height: 24)
        XCTAssertEqual(
            OverflowRescuePlanner.evaluateAttempt(
                postMove: inLane,
                overflow: liveLikeOverflow,
                notch: liveLikeNotch,
                destination: dest
            ),
            .success
        )
    }

    func testAlreadyRescuedMatchesWindowIDAfterTitleKeyChanges() {
        let item = underGapScratchpad()
        var rescued = enabledSnapshot(items: [item])
        rescued.alreadyRescuedIDs = [String(item.windowID)]
        XCTAssertTrue(OverflowRescuePlanner.decide(rescued).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(rescued).refusals.first?.reason, .alreadyRescued)

        var recent = enabledSnapshot(items: [item])
        recent.recentUserMoveIDs = [String(item.windowID)]
        XCTAssertEqual(OverflowRescuePlanner.decide(recent).refusals.first?.reason, .recentUserMove)
    }

    func testRecentUserMoveAndAlreadyRescuedAreRefused() {
        let item = underGapScratchpad()
        var recent = enabledSnapshot(items: [item])
        recent.recentUserMoveIDs = [item.identityKey]
        XCTAssertTrue(OverflowRescuePlanner.decide(recent).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(recent).refusals.first?.reason, .recentUserMove)

        var rescued = enabledSnapshot(items: [item])
        rescued.alreadyRescuedIDs = [item.identityKey]
        XCTAssertTrue(OverflowRescuePlanner.decide(rescued).candidates.isEmpty)
        XCTAssertEqual(OverflowRescuePlanner.decide(rescued).refusals.first?.reason, .alreadyRescued)
    }

    func testImmovableAndBackdropAreRefused() {
        let cc = item(
            key: "cc",
            windowID: 8,
            namespace: "com.apple.controlcenter",
            ownerName: "Control Center",
            title: "Wi‑Fi",
            x: 753,
            width: 37
        )
        XCTAssertEqual(
            OverflowRescuePlanner.decide(enabledSnapshot(items: [cc])).refusals.first?.reason,
            .immovable
        )

        let siri = item(
            key: "siri",
            windowID: 9,
            namespace: "com.apple.Siri",
            ownerName: "Siri",
            title: "Siri",
            x: 753,
            width: 24
        )
        XCTAssertEqual(
            OverflowRescuePlanner.decide(enabledSnapshot(items: [siri])).refusals.first?.reason,
            .immovable
        )

        let backdrop = item(
            key: "backdrop",
            windowID: 10,
            namespace: "Menubar",
            ownerName: "Window Server",
            title: "Menubar",
            x: 0,
            width: 1_496
        )
        XCTAssertEqual(
            OverflowRescuePlanner.decide(enabledSnapshot(items: [backdrop])).refusals.first?.reason,
            .backdrop
        )

        let chrome = item(
            key: "hb",
            windowID: 11,
            namespace: "com.nstranquist.nicos-hidden-menubar",
            ownerName: "Nicos Hidden Bar",
            title: "Hidden",
            x: 753,
            width: 24
        )
        XCTAssertEqual(
            OverflowRescuePlanner.decide(enabledSnapshot(items: [chrome])).refusals.first?.reason,
            .hiddenBarChrome
        )
    }

    func testVisibleRightAndHiddenLaneAreNotRescueCandidates() {
        let visible = item(
            key: "visible",
            windowID: 12,
            namespace: "com.example.visible",
            ownerName: "Visible",
            title: "V",
            x: 1_200,
            width: 24
        )
        XCTAssertEqual(
            OverflowRescuePlanner.decide(enabledSnapshot(items: [visible])).refusals.first?.reason,
            .alreadyInRightStrip
        )

        let hiddenLane = item(
            key: "hidden",
            windowID: 13,
            namespace: "org.hammerspoon.Hammerspoon",
            ownerName: "Hammerspoon",
            title: "Hammerspoon",
            x: 852,
            width: 38
        )
        let hiddenDecision = OverflowRescuePlanner.decide(enabledSnapshot(items: [hiddenLane]))
        XCTAssertTrue(hiddenDecision.candidates.isEmpty)
        XCTAssertNotEqual(hiddenDecision.refusals.first?.reason, .optInOff)
    }

    func testLeftBandGhostRefused() {
        let ghost = item(
            key: "ghost",
            windowID: 14,
            namespace: "unknown",
            ownerName: "",
            title: "",
            x: 500,
            width: 33
        )
        XCTAssertEqual(
            OverflowRescuePlanner.decide(enabledSnapshot(items: [ghost])).refusals.first?.reason,
            .leftBandGhost
        )
    }

    func testHiddenLaneDestinationIsNotSatisfiedAt753ButIsAt1220() throws {
        let planned = OverflowRescuePlanner.hiddenLaneDestination(
            itemWidth: 37,
            hideSeparatorX: 1_260,
            overflow: liveLikeOverflow
        )
        let dest = try XCTUnwrap(planned)
        let underGap = CGRect(x: 753, y: 4, width: 37, height: 24)
        let inLane = CGRect(x: 1_220, y: 4, width: 37, height: 24)
        let separator = CGRect(x: 1_260, y: 0, width: 8, height: 24)

        XCTAssertFalse(
            MenuBarMoveMatch.matchesHiddenLane(
                item: underGap,
                expectedMinX: dest.expectedMinX,
                expectedMaxX: dest.expectedMaxX
            ),
            "under-gap 753 must not already satisfy the hidden-lane band"
        )
        XCTAssertTrue(
            MenuBarMoveMatch.matchesHiddenLane(
                item: inLane,
                expectedMinX: dest.expectedMinX,
                expectedMaxX: dest.expectedMaxX
            ),
            "1220/w=37 is the planned hidden-lane landing"
        )
        // Why .leftOf(separator) cannot be the rescue dest: 753 is already left of 1260.
        XCTAssertTrue(MenuBarMoveMatch.matchesLeftOf(item: underGap, target: separator))
        XCTAssertTrue(MenuBarMoveMatch.matchesLeftOf(item: inLane, target: separator))
    }

    func testOriginMatchIsTwoSidedAndRejectsRightwardDrift() {
        let origin = CGRect(x: 753, y: 4, width: 37, height: 24)
        XCTAssertTrue(MenuBarMoveMatch.matchesOrigin(item: origin, origin: origin))

        let stillInGap = CGRect(x: 780, y: 4, width: 37, height: 24)
        XCTAssertFalse(
            MenuBarMoveMatch.matchesOrigin(item: stillInGap, origin: origin),
            "753→780 is a half-move; two-sided origin must not accept it"
        )
        // The old one-sided absolute match (used for collapse park) would
        // treat any rightward drift as done — that is why rollback cannot use it.
        XCTAssertTrue(
            MenuBarMoveMatch.matchesAbsoluteAtOrPast(item: stillInGap, x: Double(origin.midX))
        )

        let pastEdge = CGRect(x: 1_500, y: 4, width: 37, height: 24)
        XCTAssertFalse(MenuBarMoveMatch.matchesOrigin(item: pastEdge, origin: origin))
        XCTAssertTrue(MenuBarMoveMatch.matchesAbsoluteAtOrPast(item: pastEdge, x: Double(origin.midX)))
    }

    func testRescueDecisionDoesNotUseCollapseSession() {
        // Structural: planner output is only Decision/Candidate/Refusal — no
        // PlacementHideSession / collapse commit. This test would not compile
        // if decide() returned a collapse plan.
        let decision = OverflowRescuePlanner.decide(enabledSnapshot(items: [underGapScratchpad()]))
        XCTAssertFalse(decision.candidates.isEmpty)
        XCTAssertNil(PlacementHideSession().planned.first)
    }

    func testTableDrivenGatingCases() {
        struct Row {
            var name: String
            var mutate: (inout OverflowRescuePlanner.Snapshot) -> Void
            var items: [OverflowRescuePlanner.Item]
            var expectCandidateKeys: [String]
            var expectReason: OverflowRescuePlanner.RefuseReason?
        }

        let gap = underGapScratchpad()
        let rows: [Row] = [
            Row(name: "flag off", mutate: { $0.rescueEnabled = false }, items: [gap], expectCandidateKeys: [], expectReason: .optInOff),
            Row(name: "753 under-gap", mutate: { _ in }, items: [gap], expectCandidateKeys: [gap.identityKey], expectReason: nil),
            Row(name: "hidden-lane", mutate: { _ in }, items: [hiddenLaneItem()], expectCandidateKeys: [], expectReason: .alreadyInRightStrip),
            Row(name: "visible", mutate: { _ in }, items: [item(key: "vis", windowID: 20, namespace: "com.example.v", ownerName: "V", title: "", x: 1_212, width: 24)], expectCandidateKeys: [], expectReason: .alreadyInRightStrip),
            Row(name: "chrome", mutate: { _ in }, items: [item(key: "chrome", windowID: 21, namespace: "com.nstranquist.nicos-hidden-menubar", ownerName: "Nicos Hidden Bar", title: "Hidden", x: 753, width: 24)], expectCandidateKeys: [], expectReason: .hiddenBarChrome),
            Row(name: "immovable", mutate: { _ in }, items: [item(key: "imm", windowID: 22, namespace: "com.apple.controlcenter", ownerName: "Control Center", title: "Focus", x: 753, width: 24)], expectCandidateKeys: [], expectReason: .immovable),
            Row(name: "cooldown", mutate: { $0.recentUserMoveIDs = [gap.identityKey] }, items: [gap], expectCandidateKeys: [], expectReason: .recentUserMove),
            Row(name: "already-rescued", mutate: { $0.alreadyRescuedIDs = [gap.identityKey] }, items: [gap], expectCandidateKeys: [], expectReason: .alreadyRescued),
            Row(name: "bad geometry", mutate: { $0.hideSeparatorX = nil; $0.overflow = nil }, items: [gap], expectCandidateKeys: [], expectReason: .geometryUnreadable),
        ]

        for row in rows {
            var snapshot = enabledSnapshot(items: row.items)
            row.mutate(&snapshot)
            let decision = OverflowRescuePlanner.decide(snapshot)
            XCTAssertEqual(
                decision.candidates.map(\.identityKey),
                row.expectCandidateKeys,
                row.name
            )
            if let reason = row.expectReason {
                XCTAssertEqual(decision.refusals.first?.reason, reason, row.name)
            }
        }
    }

    // MARK: - Fixtures

    private func enabledSnapshot(items: [OverflowRescuePlanner.Item]) -> OverflowRescuePlanner.Snapshot {
        OverflowRescuePlanner.Snapshot(
            items: items,
            hideSeparatorX: 1_260,
            hideSeparatorWindowID: 99,
            laneBounds: liveLikeLanes,
            notch: liveLikeNotch,
            overflow: liveLikeOverflow,
            ownPIDs: [1],
            recentUserMoveIDs: [],
            alreadyRescuedIDs: [],
            rescueEnabled: true,
            movementEnabled: true,
            notchSupportEnabled: true,
            permissionsGranted: true,
            geometryReadable: true
        )
    }

    private func underGapScratchpad() -> OverflowRescuePlanner.Item {
        item(
            key: "v1:com.nicos.nicos-scratchpad.MenuBarHelper:_:Scratchpad:0",
            windowID: 42,
            namespace: "com.nicos.nicos-scratchpad.MenuBarHelper",
            ownerName: "NicosScratchpadMenuBar",
            title: "Scratchpad",
            x: 753,
            width: 37
        )
    }

    private func hiddenLaneItem() -> OverflowRescuePlanner.Item {
        item(
            key: "rescued",
            windowID: 43,
            namespace: "com.nicos.nicos-scratchpad.MenuBarHelper",
            ownerName: "NicosScratchpadMenuBar",
            title: "Scratchpad",
            x: 1_220,
            width: 37
        )
    }

    private func item(
        key: String,
        windowID: UInt32,
        namespace: String,
        ownerName: String,
        title: String,
        x: Double,
        width: Double
    ) -> OverflowRescuePlanner.Item {
        OverflowRescuePlanner.Item(
            identityKey: key,
            windowID: windowID,
            namespace: namespace,
            ownerName: ownerName,
            title: title,
            frame: CGRect(x: x, y: 4, width: width, height: 24),
            ownerPID: 99
        )
    }
}
