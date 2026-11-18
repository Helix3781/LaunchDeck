import Carbon.HIToolbox
import Foundation

/// Global shortcuts registered through Carbon, which needs no accessibility prompt.
/// One manager owns every slot so a single event handler can dispatch by hot key id.
final class HotKeyManager {
    /// Notification hot key IDs, one per behaviour that can be triggered globally.
    enum Slot: UInt32 {
        case panel = 1
        case screenshot = 2
    }

    private var refs: [Slot: EventHotKeyRef] = [:]
    private var actions: [Slot: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    var isRegistered: Bool { !refs.isEmpty }

    func register(_ slot: Slot, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        if let ref = refs.removeValue(forKey: slot) {
            UnregisterEventHotKey(ref)
        }
        actions[slot] = action
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C444B31), id: slot.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[slot] = ref
            NSLog("LaunchDeck: hotkey %u registered (key=%u mods=%u)", slot.rawValue, keyCode, modifiers)
        } else {
            NSLog("LaunchDeck: hotkey %u registration failed (%d) key=%u mods=%u",
                  slot.rawValue, status, keyCode, modifiers)
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let error = GetEventParameter(event,
                                          EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID),
                                          nil,
                                          MemoryLayout<EventHotKeyID>.size,
                                          nil,
                                          &hotKeyID)
            guard error == noErr, let slot = Slot(rawValue: hotKeyID.id) else { return noErr }
            DispatchQueue.main.async { manager.actions[slot]?() }
            return noErr
        }, 1, &eventType, pointer, &handlerRef)
    }
}