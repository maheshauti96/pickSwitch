import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut for opening the overlay (Requirement 6).
///
/// This became configurable because the fixed ⌃⌥Space turned out not to fire on a
/// real machine even though registration reported success. That is the signature of
/// another process already holding the combination: `RegisterEventHotKey` does not
/// fail in that situation, the keystroke simply never arrives. With no way to change
/// it, the shortcut was unfixable from the user's side.
///
/// A short preset list rather than a full shortcut recorder: a recorder is a
/// surprising amount of UI for a secondary trigger, and a handful of combinations that
/// are rarely contended covers the actual need.
struct HotKeyShortcut: Equatable, Hashable, Codable, Sendable, Identifiable {

    let keyCode: UInt32
    /// Carbon modifier mask (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`).
    let carbonModifiers: UInt32
    let displayName: String

    var id: String { "\(carbonModifiers)-\(keyCode)" }

    // MARK: - Presets

    static let controlOptionSpace = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥Space"
    )

    static let optionSpace = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey),
        displayName: "⌥Space"
    )

    static let controlOptionTab = HotKeyShortcut(
        keyCode: UInt32(kVK_Tab),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥Tab"
    )

    static let controlOptionGrave = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_Grave),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥`"
    )

    static let commandShiftBackslash = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_Backslash),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        displayName: "⌘⇧\\"
    )

    /// Three modifiers plus Space. Nothing else realistically claims this, which makes it
    /// the shortcut to reach for when another application is silently swallowing a
    /// simpler one — and unlike F13 it can actually be typed on any keyboard.
    static let hyperSpace = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘Space"
    )

    /// F13 has no default binding, which is why it is a popular remapping target.
    ///
    /// It is also absent from every laptop keyboard and most compact ones: only extended
    /// keyboards with a numeric keypad have it. That matters more than it first appears,
    /// because remapping software records a shortcut by asking you to *press* it — a key
    /// you cannot press is a key you cannot assign. Offered for people on an extended
    /// keyboard, not as general advice.
    static let f13 = HotKeyShortcut(
        keyCode: UInt32(kVK_F13),
        carbonModifiers: 0,
        displayName: "F13"
    )

    static let presets: [HotKeyShortcut] = [
        .controlOptionSpace,
        .hyperSpace,
        .optionSpace,
        .controlOptionTab,
        .controlOptionGrave,
        .commandShiftBackslash,
        .f13,
    ]

    /// Something the user needs to know before choosing this one.
    var caveat: String? {
        self == .f13
            ? "Only extended keyboards have F13. Laptop and compact keyboards do not, and you cannot assign a key you cannot press."
            : nil
    }

    static let `default` = HotKeyShortcut.controlOptionSpace

    // MARK: - Storage

    /// Packed into one integer so `SettingsStore` stays a plain key-value store.
    var storageValue: Int { Int(carbonModifiers) << 16 | Int(keyCode) }

    /// Rebuild a shortcut from storage.
    ///
    /// Presets are matched first so they keep their hand-written labels, but anything else is
    /// reconstructed rather than rejected. That matters: a recorded shortcut is not in the
    /// preset list, and an earlier version of this returned `nil` for anything that was not,
    /// which would have silently thrown away every custom choice on the next launch.
    static func from(storageValue: Int) -> HotKeyShortcut? {
        let keyCode = UInt32(storageValue & 0xFFFF)
        let modifiers = UInt32((storageValue >> 16) & 0xFFFF)

        if let preset = presets.first(where: {
            $0.keyCode == keyCode && $0.carbonModifiers == modifiers
        }) {
            return preset
        }
        return recorded(keyCode: keyCode, carbonModifiers: modifiers)
    }

    /// A shortcut captured from the keyboard, labelled from the active layout.
    ///
    /// - Returns: `nil` when the combination would be a bad global shortcut. See
    ///   `isUsableAsGlobalShortcut`.
    static func recorded(keyCode: UInt32, carbonModifiers: UInt32) -> HotKeyShortcut? {
        guard isUsableAsGlobalShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers) else {
            return nil
        }
        return HotKeyShortcut(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers,
            displayName: KeyNaming.description(keyCode: keyCode, carbonModifiers: carbonModifiers)
        )
    }

    /// Whether a combination is safe to claim system-wide.
    ///
    /// A global shortcut fires whatever the user is doing, so a bare letter — or a letter with
    /// only Shift — would trigger the switcher in the middle of typing a sentence. Requiring
    /// Control, Option or Command prevents that. Function keys are exempt because they type
    /// nothing on their own, which is exactly why they make good shortcuts.
    static func isUsableAsGlobalShortcut(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        guard isPlausible(keyCode: keyCode, carbonModifiers: carbonModifiers) else { return false }
        if KeyNaming.isFunctionKey(keyCode) { return true }

        let meaningful = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        return carbonModifiers & meaningful != 0
    }

    /// Whether these values could have come from a real keystroke at all.
    ///
    /// Reconstructing arbitrary shortcuts from storage means a corrupted or hand-edited
    /// preference must not produce a shortcut for a key that does not exist. Virtual key
    /// codes are 7-bit, and the modifier mask has five meaningful bits, so anything outside
    /// those is not a keystroke and falls back to the default instead.
    private static func isPlausible(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        let knownModifiers = UInt32(cmdKey | shiftKey | alphaLock | optionKey | controlKey)
        return keyCode <= 127 && carbonModifiers & ~knownModifiers == 0
    }

    /// Why a combination was refused, for the recorder to show.
    static func rejectionReason(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        guard !isUsableAsGlobalShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers) else {
            return nil
        }
        return """
        Add Control, Option or Command. Without one of those the shortcut would fire while \
        you were typing.
        """
    }
}
