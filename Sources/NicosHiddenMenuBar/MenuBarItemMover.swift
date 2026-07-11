import AppKit
import CoreGraphics
import Foundation

// MARK: - Movement engine (EXPERIMENTAL, opt-in)
//
// Faithful port of the core technique from Ice's `MenuBarItemManager`: move any
// app's menu bar item by synthesizing a Cmd+drag — a `leftMouseDown` with the
// Command flag at a far-off point that "grabs" the item, then a `leftMouseUp` at
// the destination edge of a target item. This is the ONLY way to truly hide /
// rearrange arbitrary items (vs. the spacer trick that only shoves our own
// left-neighbors off the edge).
//
// Unlike Ice we keep a simplified post/settle loop rather than the full
// event-tap continuation + 5x retry machinery. Because this rearranges the
// user's real menu bar and cannot be validated without doing so live, it is
// gated behind `PreferencesStore.config.enableExperimentalItemMovement`
// (default OFF) and never auto-invoked.

enum MenuBarItemMover {
    enum MoveError: Error {
        case notEnabled
        case missingItem
        case missingTarget
        case eventSource
        case eventCreation
        case notMovable
    }

    enum Destination {
        case leftOf(targetWindowID: CGWindowID)
        case rightOf(targetWindowID: CGWindowID)
    }

    /// Move `windowID` to the given destination. Throws `notEnabled` unless the
    /// experimental flag is on, so callers can't trigger it by accident.
    @MainActor
    static func move(windowID: CGWindowID, to destination: Destination, enabled: Bool) async throws {
        guard enabled else { throw MoveError.notEnabled }

        guard let item = MenuBarWindowInfo.read(windowID: windowID) else {
            throw MoveError.missingItem
        }
        guard !item.info.isLikelyImmovable else {
            throw MoveError.notMovable
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw MoveError.eventSource
        }

        let endPoint = try endPoint(for: destination)
        let startPoint = CGPoint(x: 20_000, y: 20_000)

        guard
            let mouseDown = CGEvent.menuBarMoveEvent(
                phase: .down, location: startPoint, windowID: windowID, pid: item.ownerPID, source: source
            ),
            let mouseUp = CGEvent.menuBarMoveEvent(
                phase: .up, location: endPoint, windowID: targetWindowID(for: destination), pid: item.ownerPID, source: source
            )
        else {
            throw MoveError.eventCreation
        }

        permitAllEvents(source: source)

        let restoreLocation = MouseCursorBridge.location
        MouseCursorBridge.hide()
        defer {
            if let restoreLocation { MouseCursorBridge.warp(to: restoreLocation) }
            MouseCursorBridge.show()
        }

        mouseDown.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        mouseUp.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(20))
    }

    // MARK: Geometry

    private static func targetWindowID(for destination: Destination) -> CGWindowID {
        switch destination {
        case .leftOf(let id), .rightOf(let id): return id
        }
    }

    private static func endPoint(for destination: Destination) throws -> CGPoint {
        let targetID = targetWindowID(for: destination)
        guard let frame = MenuBarBridging.frame(for: targetID) else {
            throw MoveError.missingTarget
        }
        switch destination {
        case .leftOf: return CGPoint(x: frame.minX, y: frame.midY)
        case .rightOf: return CGPoint(x: frame.maxX, y: frame.midY)
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

    /// Build a Cmd+drag move event for a menu bar item. Mirrors Ice's
    /// `CGEvent.menuBarItemEvent(type: .move(...))`.
    class func menuBarMoveEvent(
        phase: MovePhase,
        location: CGPoint,
        windowID: CGWindowID,
        pid: pid_t,
        source: CGEventSource
    ) -> CGEvent? {
        let mouseType: CGEventType = (phase == .down) ? .leftMouseDown : .leftMouseUp
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: mouseType,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            return nil
        }

        // The grab is what Command-flagged left-mouse-down on a status item does.
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

// MARK: - Mouse cursor helpers

enum MouseCursorBridge {
    static var location: CGPoint? {
        guard let event = CGEvent(source: nil) else { return nil }
        return event.location
    }

    static func hide() {
        CGDisplayHideCursor(CGMainDisplayID())
    }

    static func show() {
        CGDisplayShowCursor(CGMainDisplayID())
    }

    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }
}
