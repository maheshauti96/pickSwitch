import Carbon.HIToolbox
import Foundation

/// Turns a key code and modifier mask into the label a Mac user expects to read.
///
/// Needed because a recorded shortcut is persisted as nothing but a key code and a mask —
/// there is no room to store the text — so the label has to be reconstructed every time it
/// is loaded.
enum KeyNaming {

    /// Keys whose name is a word or a symbol rather than the character they type.
    ///
    /// These have to be a fixed table: asking the keyboard layout what Return produces gives
    /// a carriage return, which is not something to print in a menu.
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_ANSI_KeypadEnter: "Enter",
        kVK_Tab: "Tab",
        kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "Escape",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "Home",
        kVK_End: "End",
        kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down",
        kVK_Help: "Help",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Function keys are the only ones usable with no modifier at all, because they type
    /// nothing on their own.
    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
        kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(Int(keyCode))
    }

    /// The full label, e.g. `⌃⌥⌘Space`.
    ///
    /// Modifier order follows Apple's convention — Control, Option, Shift, Command — so it
    /// reads the same way as every menu on the system.
    static func description(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var label = ""
        if carbonModifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label + keyLabel(for: keyCode)
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }

        // The layout is consulted only on the main thread, because Text Input Services is
        // main-thread-only — calling it from a background thread aborts the process, which is
        // exactly what happened when the parallel test suite reached this code. The standard
        // table below is a correct answer for the common case and a safe one everywhere.
        if Thread.isMainThread,
           let character = MainActor.assumeIsolated({ layoutCharacter(for: keyCode) }),
           !character.isEmpty {
            return character.uppercased()
        }
        if let standard = standardKeys[Int(keyCode)] { return standard.uppercased() }
        return "Key \(keyCode)"
    }

    /// The US layout's printable keys, as a deterministic fallback.
    private static let standardKeys: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
        kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
        kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
        kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
        kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
    ]

    /// Ask the active keyboard layout what this key types.
    ///
    /// Going through the layout rather than assuming a US keyboard: on a French or German
    /// layout the key at a given position produces a different character, and labelling it
    /// with the American one would be wrong on the user's own keyboard.
    @MainActor
    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)

            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                // No modifiers: the label should be the bare key, since the modifiers are
                // already shown as symbols beside it.
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )

            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
