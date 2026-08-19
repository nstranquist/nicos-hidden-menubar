import CoreGraphics
import Foundation

/// Versioned durable identity for a menu-bar item (ITEM-001 / ADR-0003).
///
/// `legacyKey` preserves the pre-v0.2 `namespace:title` string so first-party
/// visibility lists and caches migrate without silent loss.
struct MenuBarItemIdentity: Equatable, Hashable, Sendable, Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Owning app bundle id (or owner name when unavailable).
    var namespace: String
    /// Window title when present (often empty for image-only extras).
    var title: String
    /// Control Center / specialized module id when known.
    var moduleID: String?
    /// Left-to-right ordinal among peers sharing namespace+title+module on one scan.
    var ordinal: Int
    /// Pre-v0.2 cache/policy key.
    var legacyKey: String

    /// Stable key for caches, diagnostics, and policy maps.
    var key: String {
        let module = moduleID ?? "_"
        return "v\(schemaVersion):\(namespace):\(module):\(title):\(ordinal)"
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        namespace: String,
        title: String,
        moduleID: String? = nil,
        ordinal: Int = 0,
        legacyKey: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.namespace = namespace
        self.title = title
        self.moduleID = moduleID
        self.ordinal = max(0, ordinal)
        self.legacyKey = legacyKey ?? "\(namespace):\(title)"
    }

    /// Migrates a pre-v0.2 `namespace:title` key into a versioned identity.
    static func migrateLegacyKey(_ legacy: String) -> MenuBarItemIdentity {
        let parts = legacy.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let namespace = parts.first.map(String.init) ?? "unknown"
        let title = parts.count > 1 ? String(parts[1]) : ""
        let module = ControlCenterModules.moduleID(namespace: namespace, title: title)
        return MenuBarItemIdentity(
            namespace: namespace,
            title: title,
            moduleID: module,
            ordinal: 0,
            legacyKey: legacy
        )
    }

    /// Builds identities for a left→right scan, disambiguating peer collisions.
    static func resolveScan(_ raw: [(namespace: String, title: String)]) -> [MenuBarItemIdentity] {
        var peerCounts: [String: Int] = [:]
        return raw.map { entry in
            let module = ControlCenterModules.moduleID(namespace: entry.namespace, title: entry.title)
            let peerKey = "\(entry.namespace)|\(module ?? "")|\(entry.title)"
            let ordinal = peerCounts[peerKey, default: 0]
            peerCounts[peerKey] = ordinal + 1
            return MenuBarItemIdentity(
                namespace: entry.namespace,
                title: entry.title,
                moduleID: module,
                ordinal: ordinal
            )
        }
    }
}

/// Known Control Center module specialization so image-only peers stay distinct.
enum ControlCenterModules {
    static let controlCenterNamespace = "com.apple.controlcenter"

    /// Title / owner-name fragments → stable module ids.
    static let knownModules: [(id: String, matchers: [String])] = [
        ("wifi", ["wifi", "wi-fi", "wi‑fi", "wlan"]),
        ("bluetooth", ["bluetooth", "bt"]),
        ("airdrop", ["airdrop", "air drop"]),
        ("focus", ["focus", "do not disturb", "dnd"]),
        ("display", ["display", "brightness", "true tone"]),
        ("sound", ["sound", "volume", "audio"]),
        ("battery", ["battery", "power"]),
        ("keyboard-brightness", ["keyboard brightness", "keyboard"]),
        ("now-playing", ["now playing", "music"]),
        ("stage-manager", ["stage manager"]),
        ("screen-mirroring", ["screen mirroring", "airplay"]),
        ("control-center", ["control center", "controlcentre", "control centre"]),
        ("clock", ["clock"]),
        ("user-switcher", ["user", "fast user"]),
    ]

    static func moduleID(namespace: String, title: String) -> String? {
        let ns = namespace.lowercased()
        guard ns.contains("controlcenter") || ns == controlCenterNamespace else {
            return nil
        }
        let haystack = title.lowercased()
        if haystack.isEmpty {
            // Image-only CC items still need a module slot; callers supply ordinals.
            return "module"
        }
        for entry in knownModules {
            if entry.matchers.contains(where: { haystack.contains($0) }) {
                return entry.id
            }
        }
        // Stable slug from title for unknown but titled modules.
        let slug =
            haystack
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return slug.isEmpty ? "module" : slug
    }

    /// Fixture table used by ITEM-001 automated acceptance.
    static let fixtureTitles: [(title: String, moduleID: String)] = [
        ("Wi‑Fi", "wifi"),
        ("Bluetooth", "bluetooth"),
        ("Focus", "focus"),
        ("Sound", "sound"),
        ("Battery", "battery"),
        ("Display", "display"),
        ("AirDrop", "airdrop"),
        ("Screen Mirroring", "screen-mirroring"),
    ]

    static func displayName(forModuleID moduleID: String?, title: String, ordinal: Int) -> String? {
        if !title.isEmpty, title.lowercased() != "control center" {
            return title
        }
        switch moduleID {
        case "wifi": return "Wi‑Fi"
        case "bluetooth": return "Bluetooth"
        case "airdrop": return "AirDrop"
        case "focus": return "Focus"
        case "display": return "Display"
        case "sound": return "Sound"
        case "battery": return "Battery"
        case "keyboard-brightness": return "Keyboard"
        case "now-playing": return "Now Playing"
        case "stage-manager": return "Stage Manager"
        case "screen-mirroring": return "Screen Mirroring"
        case "control-center": return "Control Center"
        case "clock": return "Clock"
        case "user-switcher": return "User"
        case "module":
            return ordinal > 0 ? "Control Center \(ordinal + 1)" : "Control Center"
        default:
            if let moduleID, !moduleID.isEmpty, moduleID != "module" {
                return
                    moduleID
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: " ")
            }
            return nil
        }
    }

    /// SF Symbol used when live capture is unavailable.
    static func symbolName(forModuleID moduleID: String?, title: String) -> String? {
        let id = moduleID ?? Self.moduleID(namespace: controlCenterNamespace, title: title)
        switch id {
        case "wifi": return "wifi"
        case "bluetooth": return "wave.3.right"
        case "airdrop": return "airplayaudio"
        case "focus": return "moon.fill"
        case "display": return "sun.max.fill"
        case "sound": return "speaker.wave.2.fill"
        case "battery": return "battery.100"
        case "keyboard-brightness": return "keyboard"
        case "now-playing": return "music.note"
        case "stage-manager": return "rectangle.3.group"
        case "screen-mirroring": return "airplayvideo"
        case "control-center": return "switch.2"
        case "clock": return "clock"
        case "user-switcher": return "person.crop.circle"
        default:
            return title.isEmpty ? "switch.2" : nil
        }
    }
}

extension MenuBarItemInfo {
    /// Versioned identity with no ordinal (single-item contexts).
    var identity: MenuBarItemIdentity {
        MenuBarItemIdentity(
            namespace: namespace,
            title: title,
            moduleID: ControlCenterModules.moduleID(namespace: namespace, title: title),
            ordinal: 0
        )
    }
}
