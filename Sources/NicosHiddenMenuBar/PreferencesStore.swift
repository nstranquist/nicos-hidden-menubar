import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    struct Paths: Equatable {
        var configURL: URL
        var diagnosticsURL: URL
        var bridgeURL: URL

        static func resolve(
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Paths {
            let configBaseURL: URL
            if let xdgConfigHome = environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
                configBaseURL = URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
            } else {
                configBaseURL = homeDirectory.appendingPathComponent(".config", isDirectory: true)
            }
            let appDirectory = configBaseURL.appendingPathComponent("nicos-hidden-menubar", isDirectory: true)
            return Paths(
                configURL: appDirectory.appendingPathComponent("config.json"),
                diagnosticsURL: appDirectory.appendingPathComponent("diagnostics.json"),
                bridgeURL: appDirectory.appendingPathComponent("hammerspoon-bridge.json")
            )
        }
    }

    static let shared = PreferencesStore()

    @Published private(set) var config: HiddenBarConfig
    @Published private(set) var diagnostics: HiddenBarDiagnostics

    let paths: Paths

    private let fileManager: FileManager
    private let importer: HiddenBarImporter
    private var lastGoodConfig: HiddenBarConfig

    init(
        paths: Paths = .resolve(),
        fileManager: FileManager = .default,
        importer: HiddenBarImporter = .live
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.importer = importer
        self.config = HiddenBarConfig.default
        self.diagnostics = HiddenBarDiagnostics.default
        self.lastGoodConfig = HiddenBarConfig.default

        bootstrap()
    }

    func reloadFromDisk() {
        do {
            if let loaded = try loadConfigFromDisk() {
                config = loaded
                lastGoodConfig = loaded
            }
        } catch {
            config = lastGoodConfig
            updateDiagnostics { current in
                current.bridgeMessage = current.bridgeMessage
                current.hotkeyMessage = error.localizedDescription
            }
        }
        diagnostics = loadDiagnosticsFromDisk()
    }

    @discardableResult
    func updateConfig(_ transform: (inout HiddenBarConfig) -> Void) -> Bool {
        var candidate = config
        transform(&candidate)
        do {
            let validated = try candidate.validated()
            try persistConfig(validated)
            config = validated
            lastGoodConfig = validated
            return true
        } catch {
            config = lastGoodConfig
            return false
        }
    }

    @discardableResult
    func setActiveProfile(_ name: String) -> Bool {
        updateConfig { current in
            current.activeProfile = name
        }
    }

    func updateDiagnostics(_ transform: (inout HiddenBarDiagnostics) -> Void) {
        var next = diagnostics
        transform(&next)
        next.updatedAt = hiddenBarTimestampString(Date())
        diagnostics = next
        try? persistDiagnostics(next)
    }

    func recordBridgeStatus(_ status: HammerspoonBridgeLoadStatus) {
        updateDiagnostics { current in
            current.bridgeStatus = status.code
            current.bridgeMessage = status.message
        }
    }

    func recordMarkerOrder(valid: Bool) {
        updateDiagnostics { current in
            current.markerOrderStatus = valid ? .valid : .invalid
        }
    }

    func recordGeometryReadable(_ readable: Bool, reason: String? = nil) {
        updateDiagnostics { current in
            current.geometryReadable = readable
            current.geometryReason = readable ? nil : reason
        }
    }

    func recordGeometrySnapshot(_ snapshot: HiddenBarGeometrySnapshot) {
        updateDiagnostics { current in
            current.geometrySnapshot = snapshot
        }
    }

    func recordCollapseHidItems(_ hidItems: Bool?) {
        updateDiagnostics { current in
            current.lastCollapseHidItems = hidItems
        }
    }

    func recordHotkey(status: ShortcutHealth, message: String?) {
        updateDiagnostics { current in
            current.hotkeyStatus = status
            current.hotkeyMessage = message
        }
    }

    func recordIgnoredURL(_ url: String) {
        updateDiagnostics { current in
            current.lastIgnoredURL = url
        }
    }

    func recordDogfoodRevealOpen() {
        updateDiagnostics { current in
            var d = current.dogfood ?? .default
            d.revealPanelOpens += 1
            d.lastRevealAt = hiddenBarTimestampString(Date())
            current.dogfood = d
        }
    }

    func recordDogfoodRevealDismiss() {
        updateDiagnostics { current in
            var d = current.dogfood ?? .default
            d.revealPanelDismisses += 1
            current.dogfood = d
        }
    }

    func recordDogfoodHideStart() {
        updateDiagnostics { current in
            var d = current.dogfood ?? .default
            d.placementHideStarts += 1
            current.dogfood = d
        }
    }

    func recordDogfoodHideOutcome(succeeded: Bool, reason: String) {
        updateDiagnostics { current in
            var d = current.dogfood ?? .default
            if succeeded {
                d.placementHideSuccesses += 1
            } else {
                d.placementHideFailures += 1
            }
            d.lastPlacementHideReason = reason
            d.lastHideAt = hiddenBarTimestampString(Date())
            current.dogfood = d
        }
    }

    func recordDogfoodAccessibilitySample(trusted: Bool) {
        updateDiagnostics { current in
            var d = current.dogfood ?? .default
            if trusted {
                d.accessibilityTrustedSamples += 1
            } else {
                d.accessibilityUntrustedSamples += 1
            }
            current.dogfood = d
        }
    }

    func recordRevealPerformance(_ sample: RevealPerformanceSample) {
        updateDiagnostics { current in
            var performance = current.performance ?? .default
            performance.append(sample)
            current.performance = performance
        }
    }

    @discardableResult
    func replaceFirstPartyVisibleTitles(_ titles: [String]) -> Bool {
        updateConfig { current in
            current.firstPartyVisible.preferredVisibleTitles = FirstPartyVisibleTitles.sanitize(titles)
        }
    }

    @discardableResult
    func setFirstPartyVisibleTitle(_ title: String, enabled: Bool) -> Bool {
        updateConfig { current in
            current.firstPartyVisible.preferredVisibleTitles = FirstPartyVisibleTitles.toggled(
                current.firstPartyVisible.preferredVisibleTitles,
                title: title,
                enabled: enabled
            )
        }
    }

    private func bootstrap() {
        diagnostics = loadDiagnosticsFromDisk()

        do {
            if let loaded = try loadConfigFromDisk() {
                config = loaded
                lastGoodConfig = loaded
                return
            }
        } catch {
            config = HiddenBarConfig.default
            lastGoodConfig = HiddenBarConfig.default
        }

        if let imported = importer.importIfAvailable() {
            config = imported.config
            lastGoodConfig = imported.config
            diagnostics.importNote = imported.note
        } else {
            config = HiddenBarConfig.default
            lastGoodConfig = HiddenBarConfig.default
        }

        try? persistConfig(config)
        try? persistDiagnostics(diagnostics)
    }

    private func loadConfigFromDisk() throws -> HiddenBarConfig? {
        guard fileManager.fileExists(atPath: paths.configURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: paths.configURL)
        let decoder = JSONDecoder()
        let loaded = try decoder.decode(HiddenBarConfig.self, from: data)
        let validated = try loaded.validated()
        if validated != loaded {
            try persistConfig(validated)
        }
        return validated
    }

    private func loadDiagnosticsFromDisk() -> HiddenBarDiagnostics {
        guard fileManager.fileExists(atPath: paths.diagnosticsURL.path),
            let data = try? Data(contentsOf: paths.diagnosticsURL),
            let loaded = try? JSONDecoder().decode(HiddenBarDiagnostics.self, from: data)
        else {
            return HiddenBarDiagnostics.default
        }
        return loaded
    }

    private func persistConfig(_ config: HiddenBarConfig) throws {
        try ensureParentDirectory(for: paths.configURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: paths.configURL, options: .atomic)
    }

    private func persistDiagnostics(_ diagnostics: HiddenBarDiagnostics) throws {
        try ensureParentDirectory(for: paths.diagnosticsURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(diagnostics)
        try data.write(to: paths.diagnosticsURL, options: .atomic)
    }

    private func ensureParentDirectory(for fileURL: URL) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
