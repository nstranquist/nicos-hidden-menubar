import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var bridge: HammerspoonBridge
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

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

    var body: some View {
        Form {
            Section("General") {
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
                Toggle("Show preferences on launch", isOn: binding(\.showPreferencesOnLaunch))
                Toggle("Use regular activation on expand", isOn: binding(\.useRegularActivationOnExpand))
                Toggle("Hide markers while expanded", isOn: binding(\.hideMarkersWhileExpanded))
            }

            Section("Hidden Items") {
                Picker("Reveal hidden items", selection: Binding(
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
                Text("Automatic uses the compact menu bar on regular displays and expands below the menu bar on notched displays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Experimental: truly move/hide items (Cmd-drag)", isOn: optionalBinding(\.enableExperimentalItemMovement))
                Text("Synthesizes Command-drag to rearrange another app's items. Off by default — it manipulates your real menu bar and needs Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if MenuBarItemImageCapture.hasScreenRecordingPermission() {
                    Label("Screen Recording granted — the panel shows item icons", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Screen Recording for item icons") {
                        MenuBarItemImageCapture.requestScreenRecordingPermission()
                    }
                }
            }

            Section("Auto Collapse") {
                Toggle("Enabled", isOn: binding(\.autoCollapse.enabled))
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
                    Text("\(preferencesStore.config.autoCollapse.seconds) seconds")
                }
            }

            Section("Shortcut") {
                Text(preferencesStore.config.globalShortcut.display)
                    .font(.system(.body, design: .monospaced))
                Toggle("Shortcut enabled", isOn: binding(\.globalShortcut.enabled))
            }

            Section("Lanes") {
                Toggle("Always hidden lane enabled", isOn: binding(\.lanes.alwaysHiddenEnabled))
                Toggle("Primary separator visible when expanded", isOn: binding(\.lanes.primarySeparatorVisibleWhenExpanded))
                Toggle("Secondary separator visible when expanded", isOn: binding(\.lanes.secondarySeparatorVisibleWhenExpanded))
            }

            Section("Profiles") {
                Picker("Active profile", selection: Binding(
                    get: { profileStore.activeProfileName },
                    set: { newValue in _ = profileStore.switchProfile(named: newValue) }
                )) {
                    ForEach(profileStore.availableProfiles, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section("First Party Visible Titles") {
                Text("Configured titles are persisted in config. Dragging markers does not rewrite this list automatically.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
                        .foregroundStyle(.secondary)

                    if bridgeSuggestedTitles != configuredTitles {
                        Button("Use Bridge Suggestion") {
                            _ = preferencesStore.replaceFirstPartyVisibleTitles(bridgeSuggestedTitles)
                        }
                    }
                } else {
                    Text("Bridge suggestion unavailable.")
                        .foregroundStyle(.secondary)
                }

                if configuredTitles != HiddenBarConfig.default.firstPartyVisible.preferredVisibleTitles {
                    Button("Restore Defaults") {
                        _ = preferencesStore.replaceFirstPartyVisibleTitles(
                            HiddenBarConfig.default.firstPartyVisible.preferredVisibleTitles
                        )
                    }
                }
            }
        }
        .padding()
        .formStyle(.grouped)
        .frame(minWidth: 640, minHeight: 680)
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

    private func binding(_ keyPath: WritableKeyPath<HiddenBarConfig, AutoCollapseSettings>) -> Binding<AutoCollapseSettings> {
        Binding(
            get: { preferencesStore.config[keyPath: keyPath] },
            set: { newValue in
                _ = preferencesStore.updateConfig { current in
                    current[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<HiddenBarConfig, LaneSettings>) -> Binding<LaneSettings> {
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
