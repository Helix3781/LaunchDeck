import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let launchDeckHotKeyChanged = Notification.Name("LaunchDeckHotKeyChanged")
}

/// The user-recordable global shortcut, persisted in UserDefaults as Carbon key code + modifiers.
enum Shortcut {
    private static let keyCodeKey = "launchdeck.hotkey.keyCode"
    private static let modifiersKey = "launchdeck.hotkey.modifiers"
    private static let labelKey = "launchdeck.hotkey.label"

    static var keyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: keyCodeKey) as? Int
        return UInt32(stored ?? Int(kVK_Space))
    }

    static var modifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: modifiersKey) as? Int
        return UInt32(stored ?? Int(optionKey))
    }

    static var label: String {
        UserDefaults.standard.string(forKey: labelKey) ?? "⌥ Space"
    }

    static func save(keyCode: UInt32, modifiers: UInt32, label: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey)
        UserDefaults.standard.set(label, forKey: labelKey)
        NotificationCenter.default.post(name: .launchDeckHotKeyChanged, object: nil)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: keyCodeKey)
        UserDefaults.standard.removeObject(forKey: modifiersKey)
        UserDefaults.standard.removeObject(forKey: labelKey)
        NotificationCenter.default.post(name: .launchDeckHotKeyChanged, object: nil)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func describe(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }

        let special: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        ]
        if let name = special[keyCode] {
            return text + name
        }
        if let characters, !characters.isEmpty {
            return text + characters.uppercased()
        }
        return text + "Key\(keyCode)"
    }
}
