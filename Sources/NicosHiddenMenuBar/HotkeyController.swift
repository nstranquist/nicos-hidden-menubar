import Carbon
import Combine
import Foundation

@MainActor
final class HotkeyController: ObservableObject {
    @Published private(set) var shortcutDisplay: String

    private let preferencesStore: PreferencesStore
    private let onTrigger: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var cancellables: Set<AnyCancellable> = []
    private let signature: OSType = 0x4e48424d

    init(
        preferencesStore: PreferencesStore = .shared,
        onTrigger: @escaping () -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.onTrigger = onTrigger
        self.shortcutDisplay = preferencesStore.config.globalShortcut.display

        preferencesStore.$config
            .sink { [weak self] config in
                self?.apply(config: config)
            }
            .store(in: &cancellables)

        apply(config: preferencesStore.config)
    }

    private func apply(config: HiddenBarConfig) {
        shortcutDisplay = config.globalShortcut.display
        unregister()

        guard config.globalShortcut.enabled else {
            preferencesStore.recordHotkey(status: .unknown, message: "Global shortcut disabled.")
            return
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.onTrigger()
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(config.globalShortcut.keyCode),
            UInt32(config.globalShortcut.carbonFlags),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            preferencesStore.recordHotkey(status: .valid, message: nil)
        } else {
            preferencesStore.recordHotkey(status: .invalid, message: "RegisterEventHotKey returned \(status).")
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
