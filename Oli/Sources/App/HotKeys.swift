import AppKit
import Carbon.HIToolbox

// MARK: - Raccourcis globaux
// ⌥⌘O open / fold, ⌥⌘T terminal, ⌥⌘J ask Oli. Registered with Carbon (works from any app).

@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef?] = []

    private static let actions: [UInt32: @MainActor () -> Void] = [
        1: { NotchController.shared.toggle(.home) },
        2: { NotchController.shared.toggle(.terminal) },
        3: { NotchController.shared.toggle(.chat) },
    ]

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let n = id.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.actions[n]?() } }
            return noErr
        }, 1, &spec, nil, nil)
        let mods = UInt32(optionKey | cmdKey)
        for (n, key) in [(UInt32(1), kVK_ANSI_O), (2, kVK_ANSI_T), (3, kVK_ANSI_J)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), mods, EventHotKeyID(signature: OSType(0x4F4C4921), id: n),  // 'OLI!'
                                GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
    }
}
