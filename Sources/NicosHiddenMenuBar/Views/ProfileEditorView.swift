import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var selectedProfile = "default"

    var body: some View {
        Form {
            Picker("Profile", selection: $selectedProfile) {
                ForEach(profileStore.availableProfiles, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            if let profile = preferencesStore.config.profiles[selectedProfile] {
                Toggle(
                    "Auto collapse enabled",
                    isOn: Binding(
                        get: { profile.autoCollapseEnabled },
                        set: { newValue in
                            updateSelectedProfile { current in
                                current.autoCollapseEnabled = newValue
                            }
                        }
                    )
                )

                Stepper(
                    value: Binding(
                        get: { profile.autoCollapseSeconds },
                        set: { newValue in
                            updateSelectedProfile { current in
                                current.autoCollapseSeconds = max(1, newValue)
                            }
                        }
                    ),
                    in: 1...300
                ) {
                    Text("\(profile.autoCollapseSeconds) seconds")
                }

                Toggle(
                    "Use regular activation on expand",
                    isOn: Binding(
                        get: { profile.useRegularActivationOnExpand },
                        set: { newValue in
                            updateSelectedProfile { current in
                                current.useRegularActivationOnExpand = newValue
                            }
                        }
                    )
                )
            }

            Section("Configured First Party Visible Titles") {
                Text(preferencesStore.config.firstPartyVisible.preferredVisibleTitles.joined(separator: ", "))
                    .font(.system(.body, design: .monospaced))
                Text("Edit this in Settings. Hidden Bar persists the configured list; dragging markers alone does not rewrite it.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 480, height: 420)
        .onAppear {
            selectedProfile = profileStore.activeProfileName
        }
    }

    private func updateSelectedProfile(_ transform: (inout HiddenBarProfile) -> Void) {
        guard var profile = preferencesStore.config.profiles[selectedProfile] else {
            return
        }
        transform(&profile)
        _ = profileStore.updateProfile(named: selectedProfile, profile: profile)
    }
}
