import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var bridge: HammerspoonBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nicos Hidden Bar")
                .font(.title2.bold())

            Text("Drag the separator markers so the toggle stays on the right and your first-party items remain in the visible lane.")

            if !bridge.status.preferredVisibleTitles.isEmpty {
                Text("Bridge-suggested visible titles: \(bridge.status.preferredVisibleTitles.joined(separator: ", "))")
                    .foregroundStyle(.secondary)
            }

            Text("If you want a different persisted first-party visible set, change it in Settings. Dragging the markers only changes layout; it does not rewrite the config.")
                .foregroundStyle(.secondary)

            if let importNote = preferencesStore.diagnostics.importNote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Imported from \(importNote.sourceDomain)")
                        .font(.headline)
                    if !importNote.ignoredKeys.isEmpty {
                        Text("Ignored keys: \(importNote.ignoredKeys.joined(separator: ", "))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Use Option-click on the toggle to temporarily reveal the markers for drag setup.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(width: 500, height: 420)
    }
}
