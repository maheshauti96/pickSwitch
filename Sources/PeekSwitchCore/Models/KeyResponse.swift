import CoreGraphics
import Foundation

/// What a key press should do while the overlay is on screen.
///
/// ## Why this is a value and not just code in the tap callback
///
/// The overlay's event tap is a C callback, which is the least testable place in the app and was
/// carrying a real defect: with the shortcut set to ⌥Space, pressing it again typed a space into
/// the search field instead of closing the overlay. The tap consumed the keystroke, so the Carbon
/// hotkey behind it never fired at all — the toggle looked broken when in fact the keystroke never
/// reached it.
///
/// The guard that should have prevented it tested the event's modifier flags, and those cannot be
/// relied on here. The tap is installed at `.cghidEventTap`, ahead of session-level taps, and a key
/// event arriving that early does not reliably carry the modifier state the window server later
/// attaches to it. Auto-repeat makes it worse: hold ⌥Space, release Option a fraction before Space,
/// and the repeats that follow genuinely have no Option flag at all.
///
/// The first fix for that passed the shortcut's key code straight through whenever it appeared, on
/// the grounds that the key could not be trusted to be typing. It closed the overlay, and it cost
/// more than expected: under ⌥Space a literal space could no longer be typed into the search filter
/// at all. That was a bad trade. A search field that silently refuses one of the most common
/// characters is not a small compromise, and it was reported as a bug within a day.
///
/// So the modifier state is consulted after all — just not the copy attached to the event. The
/// caller queries the *live* keyboard state, which is a hardware question rather than event
/// metadata, and is therefore not subject to whatever the window server had attached by the time
/// this tap saw the key. With that available the two cases separate cleanly:
///
/// - The shortcut's key with the shortcut's modifiers actually held: the user is toggling. Answered
///   with `dismiss` and consumed here, rather than passed through in the hope that the Carbon hotkey
///   picks it up — this layer already knows what it means, and consuming it is what guarantees no
///   space is typed.
/// - The same key with those modifiers released: the user is typing. A space is a space.
///
/// The auto-repeat case that defeated the flags now resolves correctly for the same reason: if
/// Option has genuinely been let go, the repeats that follow really are bare spaces, and typing them
/// is the honest reading of what the keyboard is doing.
enum ArrowDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down
}
enum KeyResponse: Equatable, Sendable {

    case dismiss
    /// Consume the key and do nothing with it.
    ///
    /// Exists for one case: the shortcut's own key auto-repeating. Holding ⌥Space long enough to
    /// repeat produces a stream of key-downs after the chord has already been acted on, and there is
    /// no reading of those that is useful. Treating them as the chord again would toggle the overlay
    /// dozens of times a second; treating them as typing puts a run of spaces in the search field,
    /// which is what "there is an extra space after my text" turned out to be. Passing them on would
    /// hand the same repeats to the hotkey. So they stop here.
    case ignore
    /// The registered shortcut, pressed while its own overlay is up.
    ///
    /// Deliberately not `dismiss`. Escape backs out of an active search before it closes anything,
    /// which is right for Escape and wrong for the shortcut: the combination that opened the overlay
    /// closes it, and having it eat a query instead would be a different bug wearing the same
    /// clothes. This routes to the same press handling the global hotkey uses, so the tap and the
    /// hotkey cannot drift apart.
    case triggerShortcut
    case confirm
    case deleteSearchCharacter
    case typeIntoSearch(String)
    /// An arrow key, reported as the direction pressed rather than as a change of selection.
    ///
    /// What "up" means depends on the arrangement — a row in a grid, the previous card in a
    /// list, one step back around a ring — and this layer has no business knowing which is on
    /// screen. It says which key was pressed; `OverlayLayout` decides what that moves.
    case moveSelection(ArrowDirection)
    /// Leave the event alone and let it continue down the pipeline.
    case passThrough

    // Virtual key codes, which are layout-independent.
    static let escapeKeyCode: Int64 = 53
    static let returnKeyCode: Int64 = 36
    static let keypadEnterKeyCode: Int64 = 76
    static let deleteKeyCode: Int64 = 51
    static let forwardDeleteKeyCode: Int64 = 117
    static let leftArrowKeyCode: Int64 = 123
    static let rightArrowKeyCode: Int64 = 124
    static let downArrowKeyCode: Int64 = 125
    static let upArrowKeyCode: Int64 = 126

    /// Resolve one `keyDown`.
    ///
    /// - Parameters:
    ///   - keyCode: the virtual key code.
    ///   - activeModifiers: the modifiers physically held at this moment, queried from the keyboard
    ///     rather than read off the event. See the note above for why the event's own flags are not
    ///     usable at this tap location.
    ///   - characters: what the key would type on the active layout, or `nil` for keys that type
    ///     nothing.
    ///   - isAutorepeat: whether this key-down came from the key being held rather than newly
    ///     pressed. Only consulted for the shortcut's own key; holding an ordinary letter to repeat
    ///     it is normal typing and stays that way.
    ///   - shortcutKeyCode: the key code of the registered global shortcut, when there is one.
    ///   - shortcutModifiers: the modifiers that shortcut requires. Empty for a shortcut that needs
    ///     none, such as F13.
    static func forKeyDown(
        keyCode: Int64,
        activeModifiers: CGEventFlags,
        characters: String?,
        isAutorepeat: Bool = false,
        shortcutKeyCode: Int64?,
        shortcutModifiers: CGEventFlags = []
    ) -> KeyResponse {
        switch keyCode {
        case escapeKeyCode:
            return .dismiss
        case returnKeyCode, keypadEnterKeyCode:
            return .confirm
        case deleteKeyCode, forwardDeleteKeyCode:
            return .deleteSearchCharacter
        case leftArrowKeyCode:
            return .moveSelection(.left)
        case rightArrowKeyCode:
            return .moveSelection(.right)
        case upArrowKeyCode:
            return .moveSelection(.up)
        case downArrowKeyCode:
            return .moveSelection(.down)
        default:
            break
        }

        // The shortcut pressed in full, while its own overlay is up, means close it. Handled here
        // and consumed, rather than passed through for the Carbon hotkey to notice: this layer
        // already knows what the combination means, and consuming it is what guarantees the key
        // cannot also be typed.
        if let shortcutKeyCode, keyCode == shortcutKeyCode {
            // A repeat of the shortcut's own key is the key still being held from the press that was
            // already dealt with, whatever the modifiers now say. This is the case that leaked
            // spaces: hold ⌥Space, let Option go a moment before Space, and every repeat after that
            // looks exactly like a deliberate space bar.
            if isAutorepeat { return .ignore }

            if activeModifiers.isSuperset(of: shortcutModifiers) {
                return .triggerShortcut
            }
        }

        // A command or control chord is a shortcut, not typing — passing those through is what
        // keeps ⌘Tab and the like working while the overlay is up. Option is included because a
        // chord is not text. Read from the live state, so a chord cannot slip through as text just
        // because the event arrived here without its flags attached.
        guard !activeModifiers.contains(.maskCommand),
              !activeModifiers.contains(.maskControl),
              !activeModifiers.contains(.maskAlternate)
        else { return .passThrough }

        guard let characters, WindowSearch.isSearchable(characters) else { return .passThrough }
        return .typeIntoSearch(characters)
    }
}
