import AppKit
import Foundation

/// The three menu bar sections, mirroring Ice's control-item model.
///
/// - `visible`: items always shown (right of the primary divider).
/// - `hidden`: items revealed only on expand (between primary and toggle).
/// - `alwaysHidden`: items revealed only via explicit reveal (left of secondary).
enum ControlSection: String, CaseIterable, Sendable {
    case visible = "NicosHB-Visible"
    case hidden = "NicosHB-Hidden"
    case alwaysHidden = "NicosHB-AlwaysHidden"

    /// autosaveName for the section's status item, so macOS persists its dragged
    /// position across launches.
    var autosaveName: String { rawValue }

    /// Seed position (lower = further right, toward the clock) used the first
    /// time the item appears, before the user drags it.
    var seedPreferredPosition: Double {
        switch self {
        case .visible: return 0
        case .hidden: return 1
        case .alwaysHidden: return 2
        }
    }
}

/// Read/write the private `NSStatusItem Preferred Position <autosave>` defaults
/// macOS uses to remember status-item positions. Same mechanism Ice seeds.
enum StatusItemDefaults {
    private static func key(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    static func preferredPosition(for autosaveName: String) -> Double? {
        let key = key(for: autosaveName)
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return nil
        }
        return UserDefaults.standard.double(forKey: key)
    }

    static func setPreferredPosition(_ value: Double, for autosaveName: String) {
        UserDefaults.standard.set(value, forKey: key(for: autosaveName))
    }

    /// Seed a section's position only if macOS hasn't already remembered one.
    static func seedIfNeeded(_ section: ControlSection) {
        guard preferredPosition(for: section.autosaveName) == nil else {
            return
        }
        setPreferredPosition(section.seedPreferredPosition, for: section.autosaveName)
    }

    /// Force-seed every control section. Used when live geometry proves markers
    /// drifted off-screen; macOS re-reads preferred positions on next item birth.
    static func resetAllToSeed() {
        for section in ControlSection.allCases {
            setPreferredPosition(section.seedPreferredPosition, for: section.autosaveName)
        }
    }

    static func clearPreferredPosition(for autosaveName: String) {
        UserDefaults.standard.removeObject(forKey: key(for: autosaveName))
    }
}
