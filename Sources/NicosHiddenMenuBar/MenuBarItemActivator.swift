import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Opens a menu-bar item by synthesizing a normal left click at its frame
/// (ACT-001). Distinct from Command-drag movement in `MenuBarItemMover`.
enum MenuBarItemActivator {
    enum ActivateError: Error, Equatable {
        case missingItem
        case missingFrame
        case eventSource
        case eventCreation
        case accessibilityRequired
        case clickDidNotStick
    }

    /// True when Accessibility is granted for synthetic event targeting.
    static func hasAccessibilityPermission() -> Bool {
        PrivacyPermissions.isAccessibilityTrusted
    }

    /// Registers this app with Accessibility TCC (so it appears in Privacy
    /// settings) and optionally prompts. Prefer
    /// `PrivacyPermissions.requestAccessibilityAccessAndShowSettings()` from UI.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        PrivacyPermissions.enrollAccessibility(prompt: true)
    }

    /// Click the status item so its menu opens without rearranging the bar.
    @MainActor
    static func openMenu(windowID: CGWindowID) async throws {
        guard let item = MenuBarWindowInfo.read(windowID: windowID) else {
            throw ActivateError.missingItem
        }
        guard item.frame.width > 0, item.frame.height > 0 else {
            throw ActivateError.missingFrame
        }

        // CGEvent posting to other processes is more reliable with Accessibility.
        guard hasAccessibilityPermission() else {
            throw ActivateError.accessibilityRequired
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActivateError.eventSource
        }

        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        guard
            let mouseDown = CGEvent.clickEvent(
                phase: .down,
                location: point,
                windowID: windowID,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUp = CGEvent.clickEvent(
                phase: .up,
                location: point,
                windowID: windowID,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw ActivateError.eventCreation
        }

        permitLocalEvents(source: source)
        let restore = MouseCursorBridge.location
        // Disconnect hardware mouse so the click doesn't leave the pointer stranded
        // on an under-camera overflow frame.
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        defer {
            MouseCursorBridge.forceRestore(to: restore)
        }
        await postMenuBarEvent(mouseDown, toOwnerPID: item.ownerPID)
        if let restore { CGWarpMouseCursorPosition(restore) }
        try? await Task.sleep(for: .milliseconds(16))
        await postMenuBarEvent(mouseUp, toOwnerPID: item.ownerPID)
        if let restore { CGWarpMouseCursorPosition(restore) }
        try? await Task.sleep(for: .milliseconds(24))
    }

    @MainActor
    private static func postMenuBarEvent(_ event: CGEvent, toOwnerPID pid: pid_t) async {
        event.post(tap: .cgSessionEventTap)
        try? await Task.sleep(for: .milliseconds(4))
        event.postToPid(pid)
    }

    private static func permitLocalEvents(source: CGEventSource) {
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

private extension CGEventField {
    static let windowIDField = CGEventField(rawValue: 0x33)!
}

private extension CGEvent {
    enum ClickPhase { case down, up }

    class func clickEvent(
        phase: ClickPhase,
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
        // No Command flag — this is a normal activation click, not a grab/drag.
        event.flags = []
        let wid = Int64(windowID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: wid)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: wid)
        event.setIntegerValueField(.windowIDField, value: wid)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }
}
