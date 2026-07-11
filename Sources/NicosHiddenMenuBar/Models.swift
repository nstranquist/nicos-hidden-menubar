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
    /// Show the IceBar popover of hidden items instead of inline reveal.
    var iceBarEnabled: Bool? = nil
    /// EXPERIMENTAL: allow synthesized Cmd-drag to truly move/hide arbitrary
    /// items. Off by default — manipulates the real menu bar and needs live
    /// validation. See MenuBarItemMover.
    var enableExperimentalItemMovement: Bool? = nil
    /// Reveal hidden items on hover over the toggle.
    var revealOnHover: Bool? = nil

    var isIceBarEnabled: Bool { iceBarEnabled ?? false }
    var isExperimentalItemMovementEnabled: Bool { enableExperimentalItemMovement ?? false }
    var isRevealOnHoverEnabled: Bool { revealOnHover ?? false }
    var isOnboardingCompleted: Bool { onboardingCompleted ?? false }

    static let `default` = HiddenBarConfig(
        schemaVersion: currentSchemaVersion,
        launchAtLogin: true,
        showPreferencesOnLaunch: false,
        useRegularActivationOnExpand: false,
        hideMarkersWhileExpanded: false,
        autoCollapse: AutoCollapseSettings(enabled: true, seconds: 10),
        globalShortcut: GlobalShortcutSettings(
            enabled: true,
            keyCode: 42,
            carbonFlags: 1_572_864,
            display: #"cmd+shift+\\"#
        ),
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
        normalized.firstPartyVisible.preferredVisibleTitles = FirstPartyVisibleTitles
            .sanitize(normalized.firstPartyVisible.preferredVisibleTitles)
            .filter { $0 != "HS" }

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
        return normalized
    }

    var activeProfileSettings: HiddenBarProfile {
        profiles[activeProfile] ?? profiles["default"] ?? HiddenBarProfile(autoCollapseEnabled: true, autoCollapseSeconds: 10, useRegularActivationOnExpand: false)
    }
}

struct AutoCollapseSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var seconds: Int
}

struct GlobalShortcutSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var keyCode: Int
    var carbonFlags: Int
    var display: String
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
