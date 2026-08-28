import Foundation

/// Where a trigger press came from.
///
/// The two are not interchangeable, and that is the whole reason this type exists. A mouse button
/// and a keyboard shortcut are both routed through one press/release path on purpose — a button a
/// mouse keeps inside its own firmware cannot reach an event tap at all, so the only way to use it
/// is to assign it to a shortcut, and it should then behave exactly like a button. But a *real*
/// keyboard shortcut carries an expectation that a button does not: the combination that opened
/// something closes it again. Every switcher and spotlight on the system works that way.
enum TriggerSource: Equatable, Sendable {
    case button
    case keyboardShortcut
}

/// What a trigger press should do, given where it came from and what is already on screen.
///
/// Split out as a value rather than left inline in the controller because it is where the two
/// trigger kinds legitimately diverge, and because the interesting cases are combinations of
/// visibility and presentation mode — cheap to enumerate in a test, awkward to reach through an
/// event tap and a live panel.
enum TriggerResponse: Equatable, Sendable {

    /// Nothing is up: present the overlay.
    case open
    /// Switch to whatever is selected, and close.
    case commitSelection
    /// Close, leaving focus exactly where it was.
    case dismissWithoutSwitching
    /// The press means nothing here.
    case ignore

    /// Resolve a press.
    ///
    /// - Parameters:
    ///   - source: which trigger was pressed.
    ///   - overlayVisible: whether the overlay is already on screen.
    ///   - mode: how the visible presentation was started. `.hold` means the trigger is still
    ///     physically down, so a second press cannot be a deliberate second gesture.
    static func forPress(
        from source: TriggerSource,
        overlayVisible: Bool,
        mode: PresentationMode
    ) -> TriggerResponse {
        guard overlayVisible else { return .open }

        switch source {
        case .keyboardShortcut:
            // Requirement 6.2: the combination that opened the overlay closes it, and
            // does not switch. This used to be `.ignore` while presentation mode was
            // `.hold`, on the theory that Carbon auto-repeats. It does not — and a
            // mouse-mapped shortcut often never sends a hotkey *release*, so the
            // overlay stayed in hold forever and every later press was swallowed.
            return .dismissWithoutSwitching
        case .button:
            switch mode {
            case .hold:
                // Still held. Releasing decides what happens; a press arriving in
                // between is noise.
                return .ignore
            case .toggle:
                // `ActivationMode.toggle` promises "press again, or click a window, to
                // switch", and it is what makes the switcher fully mouse-driven — tap
                // to open, scroll to choose, tap to switch, with no need to click
                // precisely on a card.
                return .commitSelection
            }
        }
    }
}
