import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var preferencesStore: PreferencesStore
    @EnvironmentObject private var bridge: HammerspoonBridge
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Nicos Hidden Bar", systemImage: "menubar.rectangle")
                .font(.title.bold())

            Text("A tidy menu bar in three quick steps")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                setupStep("1", "Hold Command and drag the chevron and separator markers into position.")
                setupStep("2", "Keep everyday items to the right of the separator; move less-used items to its left.")
                setupStep("3", "Click the chevron to collapse and reveal the hidden region.")
            }

            Text("Option-click the chevron whenever you need to reveal the markers again. Right-click it for Settings and Diagnostics.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let importNote = preferencesStore.diagnostics.importNote {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Imported preferences from \(importNote.sourceDomain)", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                    if !importNote.ignoredKeys.isEmpty {
                        Text("Ignored keys: \(importNote.ignoredKeys.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !bridge.status.preferredVisibleTitles.isEmpty {
                Text("Suggested visible items: \(bridge.status.preferredVisibleTitles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Get Started", action: onComplete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 480)
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
