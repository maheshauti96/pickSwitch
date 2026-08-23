import Carbon.HIToolbox
import Testing
@testable import PeekSwitchCore

/// The shortcut became configurable because a fixed ⌃⌥Space silently never fired on a
/// real machine — another app owned it, and `RegisterEventHotKey` reports success
/// regardless. These tests cover the packing used to persist the choice.
@Suite("Hot key shortcut")
struct HotKeyShortcutTests {

    @Test("Every preset survives a storage round-trip")
    func presetsRoundTrip() {
        for shortcut in HotKeyShortcut.presets {
            let restored = HotKeyShortcut.from(storageValue: shortcut.storageValue)
            #expect(restored == shortcut, "\(shortcut.displayName) did not round-trip")
        }
    }

    @Test("Presets are distinct in both key combination and label")
    func presetsAreDistinct() {
        let ids = Set(HotKeyShortcut.presets.map(\.id))
        #expect(ids.count == HotKeyShortcut.presets.count)

        let labels = Set(HotKeyShortcut.presets.map(\.displayName))
        #expect(labels.count == HotKeyShortcut.presets.count)

        let storage = Set(HotKeyShortcut.presets.map(\.storageValue))
        #expect(storage.count == HotKeyShortcut.presets.count)
    }

    @Test("An unrecognised storage value yields nothing rather than a bogus shortcut")
    func unknownStorageValueRejected() {
        #expect(HotKeyShortcut.from(storageValue: 0) == nil)
        #expect(HotKeyShortcut.from(storageValue: 0x7FFF_FFFF) == nil)
    }

    @Test("The default is one of the presets")
    func defaultIsAPreset() {
        #expect(HotKeyShortcut.presets.contains(HotKeyShortcut.default))
    }

    /// F13 has no stock binding on any Mac keyboard, which makes it the reliable
    /// escape hatch when everything else is contended — and a natural target for
    /// remapping a spare mouse button onto.
    /// Every preset except F13 must be typeable on a laptop keyboard.
    ///
    /// F13 was once recommended as the way to bind a remapped mouse button, which was
    /// wrong: no laptop or compact keyboard has it, and remapping software asks you to
    /// press the shortcut to record it — so it could not be assigned either. It stays in
    /// the list for extended keyboards, and carries a caveat.
    @Test("Only F13 needs a keyboard most people do not have")
    func onlyF13NeedsAnExtendedKeyboard() {
        for shortcut in HotKeyShortcut.presets where shortcut != .f13 {
            #expect(shortcut.caveat == nil, "\(shortcut.displayName) should be typeable anywhere")
            #expect(shortcut.keyCode != UInt32(kVK_F13))
        }
        #expect(HotKeyShortcut.f13.caveat != nil)
    }

    /// A three-modifier chord is the escape hatch when another app is silently holding a
    /// simpler combination, so one has to be offered.
    @Test("A shortcut nothing else is likely to claim is offered")
    func aHighModifierShortcutIsOffered() {
        #expect(HotKeyShortcut.presets.contains(.hyperSpace))

        let modifiers = HotKeyShortcut.hyperSpace.carbonModifiers
        #expect(modifiers & UInt32(controlKey) != 0)
        #expect(modifiers & UInt32(optionKey) != 0)
        #expect(modifiers & UInt32(cmdKey) != 0)
        #expect(HotKeyShortcut.hyperSpace.storageValue != HotKeyShortcut.f13.storageValue)
        // Must survive persistence like every other preset.
        #expect(HotKeyShortcut.from(storageValue: HotKeyShortcut.hyperSpace.storageValue) == .hyperSpace)
    }

    @Test("A modifier-free fallback is offered")
    func modifierFreeFallbackExists() {
        #expect(HotKeyShortcut.f13.carbonModifiers == 0)
        #expect(HotKeyShortcut.presets.contains(HotKeyShortcut.f13))
    }

    /// Packing puts modifiers in the high half and the key code in the low half;
    /// neither may bleed into the other.
    @Test("Packing keeps the key code and modifiers separate")
    func packingKeepsFieldsSeparate() {
        for shortcut in HotKeyShortcut.presets {
            let packed = shortcut.storageValue
            #expect(UInt32(packed & 0xFFFF) == shortcut.keyCode)
            #expect(UInt32((packed >> 16) & 0xFFFF) == shortcut.carbonModifiers)
        }
    }
}

// MARK: - Recorded shortcuts

/// Press-to-record, which is what makes a shortcut usable when every preset is already
/// claimed by another application.
extension HotKeyShortcutTests {

    /// The bug this guards: `from(storageValue:)` used to match presets only, so a recorded
    /// shortcut would come back `nil` and be silently replaced by the default on next launch.
    @Test("A recorded shortcut survives a restart")
    func recordedShortcutSurvivesRestart() {
        guard let recorded = HotKeyShortcut.recorded(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey)
        ) else {
            Issue.record("⌃⌥K should be recordable")
            return
        }

        #expect(!HotKeyShortcut.presets.contains(recorded))
        #expect(HotKeyShortcut.from(storageValue: recorded.storageValue) == recorded)
    }

    /// A global shortcut fires whatever the user is doing, so a bare letter would open the
    /// switcher mid-sentence.
    @Test("A shortcut needs Control, Option or Command")
    func shortcutNeedsAMeaningfulModifier() {
        #expect(HotKeyShortcut.recorded(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: 0) == nil)
        // Shift alone is not enough: ⇧K is just a capital K.
        #expect(HotKeyShortcut.recorded(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(shiftKey)
        ) == nil)

        for modifier in [controlKey, optionKey, cmdKey] {
            #expect(HotKeyShortcut.recorded(
                keyCode: UInt32(kVK_ANSI_K),
                carbonModifiers: UInt32(modifier)
            ) != nil)
        }
    }

    /// Function keys type nothing on their own, which is exactly why they work bare.
    @Test("A function key needs no modifier")
    func functionKeyNeedsNoModifier() {
        #expect(HotKeyShortcut.recorded(keyCode: UInt32(kVK_F13), carbonModifiers: 0) != nil)
        #expect(HotKeyShortcut.recorded(keyCode: UInt32(kVK_F5), carbonModifiers: 0) != nil)
    }

    @Test("A refused combination explains itself")
    func refusedCombinationExplainsItself() {
        let reason = HotKeyShortcut.rejectionReason(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: 0)
        #expect(reason != nil)
        #expect(reason?.isEmpty == false)
        // Nothing to explain when the combination is fine.
        #expect(HotKeyShortcut.rejectionReason(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey)
        ) == nil)
    }

    /// Reconstructing arbitrary values from storage must not invent keys that do not exist.
    @Test("Implausible stored values are still refused")
    func implausibleStoredValuesAreRefused() {
        // Virtual key codes are 7-bit.
        #expect(HotKeyShortcut.recorded(keyCode: 9999, carbonModifiers: UInt32(cmdKey)) == nil)
        // Modifier masks have five meaningful bits; stray ones mean corrupted storage.
        #expect(HotKeyShortcut.recorded(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: 0x7FFF) == nil)
        #expect(HotKeyShortcut.from(storageValue: -1) == nil)
    }

    // MARK: - Labelling

    @Test("Modifiers are shown in the order macOS uses")
    func modifiersUseSystemOrder() {
        let all = KeyNaming.description(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(all == "⌃⌥⇧⌘Space")
    }

    @Test("Named keys read as words, not control characters")
    func namedKeysReadAsWords() {
        #expect(KeyNaming.keyLabel(for: UInt32(kVK_Space)) == "Space")
        #expect(KeyNaming.keyLabel(for: UInt32(kVK_Return)) == "Return")
        #expect(KeyNaming.keyLabel(for: UInt32(kVK_Tab)) == "Tab")
        #expect(KeyNaming.keyLabel(for: UInt32(kVK_Escape)) == "Escape")
        #expect(KeyNaming.keyLabel(for: UInt32(kVK_LeftArrow)) == "←")
        #expect(KeyNaming.keyLabel(for: UInt32(kVK_F13)) == "F13")
    }

    /// Letters come from the active keyboard layout, so the label matches the user's own
    /// keyboard rather than assuming a US one.
    @Test("Letter keys are labelled from the keyboard layout")
    func letterKeysComeFromTheLayout() {
        let label = KeyNaming.keyLabel(for: UInt32(kVK_ANSI_K))
        #expect(!label.isEmpty)
        #expect(label == label.uppercased())
        // Never a raw fallback for a key that plainly exists.
        #expect(!label.hasPrefix("Key "))
    }

    @Test("A recorded shortcut labels itself")
    func recordedShortcutLabelsItself() {
        let shortcut = HotKeyShortcut.recorded(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey | cmdKey)
        )
        #expect(shortcut?.displayName == "⌃⌘Space")
    }

    /// Presets keep their hand-written labels rather than being relabelled by the recorder.
    @Test("Presets keep their own labels when loaded")
    func presetsKeepTheirLabels() {
        for preset in HotKeyShortcut.presets {
            #expect(HotKeyShortcut.from(storageValue: preset.storageValue)?.displayName == preset.displayName)
        }
    }
}
