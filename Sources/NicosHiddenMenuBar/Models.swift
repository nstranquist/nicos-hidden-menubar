import Foundation

enum HiddenBarValidationError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidAutoCollapseSeconds(Int)
    case invalidProfileSeconds(name: String, seconds: Int)
    case invalidShortcutKeyCode(Int)
    case invalidShortcutCarbonFlags(Int)
    case invalidShortcutDisplay
    case missingActiveProfile(String)
    case missingRequiredProfile(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schemaVersion: \(version)"
        case .invalidAutoCollapseSeconds(let seconds):
            return "autoCollapse.seconds must be greater than zero; received \(seconds)"
        case .invalidProfileSeconds(let name, let seconds):
            return "profiles.\(name).autoCollapseSeconds must be greater than zero; received \(seconds)"
        case .invalidShortcutKeyCode(let keyCode):
            return "globalShortcut.keyCode must be non-negative; received \(keyCode)"
        case .invalidShortcutCarbonFlags(let flags):
            return "globalShortcut.carbonFlags must be non-negative; received \(flags)"
        case .invalidShortcutDisplay:
            return "globalShortcut.display must not be empty when enabled"
        case .missingActiveProfile(let name):
            return "activeProfile '\(name)' must exist in profiles"
        case .missingRequiredProfile(let name):
            return "profiles must include required profile '\(name)'"
        }
    }
}

struct HiddenBarConfig: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let requiredProfiles = ["default", "focus", "present", "recording"]

    var schemaVersion: Int
    var launchAtLogin: Bool
    var showPreferencesOnLaunch: Bool
    var useRegularActivationOnExpand: Bool
    var hideMarkersWhileExpanded: Bool
    var autoCollapse: AutoCollapseSettings
    var globalShortcut: GlobalShortcutSettings
    var lanes: LaneSettings
    var profiles: [String: HiddenBarProfile]
    var activeProfile: String
    var firstPartyVisible: FirstPartyVisibleSettings
    /// Optional for backward-compatible decoding of configs written before the
    /// standalone app introduced first-run onboarding.
    var onboardingCompleted: Bool? = nil
    // Parity additions (optional so older persisted configs still decode).
    /// Show the below-menu-bar **Reveal Panel** of hidden items instead of inline reveal.
    var revealPanelEnabled: Bool? = nil
    /// Legacy key from when the panel was misnamed after Ice's "IceBar".
    /// Decoded for migration only; prefer `revealPanelEnabled`. Cleared on save via `validated()`.
    var iceBarEnabled: Bool? = nil
    /// Preferred reveal surface. Optional so existing schema-v1 files decode;
    /// the legacy `revealPanelEnabled` / `iceBarEnabled` flags remain the migration fallback.
    var revealMode: HiddenItemRevealMode? = nil
    /// EXPERIMENTAL: allow synthesized Cmd-drag to truly move/hide arbitrary
    /// items. Off by default — manipulates the real menu bar and needs live
    /// validation. See MenuBarItemMover.
    var enableExperimentalItemMovement: Bool? = nil
    /// Reveal hidden items on hover over the toggle.
    var revealOnHover: Bool? = nil
    /// Status-item chevron color (optional for backward-compatible decode).
    var chevronColor: ChevronIconColor? = nil
    /// Detect overflowed status items (cut off by menu-bar width / camera gap)
    /// and list them under Overflow. Defaults **on** (opt-out). Config key kept
    /// as `notchSupportEnabled` for decode compatibility.
    var notchSupportEnabled: Bool? = nil
    /// Opt-in: move overflow / under-notch extras into the hidden lane.
    /// Off unless explicitly true. Separate from spacer collapse (ADR-0005).
    var rescueOverflowIntoHiddenLane: Bool? = nil
    /// Bundle IDs / namespaces always listed in the reveal panel (even when fully
    /// visible on the bar). Optional for backward-compatible decode.
    var panelAlwaysShowNamespaces: [String]? = nil

    var isRevealPanelEnabled: Bool { revealPanelEnabled ?? iceBarEnabled ?? false }
    var isExperimentalItemMovementEnabled: Bool { enableExperimentalItemMovement ?? false }
    var isRevealOnHoverEnabled: Bool { revealOnHover ?? false }
    var isOnboardingCompleted: Bool { onboardingCompleted ?? false }
    var resolvedChevronColor: ChevronIconColor { chevronColor ?? .white }
    /// Overflow detection is on unless the user explicitly disables it.
    var isNotchSupportEnabled: Bool { notchSupportEnabled ?? true }
    /// Rescue is off unless the user explicitly opts in.
    var isRescueOverflowIntoHiddenLaneEnabled: Bool { rescueOverflowIntoHiddenLane ?? false }
    var resolvedPanelAlwaysShowNamespaces: [String] {
        panelAlwaysShowNamespaces ?? []
    }

    var configuredRevealMode: HiddenItemRevealMode {
        if let revealMode {
            return revealMode
        }
        if let revealPanelEnabled {
            return revealPanelEnabled ? .belowMenuBar : .inline
        }
        if let iceBarEnabled {
            return iceBarEnabled ? .belowMenuBar : .inline
        }
        return .automatic
    }

    func resolvedRevealMode(hasNotch: Bool) -> HiddenItemRevealMode {
        switch configuredRevealMode {
        case .automatic:
            return hasNotch ? .belowMenuBar : .inline
        case .inline, .belowMenuBar:
            return configuredRevealMode
        }
    }

    static let `default` = HiddenBarConfig(
        schemaVersion: currentSchemaVersion,
        launchAtLogin: true,
        showPreferencesOnLaunch: false,
        useRegularActivationOnExpand: false,
        hideMarkersWhileExpanded: false,
        autoCollapse: AutoCollapseSettings(enabled: true, seconds: 10),
        globalShortcut: .deliberate(enabled: false),
        lanes: LaneSettings(
            alwaysHiddenEnabled: false,
            primarySeparatorVisibleWhenExpanded: true,
            secondarySeparatorVisibleWhenExpanded: true
        ),
        profiles: [
            "default": HiddenBarProfile(autoCollapseEnabled: true, autoCollapseSeconds: 10, useRegularActivationOnExpand: false),
            "focus": HiddenBarProfile(autoCollapseEnabled: true, autoCollapseSeconds: 4, useRegularActivationOnExpand: false),
            "present": HiddenBarProfile(autoCollapseEnabled: false, autoCollapseSeconds: 10, useRegularActivationOnExpand: true),
            "recording": HiddenBarProfile(autoCollapseEnabled: false, autoCollapseSeconds: 10, useRegularActivationOnExpand: false),
        ],
        activeProfile: "default",
        firstPartyVisible: FirstPartyVisibleSettings(
            enabled: true,
            guidanceMode: .advisory,
            preferredVisibleTitles: [],
            preferredVisibleSources: []
        )
    )

    func validated() throws -> HiddenBarConfig {
        var normalized = self
        // Migrate legacy IceBar branding key → Reveal Panel.
        if normalized.revealPanelEnabled == nil, let legacy = normalized.iceBarEnabled {
            normalized.revealPanelEnabled = legacy
        }
        normalized.iceBarEnabled = nil
        if normalized.panelAlwaysShowNamespaces == nil {
            normalized.panelAlwaysShowNamespaces = []
        } else {
            // Deduplicate while preserving order.
            var seen = Set<String>()
            normalized.panelAlwaysShowNamespaces = normalized.panelAlwaysShowNamespaces?.filter {
                let key = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, seen.insert(key).inserted else { return false }
                return true
            }
        }
        normalized.firstPartyVisible.preferredVisibleTitles = FirstPartyVisibleTitles
            .migratePolicyKeys(normalized.firstPartyVisible.preferredVisibleTitles)
            .filter { $0 != "HS" }
        // Earlier builds persisted Cocoa modifier masks while registering them
        // through Carbon. The two flag domains are incompatible, so fail closed
        // and replace any high-bit legacy mask with the deliberate preset.
        if normalized.globalShortcut.carbonFlags > GlobalShortcutSettings.maximumCarbonFlags {
            normalized.globalShortcut = .deliberate(enabled: false)
        }

        guard normalized.schemaVersion == Self.currentSchemaVersion else {
            throw HiddenBarValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard normalized.autoCollapse.seconds > 0 else {
            throw HiddenBarValidationError.invalidAutoCollapseSeconds(normalized.autoCollapse.seconds)
        }
        guard !normalized.globalShortcut.enabled || !normalized.globalShortcut.display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HiddenBarValidationError.invalidShortcutDisplay
        }
        guard normalized.globalShortcut.keyCode >= 0 else {
            throw HiddenBarValidationError.invalidShortcutKeyCode(normalized.globalShortcut.keyCode)
        }
        guard normalized.globalShortcut.carbonFlags >= 0 else {
            throw HiddenBarValidationError.invalidShortcutCarbonFlags(normalized.globalShortcut.carbonFlags)
        }
        for requiredProfile in Self.requiredProfiles where normalized.profiles[requiredProfile] == nil {
            throw HiddenBarValidationError.missingRequiredProfile(requiredProfile)
        }
        guard normalized.profiles[normalized.activeProfile] != nil else {
            throw HiddenBarValidationError.missingActiveProfile(normalized.activeProfile)
        }
        for (name, profile) in normalized.profiles where profile.autoCollapseSeconds <= 0 {
            throw HiddenBarValidationError.invalidProfileSeconds(name: name, seconds: profile.autoCollapseSeconds)
        }
        // Clamp unknown chevron strings (manual JSON edits) to a known case.
        if let raw = normalized.chevronColor {
            normalized.chevronColor = ChevronIconColor.normalized(raw.rawValue)
        }
        // Materialize default so saves write the explicit on/off choice.
        if normalized.notchSupportEnabled == nil {
            normalized.notchSupportEnabled = true
        }
        return normalized
    }

    var activeProfileSettings: HiddenBarProfile {
        profiles[activeProfile] ?? profiles["default"] ?? HiddenBarProfile(autoCollapseEnabled: true, autoCollapseSeconds: 10, useRegularActivationOnExpand: false)
    }
}

enum HiddenItemRevealMode: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case inline
    case belowMenuBar

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .inline: return "In the menu bar"
        case .belowMenuBar: return "Below the menu bar"
        }
    }
}

/// Status-item chevron color (user preference). AX-untrusted can still use a
/// temporary warning tint without erasing this choice.
enum ChevronIconColor: String, Codable, CaseIterable, Equatable, Sendable {
    case white
    case blue
    case yellow
    case orange
    case system

    var displayName: String {
        switch self {
        case .white: return "White"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .system: return "System"
        }
    }

    /// Normalize unknown/legacy strings to a safe default.
    static func normalized(_ raw: String?) -> ChevronIconColor {
        guard let raw, let value = ChevronIconColor(rawValue: raw) else {
            return .white
        }
        return value
    }
}

struct AutoCollapseSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var seconds: Int
}

struct GlobalShortcutSettings: Codable, Equatable, Sendable {
    /// Carbon modifier masks occupy the low 16 bits. Cocoa NSEvent flags use
    /// high bits and must never be passed to RegisterEventHotKey.
    static let maximumCarbonFlags = 0xFFFF
    static let deliberateKeyCode = 46  // kVK_ANSI_M
    static let deliberateCarbonFlags = 6_400  // controlKey | optionKey | cmdKey
    static let deliberateDisplay = "ctrl+opt+cmd+m"

    var enabled: Bool
    var keyCode: Int
    var carbonFlags: Int
    var display: String

    static func deliberate(enabled: Bool) -> GlobalShortcutSettings {
        GlobalShortcutSettings(
            enabled: enabled,
            keyCode: deliberateKeyCode,
            carbonFlags: deliberateCarbonFlags,
            display: deliberateDisplay
        )
    }
}

struct LaneSettings: Codable, Equatable, Sendable {
    var alwaysHiddenEnabled: Bool
    var primarySeparatorVisibleWhenExpanded: Bool
    var secondarySeparatorVisibleWhenExpanded: Bool
}

struct HiddenBarProfile: Codable, Equatable, Sendable {
    var autoCollapseEnabled: Bool
    var autoCollapseSeconds: Int
    var useRegularActivationOnExpand: Bool
}

struct FirstPartyVisibleSettings: Codable, Equatable, Sendable {
    enum GuidanceMode: String, Codable, Equatable, Sendable {
        case advisory
    }

    var enabled: Bool
    var guidanceMode: GuidanceMode
    var preferredVisibleTitles: [String]
    var preferredVisibleSources: [String]
}

enum MarkerOrderStatus: String, Codable, Equatable, Sendable {
    case unknown
    case valid
    case invalid
}

enum BridgeHealth: String, Codable, Equatable, Sendable {
    case unknown
    case missing
    case valid
    case invalid
    case stale
}

enum ShortcutHealth: String, Codable, Equatable, Sendable {
    case unknown
    case valid
    case invalid
}

struct HiddenBarImportNote: Codable, Equatable, Sendable {
    var importedAt: String
    var importedKeys: [String]
    var ignoredKeys: [String]
    var sourceDomain: String
}

struct HiddenBarGeometrySnapshot: Codable, Equatable, Sendable {
    var toggleMinX: Double?
    var primaryMinX: Double?
    var secondaryMinX: Double?
    var toggleScreenName: String?
    var primaryScreenName: String?
    var mouseScreenName: String?
    var toggleScreenVisibleWidth: Double?
    var primaryScreenVisibleWidth: Double?
    var mouseScreenVisibleWidth: Double?
    var toggleScreenVisibleMaxX: Double?
    var primaryScreenVisibleMaxX: Double?
    var mouseScreenVisibleMaxX: Double?
    var allScreenVisibleWidths: [Double]
    var allScreenVisibleMaxX: [Double]
    var rawWidthFromToggleScreen: Double?
    var rawWidthFromPrimaryScreen: Double?
    var rawWidthFromMouseScreen: Double?
    // Ground-truth menu bar facts read from the window server (CGS), independent
    // of our own NSStatusItem frames. Optional so older snapshots decode cleanly.
    var realItemCount: Int?
    var realHideableItemCount: Int?
    var realLeftmostMinX: Double?
    var notchDetected: Bool?
}

/// Sparse dogfood counters — durable across launches for local hillclimb.
struct HiddenBarDogfoodStats: Codable, Equatable, Sendable {
    var revealPanelOpens: Int = 0
    var revealPanelDismisses: Int = 0
    var placementHideStarts: Int = 0
    var placementHideSuccesses: Int = 0
    var placementHideFailures: Int = 0
    var lastPlacementHideReason: String?
    var lastRevealAt: String?
    var lastHideAt: String?
    var accessibilityTrustedSamples: Int = 0
    var accessibilityUntrustedSamples: Int = 0

    static let `default` = HiddenBarDogfoodStats()
}

struct RevealPerformanceSample: Codable, Equatable, Sendable {
    var shellMilliseconds: Double
    var contentMilliseconds: Double
    /// Items already available when the shell becomes visible. Optional so
    /// observations written before the warm-cache metric remain readable.
    var shellItemCount: Int?
    var itemCount: Int
    var imageCount: Int
    /// Permission context at observation time. Optional so older samples
    /// remain decode-compatible.
    var accessibilityTrusted: Bool?
    var screenRecordingGranted: Bool?
    var warm: Bool
    var observedAt: String
}

struct HiddenBarPerformanceStats: Codable, Equatable, Sendable {
    var revealSamples: [RevealPerformanceSample]

    static let maxRevealSamples = 50
    static let `default` = HiddenBarPerformanceStats(revealSamples: [])

    mutating func append(_ sample: RevealPerformanceSample) {
        revealSamples.append(sample)
        if revealSamples.count > Self.maxRevealSamples {
            revealSamples.removeFirst(revealSamples.count - Self.maxRevealSamples)
        }
    }

    static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(1, max(0, percentile))
        let index = Int(ceil(clamped * Double(sorted.count)) - 1)
        return sorted[max(0, min(sorted.count - 1, index))]
    }
}

struct HiddenBarDiagnostics: Codable, Equatable, Sendable {
    var markerOrderStatus: MarkerOrderStatus
    var geometryReadable: Bool
    var geometryReason: String?
    var geometrySnapshot: HiddenBarGeometrySnapshot?
    var bridgeStatus: BridgeHealth
    var bridgeMessage: String?
    var importNote: HiddenBarImportNote?
    var hotkeyStatus: ShortcutHealth
    var hotkeyMessage: String?
    var lastIgnoredURL: String?
    /// Outcome of the last collapse, verified against real item frames.
    /// nil = not yet verified, true = items confirmed hidden past the edge,
    /// false = collapse ran but no item moved off-screen (notch swallow risk).
    var lastCollapseHidItems: Bool?
    /// Optional dogfood counters (decode-tolerant for older diagnostics.json).
    var dogfood: HiddenBarDogfoodStats? = nil
    /// Bounded local-only performance observations. Optional for backward
    /// compatibility with diagnostics written before PERF-001 instrumentation.
    var performance: HiddenBarPerformanceStats? = nil
    var updatedAt: String

    static let `default` = HiddenBarDiagnostics(
        markerOrderStatus: .unknown,
        geometryReadable: true,
        geometryReason: nil,
        geometrySnapshot: nil,
        bridgeStatus: .unknown,
        bridgeMessage: nil,
        importNote: nil,
        hotkeyStatus: .unknown,
        hotkeyMessage: nil,
        lastIgnoredURL: nil,
        lastCollapseHidItems: nil,
        dogfood: .default,
        performance: .default,
        updatedAt: hiddenBarTimestampString(Date())
    )
}

struct HammerspoonBridgeFile: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var generatedAt: String
    var source: String
    var items: [HammerspoonBridgeItem]
}

struct HammerspoonBridgeItem: Codable, Equatable, Identifiable, Sendable {
    enum ItemKind: String, Codable, Equatable, Sendable {
        case menu
    }

    enum PreferredLane: String, Codable, Equatable, Sendable {
        case visible
    }

    var title: String
    var kind: ItemKind
    var module: String
    var preferredLane: PreferredLane

    var id: String {
        "\(module):\(title)"
    }
}

struct BridgeSuggestion: Equatable, Sendable {
    var preferredVisibleTitles: [String]
    var preferredVisibleSources: [String]
}

enum HammerspoonBridgeLoadStatus: Equatable, Sendable {
    case missing(path: URL)
    case invalid(path: URL, message: String)
    case stale(path: URL, message: String)
    case valid(path: URL, payload: HammerspoonBridgeFile, suggestion: BridgeSuggestion, disagreesWithConfig: Bool)

    var code: BridgeHealth {
        switch self {
        case .missing:
            return .missing
        case .invalid:
            return .invalid
        case .stale:
            return .stale
        case .valid:
            return .valid
        }
    }

    var message: String? {
        switch self {
        case .missing:
            return "Bridge file not found."
        case .invalid(_, let message), .stale(_, let message):
            return message
        case .valid:
            return nil
        }
    }

    var preferredVisibleTitles: [String] {
        switch self {
        case .valid(_, _, let suggestion, _):
            return suggestion.preferredVisibleTitles
        case .missing, .invalid, .stale:
            return []
        }
    }

    var preferredVisibleSources: [String] {
        switch self {
        case .valid(_, _, let suggestion, _):
            return suggestion.preferredVisibleSources
        case .missing, .invalid, .stale:
            return []
        }
    }
}

enum PropertyListValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)

    static func fromFoundation(_ value: NSObject) -> PropertyListValue? {
        switch value {
        case let number as NSNumber:
            let type = String(cString: number.objCType)
            if type == "c" {
                return .bool(number.boolValue)
            }
            if CFNumberIsFloatType(number) {
                return .double(number.doubleValue)
            }
            return .int(number.intValue)
        case let string as String:
            return .string(string)
        case let data as Data:
            return .data(data)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

typealias PropertyListDictionary = [String: PropertyListValue]

struct HiddenBarImportResult: Equatable, Sendable {
    var config: HiddenBarConfig
    var note: HiddenBarImportNote
}

enum MenubarSectionsExit: Int, Sendable {
    case success = 0
    case genericFailure = 1
    case appNotInstalled = 2
    case appNotRunning = 3
    case markerOrderInvalid = 4
    case bridgeInvalid = 5
    case configInvalid = 6
    case profileNotFound = 7
}

struct CLIErrorEnvelope: Codable, Equatable, Sendable {
    var ok: Bool
    var error: String
    var message: String
    var recommendedAction: String

    static func markerOrderInvalid() -> CLIErrorEnvelope {
        CLIErrorEnvelope(
            ok: false,
            error: "marker_order_invalid",
            message: "The separator markers are not in a valid order for collapse.",
            recommendedAction: "Open diagnostics and cmd-drag the markers back into the expected order."
        )
    }
}

func hiddenBarTimestampString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func hiddenBarParseDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
