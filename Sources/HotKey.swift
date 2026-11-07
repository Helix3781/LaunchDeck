import Carbon.HIToolbox
import Foundation

/// A global shortcut registered through Carbon, which needs no accessibility prompt.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                         eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.action() }
                return noErr
            }, 1, &eventType, pointer, &handlerRef)
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C444B31), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            isRegistered = true
            NSLog("LaunchDeck: hotkey registered (key=%u mods=%u)", keyCode, modifiers)
        } else {
            isRegistered = false
            NSLog("LaunchDeck: hotkey registration failed (%d) key=%u mods=%u", status, keyCode, modifiers)
        }
    }
}
