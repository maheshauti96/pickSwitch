import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import VortexflowCore

/// What each key does while the overlay is up.
///
/// This suite has now been written twice, and the second time is the interesting one.
///
/// It started because ⌥Space as the shortcut, pressed again to close the overlay, typed a space into
/// the search field instead. The tap consumed the keystroke, so the hotkey behind it never fired. The
/// first fix passed the shortcut's key code through whenever it appeared — which closed the overlay
/// and made a space impossible to type at all. That shipped, and was reported as a bug immediately:
/// a search field that refuses the space bar is not a reasonable trade for a working toggle.
///
/// The second fix distinguishes the two cases properly, using the modifiers *currently held* rather
/// than the ones attached to the event. The distinction matters because this tap runs at
/// `.cghidEventTap`, where a key event does not reliably carry the modifier state the window server
/// later attaches; a live keyboard query is not subject to that. Both readings are covered below.
@Suite("Key response")
struct KeyResponseTests {

    private static let space: Int64 = 49
    private static let letterA: Int64 = 0
    private static let tab: Int64 = 48

    private static let noModifiers = CGEventFlags(rawValue: 0)
    private static let option = CGEventFlags.maskAlternate
    private static let control = CGEventFlags.maskControl
    private static let command = CGEventFlags.maskCommand

    // MARK: - The two defects, one on each side

    /// The original defect: the shortcut pressed again must close the overlay, not type. Answered
    /// here and consumed, rather than passed through and left to the Carbon hotkey — this layer
    /// already knows what the combination means.
    @Test("the full shortcut chord toggles the overlay rather than typing")
    func shortcutChordToggles() {
        let response = KeyResponse.forKeyDown(
            keyCode: Self.space,
            activeModifiers: Self.option,
            characters: " ",
            shortcutKeyCode: Self.space,
            shortcutModifiers: Self.option
        )
        // Not `.dismiss`. Escape backs out of an active search before closing anything, which is
        // right for Escape and wrong for the shortcut — it would eat a query instead of closing.
        #expect(response == .triggerShortcut)
    }

    /// The defect introduced by the first fix. Under ⌥Space, a bare space is the user typing, and
    /// refusing it made the space bar dead in the search field.
    @Test("the shortcut's key without its modifiers is ordinary typing")
    func bareShortcutKeyTypes() {
        let response = KeyResponse.forKeyDown(
            keyCode: Self.space,
            activeModifiers: Self.noModifiers,
            characters: " ",
            shortcutKeyCode: Self.space,
            shortcutModifiers: Self.option
        )
        #expect(response == .typeIntoSearch(" "))
    }

    /// Auto-repeat with Option let go part-way through. Under the old flag-based check this was the
    /// case that leaked spaces into the query; now it resolves to the honest answer, because the
    /// keyboard really is sending bare spaces at that point.
    @Test("repeats after the modifier is released type spaces")
    func repeatsAfterModifierReleaseType() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                activeModifiers: Self.noModifiers,
                characters: " ",
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .typeIntoSearch(" ")
        )
    }

    /// The leak that survived the second fix. Hold ⌥Space, let Option go a fraction before Space,
    /// and every auto-repeat after that is indistinguishable from a deliberate space bar — so the
    /// search field filled with spaces after the text.
    ///
    /// A repeat of the shortcut's own key is that key still being held from the press that was
    /// already dealt with. There is no useful reading of it: as a chord it would toggle the overlay
    /// dozens of times a second, and as typing it inserts spaces nobody asked for.
    @Test("a repeat of the shortcut's key is ignored, modifiers or not", arguments: [
        CGEventFlags(rawValue: 0), CGEventFlags.maskAlternate,
    ])
    func shortcutKeyRepeatsAreIgnored(modifiers: CGEventFlags) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                activeModifiers: modifiers,
                characters: " ",
                isAutorepeat: true,
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .ignore
        )
    }

    /// Only the shortcut's key. Holding an ordinary letter down to repeat it is how keyboards work,
    /// and a search field that dropped those would be its own bug.
    @Test("an ordinary key still types when held")
    func ordinaryKeyRepeatsStillType() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.letterA,
                activeModifiers: Self.noModifiers,
                characters: "a",
                isAutorepeat: true,
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .typeIntoSearch("a")
        )
    }

    /// A fresh press of the same key is still a space. Suppressing repeats must not suppress the key.
    @Test("a fresh press of the shortcut's key still types")
    func freshPressStillTypes() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                activeModifiers: Self.noModifiers,
                characters: " ",
                isAutorepeat: false,
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .typeIntoSearch(" ")
        )
    }

    /// A chord that includes the shortcut's modifiers and more still means the shortcut. Holding an
    /// extra modifier is not a reason to start typing.
    @Test("extra modifiers on top of the shortcut still toggle")
    func supersetOfShortcutModifiersToggles() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                activeModifiers: [.maskAlternate, .maskShift],
                characters: " ",
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .triggerShortcut
        )
    }

    /// A partial chord is not the shortcut. With ⌃⌥Space registered, Control alone plus Space is not
    /// a toggle — and because Control is held it is not typing either.
    @Test("a partial chord neither dismisses nor types")
    func partialChordPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                activeModifiers: Self.control,
                characters: " ",
                shortcutKeyCode: Self.space,
                shortcutModifiers: [.maskControl, .maskAlternate]
            ) == .passThrough
        )
    }

    /// A shortcut that needs no modifiers, such as F13, still toggles on its own.
    @Test("a modifier-free shortcut toggles on its own key")
    func modifierFreeShortcutToggles() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Int64(kVK_F13),
                activeModifiers: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: Int64(kVK_F13),
                shortcutModifiers: []
            ) == .triggerShortcut
        )
    }

    /// A shortcut on a different key must not stop that key from being typed.
    @Test("only the shortcut's own key is treated specially")
    func otherKeysStillType() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.letterA,
                activeModifiers: Self.noModifiers,
                characters: "a",
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .typeIntoSearch("a")
        )
    }

    /// With no shortcut registered — registration can fail silently — a space is ordinary typing.
    @Test("space types normally when no shortcut is registered")
    func spaceTypesWithoutAShortcut() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.space,
                activeModifiers: Self.noModifiers,
                characters: " ",
                shortcutKeyCode: nil
            ) == .typeIntoSearch(" ")
        )
    }

    /// The shortcut's modifiers translated from Carbon must line up with what a live query returns,
    /// or the comparison above is meaningless. Checked against the real presets.
    @Test("each preset shortcut's modifiers survive the trip from Carbon")
    func presetModifiersTranslate() {
        #expect(HotKeyShortcut.optionSpace.eventFlags == [.maskAlternate])
        #expect(HotKeyShortcut.controlOptionSpace.eventFlags == [.maskControl, .maskAlternate])
        #expect(
            HotKeyShortcut.hyperSpace.eventFlags == [.maskControl, .maskAlternate, .maskCommand]
        )
        #expect(HotKeyShortcut.commandShiftBackslash.eventFlags == [.maskCommand, .maskShift])
        #expect(HotKeyShortcut.f13.eventFlags == [])
    }

    /// Every preset must actually toggle the overlay closed when pressed again. This is the property
    /// the original bug violated, checked across the whole list rather than for one combination.
    @Test("every preset shortcut closes the overlay", arguments: HotKeyShortcut.presets)
    func everyPresetToggles(shortcut: HotKeyShortcut) {
        let response = KeyResponse.forKeyDown(
            keyCode: Int64(shortcut.keyCode),
            activeModifiers: shortcut.eventFlags,
            characters: " ",
            shortcutKeyCode: Int64(shortcut.keyCode),
            shortcutModifiers: shortcut.eventFlags
        )
        #expect(response == .triggerShortcut, "\(shortcut.displayName) did not close the overlay")
    }

    // MARK: - Keys that mean something else

    @Test("escape dismisses whatever the shortcut is")
    func escapeDismisses() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.escapeKeyCode,
                activeModifiers: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: KeyResponse.escapeKeyCode
            ) == .dismiss
        )
    }

    @Test("return and the keypad's enter both confirm", arguments: [
        KeyResponse.returnKeyCode, KeyResponse.keypadEnterKeyCode,
    ])
    func returnConfirms(keyCode: Int64) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: keyCode,
                activeModifiers: Self.noModifiers,
                characters: "\r",
                shortcutKeyCode: nil
            ) == .confirm
        )
    }

    @Test("both delete keys shorten the query", arguments: [
        KeyResponse.deleteKeyCode, KeyResponse.forwardDeleteKeyCode,
    ])
    func deleteShortensTheQuery(keyCode: Int64) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: keyCode,
                activeModifiers: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: nil
            ) == .deleteSearchCharacter
        )
    }

    /// The reported bug, from both directions.
    ///
    /// Command with delete used to fall into the modifier-blind delete case and remove exactly one
    /// character, and Command-A used to reach the chord guard and be handed to the application
    /// underneath — so "select all, then delete" removed one character and silently select-all'd
    /// the user's document on the way.
    @Test("command with either delete key wipes the whole query", arguments: [
        KeyResponse.deleteKeyCode, KeyResponse.forwardDeleteKeyCode,
    ])
    func commandDeleteClearsTheQuery(keyCode: Int64) {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: keyCode,
                activeModifiers: Self.command,
                characters: nil,
                shortcutKeyCode: nil,
                isSearching: true
            ) == .clearSearchQuery
        )
        // And without Command it is still one character, searching or not.
        for searching in [true, false] {
            #expect(
                KeyResponse.forKeyDown(
                    keyCode: keyCode,
                    activeModifiers: Self.noModifiers,
                    characters: nil,
                    shortcutKeyCode: nil,
                    isSearching: searching
                ) == .deleteSearchCharacter
            )
        }
    }

    @Test("command-A selects the query, but only when there is one")
    func commandASelectsTheQuery() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.letterAKeyCode,
                activeModifiers: Self.command,
                characters: "a",
                shortcutKeyCode: nil,
                isSearching: true
            ) == .selectAllSearchQuery
        )

        // Nothing typed yet, so Command-A still belongs to whatever is behind the overlay.
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.letterAKeyCode,
                activeModifiers: Self.command,
                characters: "a",
                shortcutKeyCode: nil,
                isSearching: false
            ) == .passThrough
        )

        // A plain "a" is still typing, and Control- or Option-A are still someone else's chord.
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.letterAKeyCode,
                activeModifiers: Self.noModifiers,
                characters: "a",
                shortcutKeyCode: nil,
                isSearching: true
            ) == .typeIntoSearch("a")
        )
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.letterAKeyCode,
                activeModifiers: Self.option,
                characters: "å",
                shortcutKeyCode: nil,
                isSearching: true
            ) == .passThrough
        )
    }

    /// A user who has registered ⌘A as their trigger still gets their trigger.
    @Test("the shortcut outranks select-all when they are the same chord")
    func shortcutWinsOverSelectAll() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.letterAKeyCode,
                activeModifiers: Self.command,
                characters: "a",
                shortcutKeyCode: KeyResponse.letterAKeyCode,
                shortcutModifiers: Self.command,
                isSearching: true
            ) == .triggerShortcut
        )
    }

    // MARK: - Arrow keys

    /// All four arrows steer the overlay. They report a direction rather than a change of
    /// selection, because what "up" means depends on the arrangement on screen.
    @Test("each arrow key reports its own direction")
    func arrowsReportTheirDirection() {
        let expected: [(Int64, ArrowDirection)] = [
            (KeyResponse.leftArrowKeyCode, .left),
            (KeyResponse.rightArrowKeyCode, .right),
            (KeyResponse.upArrowKeyCode, .up),
            (KeyResponse.downArrowKeyCode, .down),
        ]

        for (keyCode, direction) in expected {
            #expect(
                KeyResponse.forKeyDown(
                    keyCode: keyCode,
                    activeModifiers: Self.noModifiers,
                    characters: nil,
                    shortcutKeyCode: nil
                ) == .moveSelection(direction)
            )
        }
    }

    /// An arrow must not also reach the window underneath. It is consumed, like a typed
    /// character — otherwise choosing a window would scroll the document behind it.
    @Test("arrows are never passed through")
    func arrowsAreConsumed() {
        for keyCode in [
            KeyResponse.leftArrowKeyCode,
            KeyResponse.rightArrowKeyCode,
            KeyResponse.upArrowKeyCode,
            KeyResponse.downArrowKeyCode,
        ] {
            let response = KeyResponse.forKeyDown(
                keyCode: keyCode,
                activeModifiers: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: nil
            )
            #expect(response != .passThrough, "key \(keyCode) reached the app underneath")
        }
    }

    /// Arrows keep working while a search is being typed, and they outrank the shortcut check:
    /// an arrow is never text, so there is nothing for the search field to gain from it.
    @Test("an arrow still steers when it is also the shortcut's key")
    func arrowWinsOverTheShortcutCheck() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: KeyResponse.downArrowKeyCode,
                activeModifiers: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: KeyResponse.downArrowKeyCode
            ) == .moveSelection(.down)
        )
    }

    // MARK: - Chords belong to the system

    /// ⌘Tab and friends have to keep working while the overlay is up.
    @Test("a command chord is left alone")
    func commandChordPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.tab,
                activeModifiers: Self.command,
                characters: "\t",
                shortcutKeyCode: nil
            ) == .passThrough
        )
    }

    @Test("an option chord is not typing")
    func optionChordPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: Self.letterA,
                activeModifiers: Self.option,
                characters: "å",
                shortcutKeyCode: Self.space,
                shortcutModifiers: Self.option
            ) == .passThrough
        )
    }

    /// A key that types nothing has nothing to contribute to a search.
    @Test("a key with no characters is left alone")
    func keyWithoutCharactersPassesThrough() {
        #expect(
            KeyResponse.forKeyDown(
                keyCode: 63,
                activeModifiers: Self.noModifiers,
                characters: nil,
                shortcutKeyCode: nil
            ) == .passThrough
        )
    }
}
