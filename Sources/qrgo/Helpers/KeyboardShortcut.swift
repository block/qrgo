import AppKit
import Carbon.HIToolbox
import Foundation

struct KeyboardShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifierRawValue: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifierRawValue = modifiers.intersection(Self.allowedModifiers).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
            .intersection(Self.allowedModifiers)
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) {
            value |= UInt32(cmdKey)
        }
        if modifiers.contains(.option) {
            value |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            value |= UInt32(controlKey)
        }
        if modifiers.contains(.shift) {
            value |= UInt32(shiftKey)
        }
        return value
    }

    var displayString: String {
        "\(modifiers.displayString)\(KeyboardShortcutKeyCode.displayName(for: keyCode))"
    }

    var menuKeyEquivalent: String {
        KeyboardShortcutKeyCode.menuEquivalent(for: keyCode) ?? ""
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        modifiers
    }

    var modifierCount: Int {
        var count = 0
        if modifiers.contains(.command) {
            count += 1
        }
        if modifiers.contains(.option) {
            count += 1
        }
        if modifiers.contains(.control) {
            count += 1
        }
        if modifiers.contains(.shift) {
            count += 1
        }
        return count
    }

    static let defaultScan = KeyboardShortcut(
        keyCode: KeyboardShortcutKeyCode.letterQ,
        modifiers: [.control, .shift]
    )

    static let allowedModifiers: NSEvent.ModifierFlags = [
        .command,
        .option,
        .control,
        .shift
    ]

    static func from(event: NSEvent) -> KeyboardShortcut? {
        guard !KeyboardShortcutKeyCode.isModifierKey(event.keyCode) else {
            return nil
        }
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: event.modifierFlags
        )
        return shortcut.modifiers.isEmpty ? nil : shortcut
    }
}

/// Rejects shortcuts that conflict with known macOS shortcuts, enabled symbolic hotkeys, or another app.
enum KeyboardShortcutValidator {
    static let minimumModifierMessage = "Use at least two modifier keys."

    static func validationMessage(
        for shortcut: KeyboardShortcut,
        currentShortcut: KeyboardShortcut?
    ) -> String? {
        if KnownSystemKeyboardShortcuts.contains(shortcut) ||
            SystemKeyboardShortcutStore.hasEnabledShortcut(matching: shortcut) {
            return "\(shortcut.displayString) conflicts with a macOS keyboard shortcut."
        }
        if shortcut.modifierCount < 2 {
            return minimumModifierMessage
        }
        if shortcut != currentShortcut &&
            !GlobalKeyboardShortcutAvailability.isAvailable(shortcut) {
            return "\(shortcut.displayString) is already used by another app."
        }
        return nil
    }
}

enum GlobalKeyboardShortcutAvailability {
    static func isAvailable(_ shortcut: KeyboardShortcut) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x51524754),
            id: 1
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        return status == noErr
    }
}

private enum SystemKeyboardShortcutStore {
    static func hasEnabledShortcut(matching shortcut: KeyboardShortcut) -> Bool {
        guard let domain = UserDefaults.standard.persistentDomain(
            forName: "com.apple.symbolichotkeys"
        ),
            let hotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return false
        }

        return hotKeys.values.contains { value in
            guard let dictionary = value as? [String: Any],
                  boolValue(dictionary["enabled"]) == true,
                  let shortcutValue = dictionary["value"] as? [String: Any],
                  let parameters = shortcutValue["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = uint32Value(parameters[1]),
                  let modifierRawValue = uintValue(parameters[2]) else {
                return false
            }
            // Symbolic hotkey parameters are stored as `[character, keyCode, modifiers]`.
            let modifiers = NSEvent.ModifierFlags(rawValue: modifierRawValue)
                .intersection(KeyboardShortcut.allowedModifiers)
            return keyCode == shortcut.keyCode && modifiers == shortcut.modifiers
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func uint32Value(_ value: Any?) -> UInt32? {
        guard let value = uintValue(value) else {
            return nil
        }
        return UInt32(value)
    }

    private static func uintValue(_ value: Any?) -> UInt? {
        if let value = value as? UInt {
            return value
        }
        if let value = value as? Int {
            return value >= 0 ? UInt(value) : nil
        }
        return (value as? NSNumber)?.uintValue
    }
}

private enum KnownSystemKeyboardShortcuts {
    static func contains(_ shortcut: KeyboardShortcut) -> Bool {
        shortcuts.contains(shortcut)
    }

    private static let shortcuts: Set<KeyboardShortcut> = [
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.space, modifiers: [.command]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.space, modifiers: [.command, .option]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.space, modifiers: [.command, .control]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.tab, modifiers: [.command]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.tab, modifiers: [.command, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.grave, modifiers: [.command]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.grave, modifiers: [.command, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.escape, modifiers: [.command, .option]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.escape, modifiers: [.command, .option, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.letterQ, modifiers: [.command, .control]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.letterQ, modifiers: [.command, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.letterQ, modifiers: [.command, .option, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.letterD, modifiers: [.command, .option]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.three, modifiers: [.command, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.four, modifiers: [.command, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.five, modifiers: [.command, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.three, modifiers: [.command, .control, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.four, modifiers: [.command, .control, .shift]),
        KeyboardShortcut(keyCode: KeyboardShortcutKeyCode.five, modifiers: [.command, .control, .shift])
    ]
}

enum KeyboardShortcutKeyCode {
    static let letterQ: UInt32 = 12
    static let letterD: UInt32 = 2
    static let three: UInt32 = 20
    static let four: UInt32 = 21
    static let five: UInt32 = 23
    static let tab: UInt32 = 48
    static let space: UInt32 = 49
    static let grave: UInt32 = 50
    static let escape: UInt32 = 53

    static func displayName(for keyCode: UInt32) -> String {
        displayNames[keyCode] ?? "Key \(keyCode)"
    }

    static func menuEquivalent(for keyCode: UInt32) -> String? {
        menuEquivalents[keyCode]
    }

    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(UInt32(keyCode))
    }

    private static let modifierKeyCodes: Set<UInt32> = [
        54,
        55,
        56,
        57,
        58,
        59,
        60,
        61,
        62,
        63
    ]

    private static let displayNames: [UInt32: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        36: "Return",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "Tab",
        49: "Space",
        50: "`",
        51: "Delete",
        53: "Esc",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow"
    ]

    private static let menuEquivalents: [UInt32: String] = [
        0: "a",
        1: "s",
        2: "d",
        3: "f",
        4: "h",
        5: "g",
        6: "z",
        7: "x",
        8: "c",
        9: "v",
        11: "b",
        12: "q",
        13: "w",
        14: "e",
        15: "r",
        16: "y",
        17: "t",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "o",
        32: "u",
        33: "[",
        34: "i",
        35: "p",
        37: "l",
        38: "j",
        39: "'",
        40: "k",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "n",
        46: "m",
        47: ".",
        49: " ",
        50: "`"
    ]
}

private extension NSEvent.ModifierFlags {
    var displayString: String {
        var result = ""
        if contains(.control) {
            result += "⌃"
        }
        if contains(.option) {
            result += "⌥"
        }
        if contains(.shift) {
            result += "⇧"
        }
        if contains(.command) {
            result += "⌘"
        }
        return result
    }
}
