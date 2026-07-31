import SwiftUI

/// First-run / repair guide. Focused on correct hide setup: markers on-screen,
/// lane placement, reveal mode, and Accessibility for panel activation.
struct OnboardingView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var bridge: HammerspoonBridge
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Welcome to Nicos Hidden Bar", systemImage: "menubar.rectangle")
                .font(.title.bold())

            Text("Hide menu extras cleanly — especially on notched Macs")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                setupStep(
                    "1",
                    "Hold ⌘ and drag the chevron (toggle) and separator(s) onto the right side of the menu bar of the display you use."
                )
                setupStep(
                    "2",
                    "Everyday items go to the right of the primary separator; items you want hidden go between the separator and the chevron."
                )
                setupStep(
                    "3",
                    "On notched displays, leave Reveal mode on Automatic (or Below the menu bar). Click the chevron to open the searchable panel — never park items under the notch."
                )
                setupStep(
                    "4",
                    "Grant Accessibility so panel clicks can open a hidden item. Screen Recording is optional for live icons."
                )
            }

            Text("Right-click the chevron for Settings, Diagnostics, and Repair Marker Positions. Option-click temporarily expands markers.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if PrivacyPermissions.isAccessibilityTrusted {
                        Label("Accessibility is on", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Accessibility is required for opening items from the panel", systemImage: "hand.raised.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("This adds “Nicos Hidden Bar” under Privacy & Security → Accessibility so you can flip the toggle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add to Privacy Settings…") {
                            PrivacyPermissions.requestAccessibilityAccessAndShowSettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            if let importNote = preferencesStore.diagnostics.importNote {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Imported preferences from \(importNote.sourceDomain)", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                    if !importNote.ignoredKeys.isEmpty {
                        Text("Ignored keys: \(importNote.ignoredKeys.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !bridge.status.preferredVisibleTitles.isEmpty {
                Text("Suggested visible items: \(bridge.status.preferredVisibleTitles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Get Started", action: onComplete)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 520)
    }

    private func setupStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
