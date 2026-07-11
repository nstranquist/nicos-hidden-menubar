import Foundation

struct HiddenBarImporter: Sendable {
    static let domain = "com.dwarvesv.minimalbar"

    static let droppedKeys: Set<String> = [
        "openAtLogin",
        "SMLoginItemSetEnabled",
        "isAutoStart",
        "showRateWindow",
        "ratingHasShown",
        "hasShownRateWindow",
        "hasShownRatePrompt",
        "closeVersion",
        "lastOpenVersion",
        "firstLaunch",
        "firstLaunchVersion",
        "firstLaunchAt",
        "isFirstMoveToTrashEvent",
        "shouldReopenOnDismiss",
        "statusItemIconKind",
    ]

    static let live = HiddenBarImporter(
        loadDefaults: { domain in
        let raw = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        return convertFoundationDictionary(raw as NSDictionary)
        },
        loadFallback: { domain in
            readDomainViaDefaultsExport(domain: domain)
        }
    )

    let loadDefaults: @Sendable (String) -> PropertyListDictionary
    let loadFallback: @Sendable (String) -> PropertyListDictionary

    init(
        loadDefaults: @escaping @Sendable (String) -> PropertyListDictionary = { _ in [:] },
        loadFallback: @escaping @Sendable (String) -> PropertyListDictionary = { _ in [:] }
    ) {
        self.loadDefaults = loadDefaults
        self.loadFallback = loadFallback
    }

    func importIfAvailable(importedAt: Date = Date()) -> HiddenBarImportResult? {
        var values = loadDefaults(Self.domain)
        if values.isEmpty {
            values = loadFallback(Self.domain)
        }
        guard !values.isEmpty else {
            return nil
        }
        return Self.importConfig(from: values, importedAt: importedAt)
    }

    static func convertFoundationDictionary(_ raw: NSDictionary) -> PropertyListDictionary {
        var converted: PropertyListDictionary = [:]
        for case let (key as String, value) in raw {
            guard let objectValue = value as? NSObject else {
                continue
            }
            if let scalar = PropertyListValue.fromFoundation(objectValue) {
                converted[key] = scalar
            }
        }
        return converted
    }

    /// Fallback path when `UserDefaults.standard.persistentDomain(forName:)` returns empty.
    ///
    /// On macOS, Foundation's preference APIs can report an empty dictionary for another
    /// app's domain even when the plist is on disk and `/usr/bin/defaults` can read it —
    /// observed during the 2026-04-19 Hidden Bar hard cutover. Shelling out to
    /// `/usr/bin/defaults export <domain> -` produces an XML plist that
    /// `PropertyListSerialization` accepts, which lets first-launch import succeed even
    /// when the upstream app is still active or the cfprefsd cache is stale.
    static func readDomainViaDefaultsExport(domain: String) -> PropertyListDictionary {
        let process = Process()
        process.launchPath = "/usr/bin/defaults"
        process.arguments = ["export", domain, "-"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            return [:]
        }
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? NSDictionary
        else {
            return [:]
        }
        return convertFoundationDictionary(dict)
    }

    static func importConfig(from values: PropertyListDictionary, importedAt: Date = Date()) -> HiddenBarImportResult {
        var config = HiddenBarConfig.default
        var importedKeySet = Set<String>()
        var ignoredKeys: [String] = []

        if let (key, value) = firstBool(for: ["autoHideEnabled", "autoHide", "isAutoHideEnabled"], in: values) {
            config.autoCollapse.enabled = value
            importedKeySet.insert(key)
        }
        if let (key, value) = firstInt(for: ["autoHideSeconds", "autoHideTimeSeconds", "secondsBeforeCollapse"], in: values) {
            config.autoCollapse.seconds = max(1, value)
            importedKeySet.insert(key)
        }
        if let (key, value) = firstBool(for: ["isShowPreferences", "showPreferencesOnLaunch"], in: values) {
            config.showPreferencesOnLaunch = value
            importedKeySet.insert(key)
        }
        if let (key, value) = firstBool(for: ["alwaysHiddenSectionEnabled", "alwaysHiddenEnabled"], in: values) {
            config.lanes.alwaysHiddenEnabled = value
            importedKeySet.insert(key)
        }
        if let (key, value) = firstBool(for: ["useFullStatusBarOnExpandEnabled", "useFullStatusBarOnExpand"], in: values) {
            config.useRegularActivationOnExpand = value
            importedKeySet.insert(key)
        }

        let shortcutKey = firstInt(for: ["shortcutKeyCode", "globalShortcutKeyCode"], in: values)
        let shortcutFlags = firstInt(for: ["shortcutCarbonFlags", "globalShortcutCarbonFlags"], in: values)
        let shortcutDisplay = firstString(for: ["shortcutDisplay", "globalShortcutDisplay"], in: values)
        if let shortcutKey, let shortcutFlags {
            config.globalShortcut.keyCode = shortcutKey.1
            config.globalShortcut.carbonFlags = shortcutFlags.1
            importedKeySet.insert(shortcutKey.0)
            importedKeySet.insert(shortcutFlags.0)
            if let shortcutDisplay {
                config.globalShortcut.display = shortcutDisplay.1
                importedKeySet.insert(shortcutDisplay.0)
            }
        }

        for key in values.keys.sorted() where !importedKeySet.contains(key) && !Self.droppedKeys.contains(key) {
            ignoredKeys.append(key)
        }

        let note = HiddenBarImportNote(
            importedAt: hiddenBarTimestampString(importedAt),
            importedKeys: importedKeySet.sorted(),
            ignoredKeys: ignoredKeys,
            sourceDomain: Self.domain
        )

        let validatedConfig = (try? config.validated()) ?? HiddenBarConfig.default
        return HiddenBarImportResult(config: validatedConfig, note: note)
    }

    private static func firstBool(for keys: [String], in values: PropertyListDictionary) -> (String, Bool)? {
        for key in keys {
            if let value = values[key]?.boolValue {
                return (key, value)
            }
        }
        return nil
    }

    private static func firstInt(for keys: [String], in values: PropertyListDictionary) -> (String, Int)? {
        for key in keys {
            if let value = values[key]?.intValue {
                return (key, value)
            }
        }
        return nil
    }

    private static func firstString(for keys: [String], in values: PropertyListDictionary) -> (String, String)? {
        for key in keys {
            if let value = values[key]?.stringValue, !value.isEmpty {
                return (key, value)
            }
        }
        return nil
    }
}
