import AppKit
import CoreGraphics
import Foundation

/// Pure destination / origin match used by `MenuBarItemMover`. Tests drive
/// these predicates directly — the live mover must not have a private copy.
enum MenuBarMoveMatch {
    static let hiddenLaneSlop: Double = 12
    static let originTolerance: Double = 8

    static func matchesLeftOf(item: CGRect, target: CGRect) -> Bool {
        item.maxX <= target.minX + 4 || item.midX < target.midX
    }

    static func matchesRightOf(item: CGRect, target: CGRect) -> Bool {
        item.minX + 4 >= target.maxX || item.midX > target.midX
    }

    /// Collapse park: at or past `x` (one-sided). Not valid for origin restore.
    static func matchesAbsoluteAtOrPast(item: CGRect, x: Double) -> Bool {
        Double(item.minX) >= x - 16 || Double(item.midX) >= x - 10
    }

    /// Hidden-lane band from the rescue planner. An under-gap extra (x=753)
    /// is left of the hide separator but not in this band.
    static func matchesHiddenLane(item: CGRect, expectedMinX: Double, expectedMaxX: Double) -> Bool {
        let slop = hiddenLaneSlop
        return Double(item.minX) >= expectedMinX - slop
            && Double(item.maxX) <= expectedMaxX + slop
    }

    /// Two-sided restore: both minX and midX must sit on the pre-move frame.
    static func matchesOrigin(item: CGRect, origin: CGRect, tolerance: Double = originTolerance) -> Bool {
        abs(Double(item.minX) - Double(origin.minX)) <= tolerance
            && abs(Double(item.midX) - Double(origin.midX)) <= tolerance
    }
}

// MARK: - Movement engine
//
// Port of Ice's MenuBarItemManager technique: synthesize Cmd+drag to move a
// menu-bar item. Collapse-time hide is a first-class product path.
//
// Cursor safety (critical):
// - CGDisplayHideCursor is **reference-counted**. Nested hide/show mismatches
//   leave the pointer invisible forever.
// - Synthetic events can move the real cursor to park points (menu-bar top).
// - We therefore: never nest hides, always force-restore + reassociate after
//   every move attempt, and always post a bare mouseUp to cancel a stuck grab.

enum MenuBarItemMover {
    enum MoveError: Error, Equatable {
        case notEnabled
        case missingItem
        case missingTarget
        case eventSource
        case eventCreation
        case notMovable
        case timedOut
        case cancelled
        case unobserved
    }

    enum Destination: Equatable {
        case leftOf(targetWindowID: CGWindowID)
        case rightOf(targetWindowID: CGWindowID)
        /// Park past the visible menu-bar edge (collapse-time hide).
        case absolute(x: Double, y: Double)
        /// Two-sided restore of a pre-move frame (overflow-rescue rollback).
        case restoreOrigin(CGRect)
        /// Hidden lane: drop left of the hide separator, but only *match*
        /// when the item is in the planned band — not merely anywhere left
        /// of the separator (an under-gap extra at x=753 already is).
        case hiddenLane(separatorWindowID: CGWindowID, expectedMinX: Double, expectedMaxX: Double)
    }

    struct Options: Equatable, Sendable {
        var maxAttempts: Int
        var settleMilliseconds: UInt64
        var timeoutMilliseconds: UInt64
        var grabWaitMilliseconds: UInt64

        static let `default` = Options(
            maxAttempts: 4,
            settleMilliseconds: 80,
            timeoutMilliseconds: 2_000,
            grabWaitMilliseconds: 100
        )

        /// Collapse-time hide — patient but still bounded (avoid multi-second cursor thrash).
        static let placementHide = Options(
            maxAttempts: 4,
            settleMilliseconds: 90,
            timeoutMilliseconds: 2_400,
            grabWaitMilliseconds: 110
        )
    }

    /// Move `windowID` to the given destination with bounded retry/timeout.
    @MainActor
    static func move(
        windowID: CGWindowID,
        to destination: Destination,
        enabled: Bool,
        options: Options = .default
    ) async throws {
        guard enabled else { throw MoveError.notEnabled }

        guard let item = MenuBarWindowInfo.read(windowID: windowID) else {
            throw MoveError.missingItem
        }
        guard !item.info.isLikelyImmovable else {
            throw MoveError.notMovable
        }

        if frameMatchesDestination(windowID: windowID, destination: destination) {
            return
        }

        let originFrame = item.frame
        let userCursor = MouseCursorBridge.location
        let deadline = ContinuousClock.now + .milliseconds(Int64(options.timeoutMilliseconds))
        var lastError: MoveError = .unobserved

        // Disconnect hardware mouse from cursor while we synthesize events, then
        // always reassociate + warp back — even on throw/cancel.
        defer {
            cancelStuckDrag(windowID: windowID, pid: item.ownerPID, at: userCursor)
            MouseCursorBridge.forceRestore(to: userCursor)
        }

        for attempt in 1...max(1, options.maxAttempts) {
            if Task.isCancelled { throw MoveError.cancelled }
            if ContinuousClock.now >= deadline { throw MoveError.timedOut }

            do {
                try await performSingleMove(
                    windowID: windowID,
                    to: destination,
                    grabWaitMilliseconds: options.grabWaitMilliseconds,
                    restoreCursor: userCursor
                )
                try await Task.sleep(for: .milliseconds(options.settleMilliseconds))
                if frameMatchesDestination(windowID: windowID, destination: destination) {
                    return
                }
                lastError = .unobserved
            } catch let error as MoveError {
                lastError = error
                cancelStuckDrag(windowID: windowID, pid: item.ownerPID, at: userCursor)
                if error == .missingTarget || error == .notMovable || error == .notEnabled {
                    throw error
                }
            }

            if attempt < options.maxAttempts {
                // No wake-up click — it posts events at the item and yanks the cursor
                // into the menu bar. Retries alone are enough.
                try? await Task.sleep(for: .milliseconds(35))
            }
        }

        // Best-effort rollback if we drifted without matching destination.
        if let current = MenuBarWindowInfo.read(windowID: windowID),
            abs(current.frame.minX - originFrame.minX) > 2
        {
            switch destination {
            case .absolute:
                try? await performSingleMove(
                    windowID: windowID,
                    to: .absolute(x: Double(originFrame.midX), y: Double(originFrame.midY)),
                    grabWaitMilliseconds: 40,
                    restoreCursor: userCursor
                )
            case .leftOf, .rightOf:
                let rollback: Destination =
                    current.frame.minX < originFrame.minX
                    ? .rightOf(targetWindowID: targetWindowID(for: destination))
                    : .leftOf(targetWindowID: targetWindowID(for: destination))
                try? await performSingleMove(
                    windowID: windowID,
                    to: rollback,
                    grabWaitMilliseconds: 40,
                    restoreCursor: userCursor
                )
            case .hiddenLane:
                try? await performSingleMove(
                    windowID: windowID,
                    to: .restoreOrigin(originFrame),
                    grabWaitMilliseconds: 40,
                    restoreCursor: userCursor
                )
            case .restoreOrigin:
                break
            }
            cancelStuckDrag(windowID: windowID, pid: item.ownerPID, at: userCursor)
        }

        if ContinuousClock.now >= deadline {
            throw MoveError.timedOut
        }
        throw lastError
    }

    // MARK: - Single attempt

    @MainActor
    private static func performSingleMove(
        windowID: CGWindowID,
        to destination: Destination,
        grabWaitMilliseconds: UInt64,
        restoreCursor: CGPoint?
    ) async throws {
        guard let item = MenuBarWindowInfo.read(windowID: windowID) else {
            throw MoveError.missingItem
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw MoveError.eventSource
        }

        let endPoint = try endPoint(for: destination)
        // Far off-screen grab point (Ice). Still targets WindowServer item move
        // via window-id fields — we disconnect the hardware cursor first.
        let startPoint = CGPoint(x: 20_000, y: 20_000)
        let releaseWindowID: CGWindowID = {
            switch destination {
            case .absolute, .restoreOrigin: return windowID
            case .leftOf, .rightOf, .hiddenLane: return targetWindowID(for: destination)
            }
        }()
        let originFrame = item.frame

        guard
            let mouseDown = CGEvent.menuBarMoveEvent(
                phase: .down, location: startPoint, windowID: windowID, pid: item.ownerPID, source: source
            ),
            let mouseUp = CGEvent.menuBarMoveEvent(
                phase: .up, location: endPoint, windowID: releaseWindowID, pid: item.ownerPID, source: source
            )
        else {
            throw MoveError.eventCreation
        }

        permitAllEvents(source: source)
        if let combined = CGEventSource(stateID: .combinedSessionState) {
            permitAllEvents(source: combined)
        }

        // Disconnect so trackpad motion doesn't fight warps; never hide the cursor
        // (hide is refcounted and was leaving it stuck/invisible).
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        defer {
            cancelStuckDrag(windowID: windowID, pid: item.ownerPID, at: restoreCursor)
            MouseCursorBridge.forceRestore(to: restoreCursor)
        }

        await postMenuBarEvent(mouseDown, toOwnerPID: item.ownerPID)
        // Do not warp between mouseDown and mouseUp. The software cursor is the
        // active drag location while hardware movement is disassociated; moving
        // it back early cancels the WindowServer grab before the item frame can
        // change. The defer below restores it on every exit path.
        await waitForFrameChange(
            windowID: windowID,
            origin: originFrame,
            timeoutMilliseconds: grabWaitMilliseconds
        )
        await postMenuBarEvent(mouseUp, toOwnerPID: item.ownerPID)
        try? await Task.sleep(for: .milliseconds(12))
    }

    /// WindowServer menu extras need both session routing and direct owner
    /// delivery. Ice synchronizes the same two deliveries with event taps; this
    /// bounded form keeps our retry/verification owner while avoiding a second
    /// long-lived tap graph.
    @MainActor
    private static func postMenuBarEvent(_ event: CGEvent, toOwnerPID pid: pid_t) async {
        event.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(4))
        event.postToPid(pid)
    }

    /// Post a non-Command leftMouseUp so WindowServer drops a half-finished grab.
    @MainActor
    private static func cancelStuckDrag(windowID: CGWindowID, pid: pid_t, at location: CGPoint?) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let loc = location ?? MouseCursorBridge.location ?? .zero
        if let up = CGEvent.menuBarMoveEvent(
            phase: .up, location: loc, windowID: windowID, pid: pid, source: source
        ) {
            up.flags = []
            up.post(tap: .cgSessionEventTap)
        }
    }

    @MainActor
    private static func waitForFrameChange(
        windowID: CGWindowID,
        origin: CGRect,
        timeoutMilliseconds: UInt64
    ) async {
        let deadline = ContinuousClock.now + .milliseconds(Int64(timeoutMilliseconds))
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return }
            if let frame = MenuBarBridging.frame(for: windowID),
                abs(frame.minX - origin.minX) > 0.5 || abs(frame.midX - origin.midX) > 0.5
            {
                return
            }
            try? await Task.sleep(for: .milliseconds(12))
        }
    }

    private static func frameMatchesDestination(
        windowID: CGWindowID,
        destination: Destination
    ) -> Bool {
        guard let itemFrame = MenuBarBridging.frame(for: windowID) else {
            return false
        }
        switch destination {
        case .leftOf(let targetID):
            guard let targetFrame = MenuBarBridging.frame(for: targetID) else { return false }
            return MenuBarMoveMatch.matchesLeftOf(item: itemFrame, target: targetFrame)
        case .rightOf(let targetID):
            guard let targetFrame = MenuBarBridging.frame(for: targetID) else { return false }
            return MenuBarMoveMatch.matchesRightOf(item: itemFrame, target: targetFrame)
        case .absolute(let x, _):
            return MenuBarMoveMatch.matchesAbsoluteAtOrPast(item: itemFrame, x: x)
        case .restoreOrigin(let origin):
            return MenuBarMoveMatch.matchesOrigin(item: itemFrame, origin: origin)
        case .hiddenLane(_, let expectedMinX, let expectedMaxX):
            return MenuBarMoveMatch.matchesHiddenLane(
                item: itemFrame,
                expectedMinX: expectedMinX,
                expectedMaxX: expectedMaxX
            )
        }
    }

    // MARK: Geometry

    private static func targetWindowID(for destination: Destination) -> CGWindowID {
        switch destination {
        case .leftOf(let id), .rightOf(let id), .hiddenLane(let id, _, _): return id
        case .absolute, .restoreOrigin: return 0
        }
    }

    private static func endPoint(for destination: Destination) throws -> CGPoint {
        switch destination {
        case .leftOf(let targetID), .hiddenLane(let targetID, _, _):
            guard let frame = MenuBarBridging.frame(for: targetID) else {
                throw MoveError.missingTarget
            }
            return CGPoint(x: frame.minX, y: frame.midY)
        case .rightOf(let targetID):
            guard let frame = MenuBarBridging.frame(for: targetID) else {
                throw MoveError.missingTarget
            }
            return CGPoint(x: frame.maxX, y: frame.midY)
        case .absolute(let x, let y):
            return CGPoint(x: x, y: y)
        case .restoreOrigin(let origin):
            return CGPoint(x: origin.midX, y: origin.midY)
        }
    }

    private static func permitAllEvents(source: CGEventSource) {
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
                state: state
            )
        }
        source.localEventsSuppressionInterval = 0
    }
}

// MARK: - CGEvent constructor (ported from Ice)

private extension CGEventField {
    static let windowIDField = CGEventField(rawValue: 0x33)!
}

private extension CGEvent {
    enum MovePhase { case down, up }

    class func menuBarMoveEvent(
        phase: MovePhase,
        location: CGPoint,
        windowID: CGWindowID,
        pid: pid_t,
        source: CGEventSource
    ) -> CGEvent? {
        let mouseType: CGEventType = (phase == .down) ? .leftMouseDown : .leftMouseUp
        guard
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: mouseType,
                mouseCursorPosition: location,
                mouseButton: .left
            )
        else {
            return nil
        }

        event.flags = (phase == .down) ? .maskCommand : []

        let wid = Int64(windowID)
        let userData = Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(event)))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.eventSourceUserData, value: userData)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: wid)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: wid)
        event.setIntegerValueField(.windowIDField, value: wid)
        return event
    }
}

// MARK: - Mouse cursor helpers (fail-safe)

enum MouseCursorBridge {
    static var location: CGPoint? {
        // Prefer AppKit Cocoa coords converted… but CGEvent is what we warp with.
        guard let event = CGEvent(source: nil) else { return nil }
        return event.location
    }

    /// Never use alone for multi-move sequences — prefer `forceRestore`.
    static func hide() {
        CGDisplayHideCursor(CGMainDisplayID())
    }

    static func show() {
        CGDisplayShowCursor(CGMainDisplayID())
    }

    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    /// Recover from stuck-invisible or teleported cursor after synthetic moves.
    /// `CGDisplayHideCursor` is refcounted — spam show() to drain the counter,
    /// re-associate hardware mouse, then warp back to the user's location.
    static func forceRestore(to point: CGPoint?) {
        for _ in 0..<16 {
            CGDisplayShowCursor(CGMainDisplayID())
        }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        if let point {
            CGWarpMouseCursorPosition(point)
            // Second warp after reassociate — some macOS builds ignore the first.
            CGWarpMouseCursorPosition(point)
        }
    }
}
