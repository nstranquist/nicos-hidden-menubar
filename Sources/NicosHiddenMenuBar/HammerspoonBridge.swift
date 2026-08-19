import Foundation

@MainActor
final class HammerspoonBridge: ObservableObject {
    static let staleInterval: TimeInterval = 24 * 60 * 60
    static let shared = HammerspoonBridge()

    @Published private(set) var status: HammerspoonBridgeLoadStatus
    @Published private(set) var resolvedVisibleTitles: [String]
    @Published private(set) var resolvedVisibleSources: [String]

    private let bridgeURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        bridgeURL: URL = PreferencesStore.Paths.resolve().bridgeURL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.bridgeURL = bridgeURL
        self.fileManager = fileManager
        self.now = now
        self.status = .missing(path: bridgeURL)
        self.resolvedVisibleTitles = HiddenBarConfig.default.firstPartyVisible.preferredVisibleTitles
        self.resolvedVisibleSources = HiddenBarConfig.default.firstPartyVisible.preferredVisibleSources
    }

    func refresh(using config: HiddenBarConfig) {
        status = Self.loadStatus(
            from: bridgeURL,
            fileManager: fileManager,
            now: now(),
            config: config
        )
        resolvedVisibleTitles = config.firstPartyVisible.preferredVisibleTitles
        resolvedVisibleSources = config.firstPartyVisible.preferredVisibleSources
    }

    static func loadStatus(
        from bridgeURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date(),
        config: HiddenBarConfig
    ) -> HammerspoonBridgeLoadStatus {
        guard fileManager.fileExists(atPath: bridgeURL.path) else {
            return .missing(path: bridgeURL)
        }

        do {
            let data = try Data(contentsOf: bridgeURL)
            let bridgeFile = try JSONDecoder().decode(HammerspoonBridgeFile.self, from: data)
            guard bridgeFile.schemaVersion == HiddenBarConfig.currentSchemaVersion else {
                return .invalid(path: bridgeURL, message: "Bridge schemaVersion is unsupported.")
            }
            guard let generatedAt = hiddenBarParseDate(bridgeFile.generatedAt) else {
                return .invalid(path: bridgeURL, message: "Bridge generatedAt is not valid ISO-8601.")
            }
            guard now.timeIntervalSince(generatedAt) <= staleInterval else {
                return .stale(path: bridgeURL, message: "Bridge file is stale and was ignored.")
            }

            let visibleItems = bridgeFile.items.filter { $0.preferredLane == .visible }
            let suggestion = BridgeSuggestion(
                preferredVisibleTitles: visibleItems.map(\.title),
                preferredVisibleSources: visibleItems.isEmpty ? [] : ["hammerspoon"]
            )
            let disagrees =
                suggestion.preferredVisibleTitles != config.firstPartyVisible.preferredVisibleTitles
                || suggestion.preferredVisibleSources != config.firstPartyVisible.preferredVisibleSources
            return .valid(
                path: bridgeURL,
                payload: bridgeFile,
                suggestion: suggestion,
                disagreesWithConfig: disagrees
            )
        } catch {
            return .invalid(path: bridgeURL, message: "Bridge file is not valid JSON.")
        }
    }
}
