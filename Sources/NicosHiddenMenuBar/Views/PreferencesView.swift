import AppKit
import SwiftUI

/// Reimagined Settings surface: Layout · Behavior · Permissions · Advanced.
/// Uses Form sections (not GroupBox) so labels stay legible in dark/light and
/// headless capture; essential actions stay reachable at normal macOS scaling.
struct PreferencesView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var bridge: HammerspoonBridge
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    @State private var selectedTab: SettingsTab = .layout
    @State private var repairNote: String?
    /// Live AX / Screen Recording trust — refreshed on appear and app activate
    /// so a re-grant after Settings is reflected without reopening the window.
    @State private var accessibilityTrusted = PrivacyPermissions.isAccessibilityTrusted
    @State private var screenRecordingGranted = PrivacyPermissions.hasScreenRecording
    @State private var accessibilityFixNote: String?

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case layout = "Layout"
        case panel = "Panel"
        case behavior = "Behavior"
        case permissions = "Permissions"
        case advanced = "Advanced"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .layout: return "rectangle.split.3x1"
            case .panel: return "menubar.arrow.down.rectangle"
            case .behavior: return "slider.horizontal.3"
            case .permissions: return "hand.raised.fill"
            case .advanced: return "gearshape.2"
            }
        }
    }

    @State private var menuBarAppRows: [(namespace: String, name: String)] = []
    @State private var panelNamespaceDraft = ""

    private var configuredTitles: [String] {
        preferencesStore.config.firstPartyVisible.preferredVisibleTitles
    }

    private var bridgeSuggestedTitles: [String] {
        bridge.status.preferredVisibleTitles
    }

    private var candidateTitles: [String] {
        FirstPartyVisibleTitles.candidateTitles(
            configTitles: configuredTitles,
            bridgeTitles: bridgeSuggestedTitles
        )
    }

    private var geometryNeedsRepair: Bool {
        // Notch compact path often has lastCollapseHidItems == false; that is
        // expected and not a repair condition. Flag only unreadable / invalid geometry.
        !preferencesStore.diagnostics.geometryReadable
            || preferencesStore.diagnostics.markerOrderStatus == .invalid
            || preferencesStore.diagnostics.geometryReason == MenuBarCollapseFailure.markersOffScreen.rawValue
            || preferencesStore.diagnostics.geometryReason == MenuBarCollapseFailure.nothingToHide.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                sidebar
                    .frame(width: 168)
                Divider()
                Form {
                    tabContent
                }
                .formStyle(.grouped)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 760, minHeight: 640)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("Nicos Hidden Bar", systemImage: "menubar.rectangle")
                .font(.title2.weight(.semibold))
            Spacer()
            if geometryNeedsRepair {
                Label("Needs repair", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .help(preferencesStore.diagnostics.geometryReason ?? "Marker geometry or last collapse needs attention")
            } else {
                Label("Healthy", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.systemImage)
                            .frame(width: 16)
                        Text(tab.rawValue)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.rawValue))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
            Text("Config: ~/.config/nicos-hidden-menubar/")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(12)
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .layout:
            layoutTab
        case .panel:
            panelTab
        case .behavior:
            behaviorTab
        case .permissions:
            permissionsTab
        case .advanced:
            advancedTab
        }
    }

    // MARK: - Panel (reveal panel contents)

    @ViewBuilder
    private var panelTab: some View {
        Section {
            Toggle("Overflow detection", isOn: Binding(
                get: { preferencesStore.config.isNotchSupportEnabled },
                set: { newValue in
                    _ = preferencesStore.updateConfig { current in
                        current.notchSupportEnabled = newValue
                    }
                }
            ))
            Text(
                "Lists status extras that are cut off by this display’s menu-bar width "
                    + "(or sit under the camera gap) in the panel’s Overflow section. "
                    + "Off-screen extras use placeholders — icons need Screen Recording of on-screen windows."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Overflow")
        } footer: {
            Text("Clicking an Overflow tile moves it into the visible menu bar, then opens it. Command-drag it back to the panel to hide it again. If it still can’t open (system-owned), use the bar icons.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            HStack {
                TextField("Bundle ID or app name contains…", text: $panelNamespaceDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addPanelAlwaysShow(panelNamespaceDraft)
                    panelNamespaceDraft = ""
                }
                .disabled(panelNamespaceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let pinned = preferencesStore.config.resolvedPanelAlwaysShowNamespaces
            if pinned.isEmpty {
                Text("No always-show apps yet. Pin menu-bar apps below so they always appear in the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pinned, id: \.self) { ns in
                    HStack {
                        Text(ns)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            removePanelAlwaysShow(ns)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Always show in panel")
        } footer: {
            Text("Pinned apps appear under Hidden even when fully visible on the bar — handy for quick launch from the panel.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Button("Refresh menu-bar apps") {
                refreshMenuBarAppRows()
            }
            if menuBarAppRows.isEmpty {
                Text("Click Refresh to scan currently registered menu extras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(menuBarAppRows, id: \.namespace) { row in
                    Toggle(isOn: Binding(
                        get: {
                            preferencesStore.config.resolvedPanelAlwaysShowNamespaces.contains {
                                row.namespace.localizedCaseInsensitiveContains($0) || $0 == row.namespace
                            }
                        },
                        set: { on in
                            if on {
                                addPanelAlwaysShow(row.namespace)
                            } else {
                                removePanelAlwaysShow(row.namespace)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Text(row.namespace)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Registered menu-bar apps")
        }
        .onAppear { refreshMenuBarAppRows() }
    }

    private func addPanelAlwaysShow(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        _ = preferencesStore.updateConfig { current in
            var list = current.resolvedPanelAlwaysShowNamespaces
            if !list.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
                list.append(key)
            }
            current.panelAlwaysShowNamespaces = list
        }
    }

    private func removePanelAlwaysShow(_ raw: String) {
        _ = preferencesStore.updateConfig { current in
            current.panelAlwaysShowNamespaces = current.resolvedPanelAlwaysShowNamespaces.filter {
                $0.caseInsensitiveCompare(raw) != .orderedSame
            }
        }
    }

    private func refreshMenuBarAppRows() {
        guard let screen = NSScreen.main else {
            menuBarAppRows = []
            return
        }
        let details = MenuBarItemScanner.detailedItems(screen: screen, includeParkedPastEdge: true)
        let discovered = LiveMenuBarDiscoveryService.discoveredItems(from: details)
        var seen = Set<String>()
        var rows: [(namespace: String, name: String)] = []
        for item in discovered {
            let ns = item.identity.namespace
            guard seen.insert(ns).inserted else { continue }
            guard !ns.lowercased().contains("nicos-hidden-menubar") else { continue }
            let name = item.ownerName.isEmpty ? ns : item.ownerName
            rows.append((namespace: ns, name: name))
        }
        menuBarAppRows = rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Layout

    @ViewBuilder
    private var layoutTab: some View {
        Section {
            Toggle("Always-hidden lane", isOn: binding(\.lanes.alwaysHiddenEnabled))
            Text("Adds a second divider for items that only appear from the reveal panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show primary separator when expanded", isOn: binding(\.lanes.primarySeparatorVisibleWhenExpanded))
            Toggle("Show always-hidden separator when expanded", isOn: binding(\.lanes.secondarySeparatorVisibleWhenExpanded))
                .disabled(!preferencesStore.config.lanes.alwaysHiddenEnabled)
            Toggle("Hide marker glyphs while expanded", isOn: binding(\.hideMarkersWhileExpanded))
        } header: {
            Text("Lanes")
        } footer: {
            Text("Command-drag the chevron and separators in the menu bar. Everyday items stay right of the separator; hide candidates stay left.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Picker("Reveal mode", selection: Binding(
                get: { preferencesStore.config.configuredRevealMode },
                set: { newValue in
                    _ = preferencesStore.updateConfig { current in
                        current.revealMode = newValue
                    }
                }
            )) {
                ForEach(HiddenItemRevealMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            revealModeHelp
        } header: {
            Text("Reveal surface")
        } footer: {
            Text("Automatic picks the panel on notched displays. Overflow detection surfaces cut-off status icons even before you hide them with a separator.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Picker("Chevron color", selection: Binding(
                get: { preferencesStore.config.resolvedChevronColor },
                set: { newValue in
                    _ = preferencesStore.updateConfig { current in
                        current.chevronColor = newValue
                    }
                    // Live-apply via config publisher → applyCurrentConfiguration.
                }
            )) {
                ForEach(ChevronIconColor.allCases, id: \.self) { color in
                    Text(color.displayName).tag(color)
                }
            }
            Text("Applies to the menu-bar toggle immediately. Accessibility-off still uses a temporary orange warning tint.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Toggle appearance")
        }

        Section {
            if let reason = preferencesStore.diagnostics.geometryReason {
                Label(reason, systemImage: "wrench.and.screwdriver")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Button("Repair Marker Positions") {
                NotificationCenter.default.post(name: .nicosHiddenBarRepairMarkers, object: nil)
                repairNote = "Repair requested — markers reseeded. Command-drag if order still looks wrong."
            }
            .buttonStyle(.borderedProminent)
            Button("Open Setup Guide") {
                NotificationCenter.default.post(name: .nicosHiddenBarOpenOnboarding, object: nil)
            }
            if let repairNote {
                Text(repairNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Marker repair")
        } footer: {
            Text("If collapse reports markers off-screen or hideable count stays zero, reset preferred positions.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var revealModeHelp: some View {
        let mode = preferencesStore.config.configuredRevealMode
        let text: String = switch mode {
        case .automatic:
            "Reveal inline on regular displays and in the searchable panel on notched displays. Collapse is verified in either mode."
        case .inline:
            "Reveal hidden items back in the menu bar. A notch may still limit how many revealed items fit."
        case .belowMenuBar:
            "Always open the searchable panel under the menu bar. Best ergonomics on MacBooks with a notch."
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Behavior

    @ViewBuilder
    private var behaviorTab: some View {
        Section {
            Toggle("Launch at login", isOn: binding(\.launchAtLogin))
            HStack {
                Text("Login item: \(launchAtLoginController.statusDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if launchAtLoginController.requiresApproval {
                    Button("Open System Settings") {
                        launchAtLoginController.openSystemSettings()
                    }
                }
            }
            if let message = launchAtLoginController.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Show settings on launch", isOn: binding(\.showPreferencesOnLaunch))
            Toggle("Show Dock icon when expanded", isOn: binding(\.useRegularActivationOnExpand))
            Text("Leave off for a Dock-less accessory app. Profiles can override this.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("General")
        }

        Section {
            Toggle("Auto-collapse enabled", isOn: binding(\.autoCollapse.enabled))
            Stepper(
                value: Binding(
                    get: { preferencesStore.config.autoCollapse.seconds },
                    set: { newValue in
                        _ = preferencesStore.updateConfig { current in
                            current.autoCollapse.seconds = max(1, newValue)
                        }
                    }
                ),
                in: 1...300
            ) {
                Text("After \(preferencesStore.config.autoCollapse.seconds) seconds")
            }
            .disabled(!preferencesStore.config.autoCollapse.enabled)
        } header: {
            Text("Auto-collapse")
        } footer: {
            Text("Return to a tidy bar after a quiet period. Global defaults apply unless a profile overrides them.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Text(preferencesStore.config.globalShortcut.display)
                .font(.system(.title3, design: .monospaced))
            Toggle(
                "Shortcut enabled",
                isOn: Binding(
                    get: { preferencesStore.config.globalShortcut.enabled },
                    set: { enabled in
                        _ = preferencesStore.updateConfig { current in
                            current.globalShortcut = .deliberate(enabled: enabled)
                        }
                    }
                )
            )
        } header: {
            Text("Global shortcut")
        } footer: {
            Text("Off by default. When enabled, use the deliberate three-modifier shortcut \(GlobalShortcutSettings.deliberateDisplay).")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Picker("Active profile", selection: Binding(
                get: { profileStore.activeProfileName },
                set: { newValue in _ = profileStore.switchProfile(named: newValue) }
            )) {
                ForEach(profileStore.availableProfiles, id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
            let profile = profileStore.activeProfile
            Text("Auto-collapse: \(profile.autoCollapseEnabled ? "\(profile.autoCollapseSeconds)s" : "manual") · Dock on expand: \(profile.useRegularActivationOnExpand ? "yes" : "no")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Edit Profiles…") {
                NotificationCenter.default.post(name: .nicosHiddenBarOpenProfileEditor, object: nil)
            }
        } header: {
            Text("Profiles")
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionsTab: some View {
        Section {
            permissionRow(
                granted: accessibilityTrusted,
                okTitle: "Accessibility granted (this binary)",
                badTitle: "Accessibility not trusted for this binary"
            )
            Text("Required to open items from the reveal panel and for placement hide/move. Live check uses AXIsProcessTrusted — Settings can show ON for a stale install while this build is still denied.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !accessibilityTrusted {
                Text(PrivacyPermissions.untrustedSettingsDetail)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let hash = PrivacyPermissions.runningCodeDirectoryHash {
                    Text("Running CDHash: \(hash.prefix(16))…")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            if let accessibilityFixNote {
                Text(accessibilityFixNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Add to Privacy Settings…") {
                    PrivacyPermissions.requestAccessibilityAccessAndShowSettings()
                    refreshPermissionState()
                }
                .buttonStyle(.borderedProminent)
                Button("Open Accessibility Settings") {
                    _ = PrivacyPermissions.openAccessibilitySettings()
                }
            }
            Button("Reset & re-grant Accessibility…") {
                PrivacyPermissions.resetAndReRequestAccessibilityAccess()
                accessibilityFixNote =
                    "Cleared the old TCC row. In Accessibility, enable the new Nicos Hidden Bar entry, then return here — status refreshes automatically."
                // Re-check after the user returns from Settings.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    refreshPermissionState()
                }
            }
            .help("Fixes “Settings says ON but app says OFF” after make install / ad-hoc re-sign")
        } header: {
            Text("Accessibility")
        }
        .onAppear(perform: refreshPermissionState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }

        Section {
            permissionRow(
                granted: screenRecordingGranted,
                okTitle: "Screen Recording granted",
                badTitle: "Screen Recording optional / not granted",
                okIsRequired: false
            )
            Text("Optional — live icons in the panel. Text labels work without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Add Screen Recording…") {
                    PrivacyPermissions.requestScreenRecordingAccessAndShowSettings()
                    refreshPermissionState()
                }
                Button("Open Screen Recording Settings") {
                    _ = PrivacyPermissions.openScreenRecordingSettings()
                }
            }
        } header: {
            Text("Screen Recording")
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedTab: some View {
        Section {
            Toggle("Truly move/hide items (Cmd-drag)", isOn: optionalBinding(\.enableExperimentalItemMovement))
            Text("When enabled, panel activation can relocate an item into the visible lane if in-place open fails. Requires Accessibility. Off by default and fail-closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Experimental movement")
        }

        Section {
            ForEach(candidateTitles, id: \.self) { title in
                Toggle(
                    title,
                    isOn: Binding(
                        get: { configuredTitles.contains(title) },
                        set: { enabled in
                            _ = preferencesStore.setFirstPartyVisibleTitle(title, enabled: enabled)
                        }
                    )
                )
            }

            if bridge.status.code == .valid {
                Text("Bridge suggestion: \(bridgeSuggestedTitles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if bridgeSuggestedTitles != configuredTitles {
                    Button("Use Bridge Suggestion") {
                        _ = preferencesStore.replaceFirstPartyVisibleTitles(bridgeSuggestedTitles)
                    }
                }
            } else {
                Text("Bridge suggestion unavailable (\(bridge.status.code.rawValue)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if configuredTitles != HiddenBarConfig.default.firstPartyVisible.preferredVisibleTitles {
                Button("Restore Defaults") {
                    _ = preferencesStore.replaceFirstPartyVisibleTitles(
                        HiddenBarConfig.default.firstPartyVisible.preferredVisibleTitles
                    )
                }
            }
        } header: {
            Text("First-party visible titles")
        } footer: {
            Text("Advisory list of titles that should stay visible. Dragging markers does not rewrite this automatically.")
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Text("Marker order: \(preferencesStore.diagnostics.markerOrderStatus.rawValue)")
            Text("Geometry: \(preferencesStore.diagnostics.geometryReadable ? "readable" : (preferencesStore.diagnostics.geometryReason ?? "unreadable"))")
            if let count = preferencesStore.diagnostics.geometrySnapshot?.realHideableItemCount {
                Text("Hideable items: \(count)")
            }
            Button("Open Diagnostics Window") {
                NotificationCenter.default.post(name: .nicosHiddenBarOpenDiagnostics, object: nil)
            }
        } header: {
            Text("Diagnostics")
        }
    }

    // MARK: - Helpers

    private func refreshPermissionState() {
        _ = PrivacyPermissions.enrollAccessibility(prompt: false)
        accessibilityTrusted = PrivacyPermissions.isAccessibilityTrusted
        screenRecordingGranted = PrivacyPermissions.hasScreenRecording
        if accessibilityTrusted {
            accessibilityFixNote = nil
        }
    }

    private func permissionRow(granted: Bool, okTitle: String, badTitle: String, okIsRequired: Bool = true) -> some View {
        HStack {
            if granted {
                Label(okTitle, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(badTitle, systemImage: okIsRequired ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundStyle(okIsRequired ? .orange : .secondary)
            }
            Spacer()
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<HiddenBarConfig, Bool?>) -> Binding<Bool> {
        Binding(
            get: { preferencesStore.config[keyPath: keyPath] ?? false },
            set: { newValue in
                _ = preferencesStore.updateConfig { current in
                    current[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<HiddenBarConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferencesStore.config[keyPath: keyPath] },
            set: { newValue in
                _ = preferencesStore.updateConfig { current in
                    current[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

extension Notification.Name {
    static let nicosHiddenBarRepairMarkers = Notification.Name("nicosHiddenBarRepairMarkers")
    static let nicosHiddenBarOpenOnboarding = Notification.Name("nicosHiddenBarOpenOnboarding")
    static let nicosHiddenBarOpenProfileEditor = Notification.Name("nicosHiddenBarOpenProfileEditor")
    static let nicosHiddenBarOpenDiagnostics = Notification.Name("nicosHiddenBarOpenDiagnostics")
}
