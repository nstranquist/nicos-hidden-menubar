import CoreGraphics
import Foundation

/// Pure overflow / under-notch rescue policy (snapshot in → candidates / refusals).
///
/// Live Cmd-drag is an I/O adapter. This planner never talks to AppKit, never
/// runs collapse, and returns an empty candidate set when the user has not
/// opted in or when geometry / permissions / movement are unavailable.
enum OverflowRescuePlanner {
    static let destinationGap: Double = 4
    static let stripSlop: Double = MenuBarOverflowLayout.containmentSlop

    struct Item: Equatable, Sendable {
        var identityKey: String
        var windowID: UInt32
        var namespace: String
        var ownerName: String
        var title: String
        var frame: CGRect
        var ownerPID: Int32
    }

    struct Snapshot: Equatable, Sendable {
        var items: [Item]
        var hideSeparatorX: Double?
        var hideSeparatorWindowID: UInt32?
        var laneBounds: MenuBarLaneBounds
        var notch: NotchBandGeometry?
        var overflow: MenuBarOverflowLayout?
        var ownPIDs: Set<Int32>
        var recentUserMoveIDs: Set<String>
        var alreadyRescuedIDs: Set<String>
        var rescueEnabled: Bool
        var movementEnabled: Bool
        var notchSupportEnabled: Bool
        var permissionsGranted: Bool
        var geometryReadable: Bool
    }

    enum RefuseReason: String, Equatable, Sendable {
        case optInOff
        case movementDisabled
        case permissionsMissing
        case geometryUnreadable
        case notchSupportOff
        case notOverflow
        case alreadyInRightStrip
        case hiddenBarChrome
        case backdrop
        case immovable
        case leftBandGhost
        case recentUserMove
        case alreadyRescued
        case destinationUnusable
    }

    struct Destination: Equatable, Sendable {
        /// Hide-separator x; item should land just left, fully in the right strip.
        var hideSeparatorX: Double
        var hideSeparatorWindowID: UInt32?
        var expectedMinX: Double
        var expectedMaxX: Double
    }

    struct Candidate: Equatable, Sendable {
        var identityKey: String
        var windowID: UInt32
        var frame: CGRect
        var destination: Destination
    }

    struct Refusal: Equatable, Sendable {
        var identityKey: String
        var reason: RefuseReason
    }

    struct Decision: Equatable, Sendable {
        var candidates: [Candidate]
        var refusals: [Refusal]

        static let empty = Decision(candidates: [], refusals: [])
    }

    enum AttemptResult: Equatable, Sendable {
        case success
        case rollbackRequired
        case unverified
    }

    static func decide(_ snapshot: Snapshot) -> Decision {
        if let closed = failClosed(snapshot) {
            return Decision(candidates: [], refusals: closed)
        }

        var candidates: [Candidate] = []
        var refusals: [Refusal] = []

        for item in snapshot.items {
            switch classify(item, snapshot: snapshot) {
            case .refuse(let reason):
                refusals.append(Refusal(identityKey: item.identityKey, reason: reason))
            case .rescue(let destination):
                candidates.append(
                    Candidate(
                        identityKey: item.identityKey,
                        windowID: item.windowID,
                        frame: item.frame,
                        destination: destination
                    )
                )
            }
        }
        return Decision(candidates: candidates, refusals: refusals)
    }

    /// Post-move success: fully inside the right usable strip, no longer
    /// overflow / under-notch, and in the planned hidden-lane band when one
    /// was computed. Missing frame or unreadable bands ⇒ fail closed.
    static func isSuccessfulRescue(
        postMove: CGRect?,
        overflow: MenuBarOverflowLayout?,
        notch: NotchBandGeometry?,
        destination: Destination? = nil
    ) -> Bool {
        guard let postMove else { return false }
        guard let overflow, fullyInRightStrip(postMove, overflow: overflow) else {
            return false
        }
        if overflow.isOverflow(
            itemMinX: postMove.minX,
            itemMaxX: postMove.maxX,
            itemMidX: postMove.midX
        ) {
            return false
        }
        if let notch,
            notch.isUnderNotch(
                itemMinX: postMove.minX,
                itemMaxX: postMove.maxX,
                itemMidX: postMove.midX
            )
        {
            return false
        }
        if let destination {
            return MenuBarMoveMatch.matchesHiddenLane(
                item: postMove,
                expectedMinX: destination.expectedMinX,
                expectedMaxX: destination.expectedMaxX
            )
        }
        return true
    }

    static func evaluateAttempt(
        postMove: CGRect?,
        overflow: MenuBarOverflowLayout?,
        notch: NotchBandGeometry?,
        destination: Destination? = nil
    ) -> AttemptResult {
        guard postMove != nil else { return .unverified }
        if isSuccessfulRescue(
            postMove: postMove,
            overflow: overflow,
            notch: notch,
            destination: destination
        ) {
            return .success
        }
        return .rollbackRequired
    }

    static func hiddenLaneDestination(
        itemWidth: Double,
        hideSeparatorX: Double,
        overflow: MenuBarOverflowLayout
    ) -> Destination? {
        guard let rMin = overflow.rightUsableMinX, let rMax = overflow.rightUsableMaxX else {
            return nil
        }
        guard rMax > rMin + 8, itemWidth > 0 else { return nil }
        let expectedMaxX = hideSeparatorX - destinationGap
        let expectedMinX = expectedMaxX - itemWidth
        guard expectedMinX >= rMin - stripSlop, expectedMaxX <= rMax + stripSlop else {
            return nil
        }
        guard expectedMinX + stripSlop >= rMin else { return nil }
        return Destination(
            hideSeparatorX: hideSeparatorX,
            hideSeparatorWindowID: nil,
            expectedMinX: expectedMinX,
            expectedMaxX: expectedMaxX
        )
    }

    // MARK: - Internals

    private enum Classification {
        case refuse(RefuseReason)
        case rescue(Destination)
    }

    private static func failClosed(_ snapshot: Snapshot) -> [Refusal]? {
        if !snapshot.rescueEnabled {
            return [Refusal(identityKey: "*", reason: .optInOff)]
        }
        if !snapshot.movementEnabled {
            return [Refusal(identityKey: "*", reason: .movementDisabled)]
        }
        if !snapshot.permissionsGranted {
            return [Refusal(identityKey: "*", reason: .permissionsMissing)]
        }
        if !snapshot.notchSupportEnabled {
            return [Refusal(identityKey: "*", reason: .notchSupportOff)]
        }
        if !snapshot.geometryReadable
            || snapshot.hideSeparatorX == nil
            || snapshot.overflow == nil
            || snapshot.overflow?.rightUsableMinX == nil
            || snapshot.overflow?.rightUsableMaxX == nil
        {
            return [Refusal(identityKey: "*", reason: .geometryUnreadable)]
        }
        return nil
    }

    private static func classify(_ item: Item, snapshot: Snapshot) -> Classification {
        if isBackdrop(ownerName: item.ownerName, title: item.title, width: item.frame.width) {
            return .refuse(.backdrop)
        }
        if isHiddenBarChrome(namespace: item.namespace, ownerName: item.ownerName)
            || snapshot.ownPIDs.contains(item.ownerPID)
        {
            return .refuse(.hiddenBarChrome)
        }
        if isImmovable(namespace: item.namespace) {
            return .refuse(.immovable)
        }
        if matchesSessionID(item, in: snapshot.recentUserMoveIDs) {
            return .refuse(.recentUserMove)
        }
        if matchesSessionID(item, in: snapshot.alreadyRescuedIDs) {
            return .refuse(.alreadyRescued)
        }

        guard let overflow = snapshot.overflow, let hideSeparatorX = snapshot.hideSeparatorX else {
            return .refuse(.geometryUnreadable)
        }

        if isLeftBandGhost(item: item, overflow: overflow) {
            return .refuse(.leftBandGhost)
        }

        if fullyInRightStrip(item.frame, overflow: overflow) {
            return .refuse(.alreadyInRightStrip)
        }

        let section = RevealPanelClassifier.section(
            itemMinX: item.frame.minX,
            itemMaxX: item.frame.maxX,
            itemMidX: item.frame.midX,
            laneBounds: snapshot.laneBounds,
            notch: snapshot.notch,
            overflow: overflow,
            notchSupportEnabled: snapshot.notchSupportEnabled,
            isParked: false
        )
        guard section == .overflow else {
            return .refuse(.notOverflow)
        }

        guard
            var destination = hiddenLaneDestination(
                itemWidth: item.frame.width,
                hideSeparatorX: hideSeparatorX,
                overflow: overflow
            )
        else {
            return .refuse(.destinationUnusable)
        }
        destination.hideSeparatorWindowID = snapshot.hideSeparatorWindowID
        return .rescue(destination)
    }

    /// Session keys are identity keys *or* window IDs so a later title
    /// assignment cannot drop a cooldown / already-rescued mark.
    private static func matchesSessionID(_ item: Item, in ids: Set<String>) -> Bool {
        ids.contains(item.identityKey) || ids.contains(String(item.windowID))
    }

    private static func fullyInRightStrip(_ frame: CGRect, overflow: MenuBarOverflowLayout) -> Bool {
        guard let rMin = overflow.rightUsableMinX, let rMax = overflow.rightUsableMaxX else {
            return false
        }
        return frame.minX >= rMin - stripSlop && frame.maxX <= rMax + stripSlop
    }

    private static func isLeftBandGhost(item: Item, overflow: MenuBarOverflowLayout) -> Bool {
        guard let leftMax = overflow.leftUsableMaxX else { return false }
        return item.frame.midX < leftMax - 4
    }

    private static func isHiddenBarChrome(namespace: String, ownerName: String) -> Bool {
        let ns = namespace.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ns.contains("nicos-hidden-menubar") { return true }
        if owner.contains("nicos hidden bar") || owner.contains("nicoshiddenmenubar") {
            return true
        }
        if RevealPanelItemQuality.junkNamespaces.contains(ns) { return true }
        if RevealPanelItemQuality.junkOwnerNames.contains(owner) { return true }
        return false
    }

    private static func isBackdrop(ownerName: String, title: String, width: Double) -> Bool {
        if ownerName == "Window Server", title == "Menubar" { return true }
        // Full-width menubar chrome that only looks under-notch because its
        // frame spans the camera housing.
        if width > RevealPanelItemQuality.maxStatusItemWidth { return true }
        return false
    }

    private static func isImmovable(namespace: String) -> Bool {
        if MenuBarItemInfo.immovableNamespaces.contains(namespace) { return true }
        if MenuBarItemInfo.nonHideableNamespaces.contains(namespace) { return true }
        if namespace.hasPrefix("com.apple.controlcenter") { return true }
        if namespace == "com.apple.Siri" { return true }
        return false
    }
}
