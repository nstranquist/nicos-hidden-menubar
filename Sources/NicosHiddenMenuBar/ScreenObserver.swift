import AppKit
import Foundation

@MainActor
final class ScreenObserver {
    private let onChange: () -> Void
    private var screenParametersObserver: NSObjectProtocol?
    private var pendingWorkItem: DispatchWorkItem?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduleChange()
            }
        }
    }

    // Note: no deinit. ScreenObserver lives for the lifetime of the app
    // (the menubar process never spawns multiple instances), so the
    // NotificationCenter observer naturally tears down at process exit.
    // Adding a deinit would need @preconcurrency dance under Swift 6
    // strict concurrency without buying anything real.

    private func scheduleChange() {
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

}
