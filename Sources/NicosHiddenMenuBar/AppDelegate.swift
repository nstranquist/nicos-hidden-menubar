import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSWindowDelegate {
    private let preferencesStore: PreferencesStore
    private let profileStore: ProfileStore
    private let bridge: HammerspoonBridge
    private let launchAtLoginController: LaunchAtLoginController

    private var preferencesWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var profileEditorWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?

    /// First currently-open managed window — used by the headless self-test to
    /// inspect / screenshot whatever window it just opened.
    var anyManagedWindow: NSWindow? {
        preferencesWindow ?? onboardingWindow ?? profileEditorWindow ?? diagnosticsWindow
    }

    init(
        preferencesStore: PreferencesStore,
        profileStore: ProfileStore,
        bridge: HammerspoonBridge,
        launchAtLoginController: LaunchAtLoginController
    ) {
        self.preferencesStore = preferencesStore
        self.profileStore = profileStore
        self.bridge = bridge
        self.launchAtLoginController = launchAtLoginController
        super.init()
    }

    func openPreferences() {
        preferencesWindow = openWindow(
            existing: preferencesWindow,
            title: "Nicos Hidden Bar Settings",
            size: NSSize(width: 680, height: 720)
        ) {
            PreferencesView()
                .environmentObject(self.preferencesStore)
                .environmentObject(self.profileStore)
                .environmentObject(self.bridge)
                .environmentObject(self.launchAtLoginController)
        }
    }

    func openOnboarding() {
        onboardingWindow = openWindow(
            existing: onboardingWindow,
            title: "Nicos Hidden Bar Onboarding",
            size: NSSize(width: 560, height: 480)
        ) {
            OnboardingView(onComplete: { [weak self] in
                guard let self else { return }
                let didSave = self.preferencesStore.updateConfig { config in
                    config.onboardingCompleted = true
                }
                if didSave {
                    self.onboardingWindow?.close()
                }
            })
                .environmentObject(self.preferencesStore)
                .environmentObject(self.bridge)
        }
    }

    func openProfileEditor() {
        profileEditorWindow = openWindow(
            existing: profileEditorWindow,
            title: "Edit Profiles",
            size: NSSize(width: 480, height: 420)
        ) {
            ProfileEditorView()
                .environmentObject(self.preferencesStore)
                .environmentObject(self.profileStore)
        }
    }

    func openDiagnostics() {
        diagnosticsWindow = openWindow(
            existing: diagnosticsWindow,
            title: "Nicos Hidden Bar Diagnostics",
            size: NSSize(width: 540, height: 460)
        ) {
            DiagnosticsView()
                .environmentObject(self.preferencesStore)
                .environmentObject(self.profileStore)
                .environmentObject(self.bridge)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        HiddenMenuBarTelemetry.windowing.info("Window closed: \(window.title, privacy: .public)")
        if window === preferencesWindow {
            preferencesWindow = nil
        } else if window === onboardingWindow {
            onboardingWindow = nil
        } else if window === profileEditorWindow {
            profileEditorWindow = nil
        } else if window === diagnosticsWindow {
            diagnosticsWindow = nil
        }

        if preferencesWindow == nil,
           onboardingWindow == nil,
           profileEditorWindow == nil,
           diagnosticsWindow == nil
        {
            HiddenMenuBarTelemetry.windowing.debug("All auxiliary windows closed; returning to accessory activation")
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func openWindow<Content: View>(
        existing: NSWindow?,
        title: String,
        size: NSSize,
        content: () -> Content
    ) -> NSWindow {
        // Headless launch (smoke / launch-verify) stays a Dock-less accessory and
        // never steals focus; a normal launch shows the Dock icon and activates.
        HiddenBarHeadless.setRegularPolicyUnlessHeadless()
        HiddenBarHeadless.activateUnlessHeadless()

        if let existing {
            HiddenMenuBarTelemetry.windowing.info("Reusing window: \(title, privacy: .public)")
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            HiddenBarHeadless.surface(existing)
            return existing
        }

        let controller = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: controller)
        HiddenMenuBarTelemetry.windowing.info("Opening window: \(title, privacy: .public)")
        window.title = title
        window.setContentSize(size)
        window.minSize = size
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        HiddenBarHeadless.surface(window)
        return window
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferencesStore = PreferencesStore.shared
    private let profileStore = ProfileStore.shared
    private let bridge = HammerspoonBridge.shared
    private let launchAtLoginController = LaunchAtLoginController.shared

    private lazy var coordinator = AppCoordinator(
        preferencesStore: preferencesStore,
        profileStore: profileStore,
        bridge: bridge,
        launchAtLoginController: launchAtLoginController
    )

    private var statusController: StatusSectionController?
    private var hotkeyController: HotkeyController?
    private var screenObserver: ScreenObserver?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        HiddenMenuBarTelemetry.appLifecycle.info("Application launched")
        NSApplication.shared.setActivationPolicy(.accessory)
        let menuBarServices = MenuBarServices.live(preferencesStore: preferencesStore)

        // Headless launch-verify: prove the preferences window (the real
        // foregrounding path) opens without stealing focus, then exit. Skip the
        // status-bar spacer items, global hotkey, and screen observer so a verify
        // run never disturbs the user's already-running instance or menu bar.
        if HiddenBarHeadlessSelfTest.isRequested {
            HiddenBarHeadlessSelfTest.runAndExit(
                compositionReport: { menuBarServices.compositionReport() },
                openWindow: { [weak self] in self?.coordinator.openPreferences() },
                window: { [weak self] in self?.coordinator.anyManagedWindow }
            )
            return
        }

        registerURLHandler()

        bridge.refresh(using: preferencesStore.config)
        preferencesStore.recordBridgeStatus(bridge.status)

        statusController = StatusSectionController(
            preferencesStore: preferencesStore,
            profileStore: profileStore,
            services: menuBarServices,
            openSettings: { [weak self] in self?.coordinator.openPreferences() },
            openDiagnostics: { [weak self] in self?.coordinator.openDiagnostics() },
            openOnboarding: { [weak self] in self?.coordinator.openOnboarding() }
        )
        hotkeyController = HotkeyController(
            preferencesStore: preferencesStore,
            onTrigger: { [weak self] in
                self?.statusController?.toggleReveal()
            }
        )
        screenObserver = ScreenObserver { [weak self] in
            self?.statusController?.recomputeGeometry()
        }

        preferencesStore.$config
            .sink { [weak self] config in
                guard let self else { return }
                self.bridge.refresh(using: config)
                self.preferencesStore.recordBridgeStatus(self.bridge.status)
            }
            .store(in: &cancellables)

        preferencesStore.$config
            .map(\.launchAtLogin)
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.launchAtLoginController.reconcile(enabled: enabled)
            }
            .store(in: &cancellables)

        if !preferencesStore.config.isOnboardingCompleted {
            coordinator.openOnboarding()
        } else if preferencesStore.config.showPreferencesOnLaunch {
            coordinator.openPreferences()
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "nicoshiddenbar" else {
            HiddenMenuBarTelemetry.commandExecution.warning("Ignored URL with unexpected scheme")
            preferencesStore.recordIgnoredURL(url.absoluteString)
            return
        }

        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        HiddenMenuBarTelemetry.commandExecution.info("Handling URL command: \(host, privacy: .public) \(pathComponents.joined(separator: "/"), privacy: .private)")

        switch host {
        case "toggle":
            statusController?.toggleReveal()
        case "expand":
            statusController?.expand()
        case "collapse":
            _ = statusController?.collapse()
        case "icebar":
            statusController?.openIceBar()
        case "profile":
            if let profileName = pathComponents.first, profileStore.switchProfile(named: profileName) {
                HiddenMenuBarTelemetry.commandExecution.info("Profile command accepted: \(profileName, privacy: .private)")
                statusController?.recomputeGeometry()
            } else {
                HiddenMenuBarTelemetry.commandExecution.warning("Profile command rejected")
                preferencesStore.recordIgnoredURL(url.absoluteString)
            }
        case "open":
            if pathComponents.first == "settings" {
                coordinator.openPreferences()
            } else if pathComponents.first == "diagnostics" {
                coordinator.openDiagnostics()
            } else {
                HiddenMenuBarTelemetry.commandExecution.warning("Open command rejected")
                preferencesStore.recordIgnoredURL(url.absoluteString)
            }
        default:
            HiddenMenuBarTelemetry.commandExecution.warning("Unknown URL command: \(host, privacy: .public)")
            preferencesStore.recordIgnoredURL(url.absoluteString)
        }
    }

    private func registerURLHandler() {
        HiddenMenuBarTelemetry.appLifecycle.debug("Registering URL handler")
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString)
        else {
            return
        }
        handleIncomingURL(url)
    }
}
