import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var bridge: HammerspoonBridge

    var body: some View {
        Form {
            Section("Marker Order") {
                Text(preferencesStore.diagnostics.markerOrderStatus.rawValue)
                Text("Active profile: \(profileStore.activeProfileName)")
                    .foregroundStyle(.secondary)
            }

            Section("Geometry") {
                Text(preferencesStore.diagnostics.geometryReadable ? "readable" : "geometry_unreadable")
                if let reason = preferencesStore.diagnostics.geometryReason {
                    Text(reason).foregroundStyle(.secondary)
                }
            }

            Section("Real Menu Bar (window server)") {
                let snapshot = preferencesStore.diagnostics.geometrySnapshot
                Text("Items detected: \(snapshot?.realItemCount.map(String.init) ?? "—")")
                Text("Hideable (left of toggle): \(snapshot?.realHideableItemCount.map(String.init) ?? "—")")
                    .foregroundStyle(.secondary)
                if let notch = snapshot?.notchDetected {
                    Text(notch ? "Notched display — verifying collapse against real frames" : "No notch")
                        .foregroundStyle(.secondary)
                }
                switch preferencesStore.diagnostics.lastCollapseHidItems {
                case .some(true):
                    Label("Last collapse hid items ✓", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                case .some(false):
                    Label("Last collapse hid nothing — items may be stuck under the notch", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .none:
                    Text("Collapse not yet verified")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Bridge") {
                Text(bridge.status.code.rawValue)
                if let message = bridge.status.message {
                    Text(message).foregroundStyle(.secondary)
                }
                if !preferencesStore.config.firstPartyVisible.preferredVisibleTitles.isEmpty {
                    Text("Configured titles: \(preferencesStore.config.firstPartyVisible.preferredVisibleTitles.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
                if !bridge.status.preferredVisibleTitles.isEmpty {
                    Text("Bridge-suggested titles: \(bridge.status.preferredVisibleTitles.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Import Note") {
                if let importNote = preferencesStore.diagnostics.importNote {
                    Text(importNote.sourceDomain)
                    Text("ignored_keys: \(importNote.ignoredKeys.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No import note recorded.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shortcut") {
                Text(preferencesStore.diagnostics.hotkeyStatus.rawValue)
                if let message = preferencesStore.diagnostics.hotkeyMessage {
                    Text(message).foregroundStyle(.secondary)
                }
            }

            if let ignoredURL = preferencesStore.diagnostics.lastIgnoredURL {
                Section("Ignored URL") {
                    Text(ignoredURL)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding()
        .frame(width: 540, height: 460)
    }
}
