import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let launchDeckHotKeyChanged = Notification.Name("LaunchDeckHotKeyChanged")
}

/// The user-recordable global shortcuts, persisted in UserDefaults as Carbon key code + modifiers.
/// Two slots exist: the panel summon key and the screenshot key.
enum Shortcut {
    enum Slot {
        case panel
        case screenshot
    }

    private enum Keys {
        static let panel = (code: "launchdeck.hotkey.keyCode",
                            modifiers: "launchdeck.hotkey.modifiers",
                            label: "launchdeck.hotkey.label")
        static let screenshot = (code: "launchdeck.screenshot.keyCode",
                                 modifiers: "launchdeck.screenshot.modifiers",
                                 label: "launchdeck.screenshot.label")
    }

    /// ⌥⇧S by default: macOS owns ⌘⇧3/4/5 for screenshots, and ⇧⌘S would steal "Save As" from
    /// every other app. Option-Shift-S is unclaimed and reads as "screenshot".
    private static let screenshotDefault = (code: UInt32(kVK_ANSI_S),
                                            modifiers: UInt32(optionKey | shiftKey),
                                            label: "⌥⇧S")

    // MARK: Panel shortcut

    static var keyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: Keys.panel.code) as? Int
        return UInt32(stored ?? Int(kVK_Space))
    }

    static var modifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: Keys.panel.modifiers) as? Int
        return UInt32(stored ?? Int(optionKey))
    }

    static var label: String {
        UserDefaults.standard.string(forKey: Keys.panel.label) ?? "⌥ Space"
    }

    static func save(keyCode: UInt32, modifiers: UInt32, label: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: Keys.panel.code)
        UserDefaults.standard.set(Int(modifiers), forKey: Keys.panel.modifiers)
        UserDefaults.standard.set(label, forKey: Keys.panel.label)
        NotificationCenter.default.post(name: .launchDeckHotKeyChanged, object: nil)
    }

    static func reset() {
        for key in [Keys.panel.code, Keys.panel.modifiers, Keys.panel.label] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .launchDeckHotKeyChanged, object: nil)
    }

    // MARK: Screenshot shortcut

    static var screenshotKeyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: Keys.screenshot.code) as? Int
        return UInt32(stored ?? Int(screenshotDefault.code))
    }

    static var screenshotModifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: Keys.screenshot.modifiers) as? Int
        return UInt32(stored ?? Int(screenshotDefault.modifiers))
    }

    static var screenshotLabel: String {
        UserDefaults.standard.string(forKey: Keys.screenshot.label) ?? screenshotDefault.label
    }

    static func saveScreenshot(keyCode: UInt32, modifiers: UInt32, label: String) {
        UserDefaults.standard.set(Int(keyCode), forKey: Keys.screenshot.code)
        UserDefaults.standard.set(Int(modifiers), forKey: Keys.screenshot.modifiers)
        UserDefaults.standard.set(label, forKey: Keys.screenshot.label)
        NotificationCenter.default.post(name: .launchDeckHotKeyChanged, object: nil)
    }

    static func resetScreenshot() {
        for key in [Keys.screenshot.code, Keys.screenshot.modifiers, Keys.screenshot.label] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .launchDeckHotKeyChanged, object: nil)
    }

    // MARK: Helpers

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

    /// True when the pair is already taken by the other slot, so the recorder can refuse it.
    static func conflicts(with other: Slot, keyCode: UInt32, modifiers: UInt32) -> Bool {
        switch other {
        case .panel:
            return keyCode == Self.keyCode && modifiers == Self.modifiers
        case .screenshot:
            return keyCode == screenshotKeyCode && modifiers == screenshotModifiers
        }
    }
}