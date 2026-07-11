import Combine
import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var availableProfiles: [String]
    @Published private(set) var activeProfileName: String

    private let preferencesStore: PreferencesStore
    private var cancellables: Set<AnyCancellable> = []

    init(preferencesStore: PreferencesStore = .shared) {
        self.preferencesStore = preferencesStore
        self.availableProfiles = Self.orderedProfileNames(from: preferencesStore.config.profiles)
        self.activeProfileName = preferencesStore.config.activeProfile

        preferencesStore.$config
            .sink { [weak self] config in
                guard let self else { return }
                self.availableProfiles = Self.orderedProfileNames(from: config.profiles)
                self.activeProfileName = config.activeProfile
            }
            .store(in: &cancellables)
    }

    var activeProfile: HiddenBarProfile {
        preferencesStore.config.activeProfileSettings
    }

    @discardableResult
    func switchProfile(named name: String) -> Bool {
        preferencesStore.setActiveProfile(name)
    }

    @discardableResult
    func updateProfile(named name: String, profile: HiddenBarProfile) -> Bool {
        preferencesStore.updateConfig { current in
            current.profiles[name] = profile
        }
    }

    private static func orderedProfileNames(from profiles: [String: HiddenBarProfile]) -> [String] {
        let preferredOrder = ["default", "focus", "present", "recording"]
        let preferred = preferredOrder.filter { profiles[$0] != nil }
        let remainder = profiles.keys.filter { !preferredOrder.contains($0) }.sorted()
        return preferred + remainder
    }
}
