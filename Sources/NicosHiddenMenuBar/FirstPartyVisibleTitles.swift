import Foundation

enum FirstPartyVisibleTitles {
    static func sanitize(_ titles: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for rawTitle in titles {
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !seen.contains(title) else {
                continue
            }
            seen.insert(title)
            result.append(title)
        }

        return result
    }

    /// Migrates legacy title/legacy-key entries into versioned identity keys
    /// without dropping recognisable values (ITEM-001-B).
    static func migratePolicyKeys(_ keys: [String]) -> [String] {
        sanitize(keys).map { key in
            if key.hasPrefix("v1:") {
                return key
            }
            if key.contains(":") {
                return MenuBarItemIdentity.migrateLegacyKey(key).key
            }
            // Bare display titles stay as-is for advisory matching.
            return key
        }
    }

    static func candidateTitles(configTitles: [String], bridgeTitles: [String]) -> [String] {
        sanitize(bridgeTitles + configTitles + HiddenBarConfig.default.firstPartyVisible.preferredVisibleTitles)
    }

    static func toggled(_ titles: [String], title: String, enabled: Bool) -> [String] {
        let sanitizedTitle = sanitize([title]).first ?? ""
        guard !sanitizedTitle.isEmpty else {
            return sanitize(titles)
        }

        let current = sanitize(titles)
        if enabled {
            return sanitize(current + [sanitizedTitle])
        }

        return current.filter { $0 != sanitizedTitle }
    }
}
