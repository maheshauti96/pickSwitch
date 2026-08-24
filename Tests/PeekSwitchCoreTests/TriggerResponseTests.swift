import Testing
@testable import PeekSwitchCore

/// What a second trigger press does, which is where the mouse button and the keyboard shortcut
/// legitimately disagree.
///
/// This suite exists because of a defect that a passing build could not have caught. Requirement
/// 6.2 — press the shortcut again to close the overlay — was specified, implemented, and
/// unreachable: the branch that dismissed lived behind a presentation mode nothing ever started,
/// while the shortcut was routed into the button's path, where a second press commits. Pressing the
/// shortcut again therefore switched windows instead of closing, and the code that promised
/// otherwise sat in the file looking correct.
@Suite("Trigger response")
struct TriggerResponseTests {

    // MARK: - Opening

    @Test("Either trigger opens the overlay when nothing is up", arguments: [
        TriggerSource.button, TriggerSource.keyboardShortcut,
    ])
    func pressOpensWhenHidden(source: TriggerSource) {
        // The mode is whatever the last presentation left behind, and must not matter here.
        for mode in [PresentationMode.hold, .toggle] {
            #expect(
                TriggerResponse.forPress(from: source, overlayVisible: false, mode: mode) == .open
            )
        }
    }

    // MARK: - The defect

    /// The behaviour asked for: the shortcut that opened the overlay closes it, and leaves focus
    /// alone.
    @Test("The shortcut pressed again closes without switching")
    func shortcutTogglesClosed() {
        #expect(
            TriggerResponse.forPress(
                from: .keyboardShortcut,
                overlayVisible: true,
                mode: .toggle
            ) == .dismissWithoutSwitching
        )
    }

    /// The regression that would reintroduce the bug: a shortcut press resolving to a commit.
    @Test("The shortcut never switches windows on a second press")
    func shortcutNeverCommits() {
        for mode in [PresentationMode.hold, .toggle] {
            #expect(
                TriggerResponse.forPress(
                    from: .keyboardShortcut,
                    overlayVisible: true,
                    mode: mode
                ) != .commitSelection
            )
        }
    }

    // MARK: - The mouse button is unchanged

    /// `ActivationMode.toggle` promises "press again, or click a window, to switch", and it is what
    /// makes the switcher usable without ever clicking precisely on a card.
    @Test("A second button press still commits the selection")
    func buttonStillCommits() {
        #expect(
            TriggerResponse.forPress(
                from: .button,
                overlayVisible: true,
                mode: .toggle
            ) == .commitSelection
        )
    }

    // MARK: - While held

    /// In hold mode the trigger is still physically down, so anything arriving before the release
    /// is noise rather than a second gesture — including a hotkey that auto-repeats.
    @Test("A press while the trigger is held is ignored", arguments: [
        TriggerSource.button, TriggerSource.keyboardShortcut,
    ])
    func pressWhileHeldIsIgnored(source: TriggerSource) {
        #expect(
            TriggerResponse.forPress(from: source, overlayVisible: true, mode: .hold) == .ignore
        )
    }

    // MARK: - Totality

    /// Every combination resolves to something, and only a visible overlay can be closed or
    /// committed. A press with nothing on screen must always open.
    @Test("Every combination is decided")
    func everyCombinationIsDecided() {
        for source in [TriggerSource.button, .keyboardShortcut] {
            for mode in [PresentationMode.hold, .toggle] {
                for visible in [true, false] {
                    let response = TriggerResponse.forPress(
                        from: source,
                        overlayVisible: visible,
                        mode: mode
                    )
                    if visible {
                        #expect(response != .open, "\(source) \(mode) reopened a visible overlay")
                    } else {
                        #expect(response == .open, "\(source) \(mode) did not open")
                    }
                }
            }
        }
    }
}
