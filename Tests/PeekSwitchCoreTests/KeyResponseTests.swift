import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// What each key does while the overlay is up.
///
/// The reason this suite exists: with the shortcut set to ⌥Space, pressing it again typed a space
/// into the search field instead of closing the overlay. The tap consumed the keystroke, so the
/// hotkey behind it never fired — the toggle appeared broken when the keystroke was never delivered.
///
/// The guard meant to prevent that tested the event's modifier flags, and this tap runs at
/// `.cghidEventTap` where those are not dependable. The `noModifiers` cases below encode the
/// situation that actually occurs: the space arrives with no Option flag on it at all.
@Suite("Key response")
struct KeyResponseTests {

    private static let space: Int64 = 49
    private static let letterA: Int64 = 0
    private static let tab: Int64 = 48

    private static let noModifiers = CGEventFlags(rawValue: 0)
    private static let option = CGEventFlags.maskAlternate
    private static let command = CGEventFlags.maskCommand

    // MARK: - The defect

    /// The exact failure, reproduced: ⌥Space as the shortcut, and the repeat arriving with no
    /// modifier flag. It must not become a search character.
    @Test("The shortcut's key never types, even with no modifier flag on the event")
    func shortcutKeyNeverTypes() {
        let response = KeyResponse.forKeyDown(
            keyCode: Self.space,
            flags: Self.noModifiers,
            characters: " ",
            shortcutKeyCode: Self.space
        )
        #expect(response == .passThrough)
    }

    /// Passing it through is the half that fixes the toggle: the hotkey only fires if the tap lets
    /// the event continue down the pipeline.
    @Test("The shortcut's key is passed on so the hotkey can act on it", arguments: [
        CGEventFlags(rawValue: 0), CGEventFlags.maskAlternate,
    ])
    func shortcutKeyReachesTheHotkey(flags: CGEventFlags) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                flags: flags,
                characters: " ",
                shortcutKeyCode: Self.space
            ) == .passThrough
        )
    }

    /// A shortcut on a different key must not stop that key from being typed.
    @Test("Only the shortcut's own key is protected")
    func otherKeysStillType() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.letterA,
                flags: Self.noModifiers,
                characters: "a",
                shortcutKeyCode: Self.space
            ) == .typeIntoSearch("a")
        )
    }

    /// With no shortcut registered — registration can fail — a space is ordinary typing again.
    @Test("Space types normally when no shortcut is registered")
    func spaceTypesWithoutAShortcut() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                flags: Self.noModifiers,
                characters: " ",
                shortcutKeyCode: nil
            ) == .typeIntoSearch(" ")
        )
    }

    // MARK: - Keys that mean something else

    @Test("Escape dismisses whatever the shortcut is")
    func escapeDismisses() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.escapeKeyCode,
                flags: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: KeyResponse.escapeKeyCode
            ) == .dismiss
        )
    }

    @Test("Return and the keypad's Enter both confirm", arguments: [
        KeyResponse.returnKeyCode, KeyResponse.keypadEnterKeyCode,
    ])
    func returnConfirms(keyCode: Int64) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: keyCode,
                flags: Self.noModifiers,
                characters: "\r",
                shortcutKeyCode: nil
            ) == .confirm
        )
    }

    @Test("Both delete keys shorten the query", arguments: [
        KeyResponse.deleteKeyCode, KeyResponse.forwardDeleteKeyCode,
    ])
    func deleteShortensTheQuery(keyCode: Int64) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: keyCode,
                flags: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: nil
            ) == .deleteSearchCharacter
        )
    }

    // MARK: - Chords belong to the system

    /// ⌘Tab and friends have to keep working while the overlay is up.
    @Test("A command chord is left alone")
    func commandChordPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.tab,
                flags: Self.command,
                characters: "\t",
                shortcutKeyCode: nil
            ) == .passThrough
        )
    }

    @Test("An option chord is not typing")
    func optionChordPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.letterA,
                flags: Self.option,
                characters: "å",
                shortcutKeyCode: Self.space
            ) == .passThrough
        )
    }

    /// A key that types nothing has nothing to contribute to a search.
    @Test("A key with no characters is left alone")
    func keyWithoutCharactersPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: 63,
                flags: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: nil
            ) == .passThrough
        )
    }
}
