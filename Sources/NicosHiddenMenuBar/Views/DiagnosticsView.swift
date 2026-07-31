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
                Text(preferencesStore.diagnostics.geometryReadable ? "readable" : "needs repair")
                if let reason = preferencesStore.diagnostics.geometryReason {
                    Text(reason)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                if let snapshot = preferencesStore.diagnostics.geometrySnapshot {
                    Text("toggle minX: \(format(snapshot.toggleMinX))")
                        .font(.caption.monospaced())
                    Text("primary minX: \(format(snapshot.primaryMinX))")
                        .font(.caption.monospaced())
                    Text("secondary minX: \(format(snapshot.secondaryMinX))")
                        .font(.caption.monospaced())
                    Text("screen visible maxX: \(format(snapshot.primaryScreenVisibleMaxX))")
                        .font(.caption.monospaced())
                }
            }

            Section("Real Menu Bar (window server)") {
                let snapshot = preferencesStore.diagnostics.geometrySnapshot
                Text("Items detected: \(snapshot?.realItemCount.map(String.init) ?? "—")")
                Text("Hideable (left of toggle): \(snapshot?.realHideableItemCount.map(String.init) ?? "—")")
                    .foregroundStyle(.secondary)
                if let leftmost = snapshot?.realLeftmostMinX {
                    Text("Leftmost item minX: \(String(format: "%.1f", leftmost))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let notch = snapshot?.notchDetected {
                    Text(notch ? "Notched display — spacer path fail-closed; panel preferred" : "No notch")
                        .foregroundStyle(.secondary)
                }
                switch preferencesStore.diagnostics.lastCollapseHidItems {
                case .some(true):
                    Label("Last collapse hid items ✓", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                case .some(false):
                    Label("Last collapse hid nothing — use panel / repair markers", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                case .none:
                    Text("Collapse not yet verified")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Dogfood") {
                let d = preferencesStore.diagnostics.dogfood ?? .default
                Text("Reveal panel opens: \(d.revealPanelOpens) · dismisses: \(d.revealPanelDismisses)")
                Text("Placement hide starts: \(d.placementHideStarts)")
                Text("Hide success: \(d.placementHideSuccesses) · fail: \(d.placementHideFailures)")
                if let reason = d.lastPlacementHideReason {
                    Text("Last hide: \(reason)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("AX samples trusted/untrusted: \(d.accessibilityTrustedSamples)/\(d.accessibilityUntrustedSamples)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Counters live in ~/.config/nicos-hidden-menubar/diagnostics.json")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("Repair") {
                Text("If markers sit far off-screen (negative minX on a single display) or hideable count is 0, reset preferred positions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Repair Marker Positions") {
                    NotificationCenter.default.post(name: .nicosHiddenBarRepairMarkers, object: nil)
                }
                .buttonStyle(.borderedProminent)
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
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 560, minHeight: 520)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}
