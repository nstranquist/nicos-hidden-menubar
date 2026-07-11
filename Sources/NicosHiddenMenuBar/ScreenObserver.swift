import AppKit
import Foundation

@MainActor
final class ScreenObserver {
    // The poll detects "user moved mouse to a different screen so its
    // menubar geometry differs" — purely a multi-monitor concern. Single
    // monitor users get zero polling; multi-monitor users get a 1s poll
    // (was 0.35s, ~3x reduction) which still feels snappy for the cursor
    // -> menubar geometry handoff.
    private static let activeScreenPollInterval: TimeInterval = 1.0

    private let onChange: () -> Void
    private var screenParametersObserver: NSObjectProtocol?
    private var pendingWorkItem: DispatchWorkItem?
    private var activeScreenPollTimer: Timer?
    private var lastScreenSignature: String?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.lastScreenSignature = Self.currentMouseScreenSignature()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Screen topology changed (display added/removed/resized);
                // re-gate the poll to match the new screen count.
                self.applyPollGate()
                self.scheduleChange()
            }
        }
        applyPollGate()
    }

    // Note: no deinit. ScreenObserver lives for the lifetime of the app
    // (the menubar process never spawns multiple instances), so the
    // NotificationCenter observer naturally tears down at process exit.
    // Adding a deinit would need @preconcurrency dance under Swift 6
    // strict concurrency without buying anything real.

    /// Start or stop the active-screen poll based on whether the user
    /// actually has multiple displays to switch between.
    private func applyPollGate() {
        let multiScreen = NSScreen.screens.count > 1
        if multiScreen && activeScreenPollTimer == nil {
            activeScreenPollTimer = Timer.scheduledTimer(withTimeInterval: Self.activeScreenPollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollActiveScreen()
                }
            }
        } else if !multiScreen, let timer = activeScreenPollTimer {
            timer.invalidate()
            activeScreenPollTimer = nil
        }
    }

    private func scheduleChange() {
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func pollActiveScreen() {
        let signature = Self.currentMouseScreenSignature()
        guard signature != lastScreenSignature else {
            return
        }
        lastScreenSignature = signature
        scheduleChange()
    }

    private static func currentMouseScreenSignature() -> String? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let screen else {
            return nil
        }
        let frame = screen.frame
        return "\(screen.localizedName)|\(frame.origin.x)|\(frame.origin.y)|\(frame.size.width)|\(frame.size.height)"
    }
}
