import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let region = Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey))
    static let long = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey))

    var display: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Shortcut.keyName(keyCode))
        return parts.joined()
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
            0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1",
            0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
            0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L",
            0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",",
            0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
            0x24: "↩", 0x30: "⇥", 0x31: "空格", 0x33: "⌫", 0x35: "⎋",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑"
        ]
        return names[keyCode] ?? "键\(keyCode)"
    }
}

enum ShortcutKind: String {
    case region
    case long
}

enum ShortcutStore {
    private static let didShowGuideKey = "didShowGuide"

    static var didShowGuide: Bool {
        get { UserDefaults.standard.bool(forKey: didShowGuideKey) }
        set { UserDefaults.standard.set(newValue, forKey: didShowGuideKey) }
    }

    static func load(_ kind: ShortcutKind) -> Shortcut {
        let defaults = UserDefaults.standard
        let key = "shortcut.\(kind.rawValue).key"
        let modifiers = "shortcut.\(kind.rawValue).modifiers"
        guard defaults.object(forKey: key) != nil else {
            return kind == .region ? .region : .long
        }
        return Shortcut(
            keyCode: UInt32(defaults.integer(forKey: key)),
            modifiers: UInt32(defaults.integer(forKey: modifiers))
        )
    }

    static func save(_ kind: ShortcutKind, _ shortcut: Shortcut) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: "shortcut.\(kind.rawValue).key")
        defaults.set(Int(shortcut.modifiers), forKey: "shortcut.\(kind.rawValue).modifiers")
    }
}
