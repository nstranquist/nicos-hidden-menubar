import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var message: String?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        self.status = service.status
    }

    var statusDescription: String {
        if !isInstalledApplication {
            return "Available after installing the app in /Applications"
        }

        switch status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval in System Settings"
        case .notRegistered:
            return "Disabled"
        case .notFound:
            return "App registration was not found"
        @unknown default:
            return "Unknown"
        }
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func reconcile(enabled: Bool) {
        guard isInstalledApplication else {
            status = service.status
            message = nil
            return
        }

        do {
            switch (enabled, service.status) {
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                break
            }
            status = service.status
            message = nil
        } catch {
            status = service.status
            message = error.localizedDescription
            HiddenMenuBarTelemetry.appLifecycle.error(
                "Launch-at-login reconciliation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private var isInstalledApplication: Bool {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        return bundleURL.path == "/Applications/NicosHiddenMenuBar.app"
    }
}
