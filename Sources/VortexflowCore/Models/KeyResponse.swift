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
    /// Shift-Return: skip the results page and open the first web hit for the query.
    case openFirstWebResult
    case deleteSearchCharacter
    /// Wipe the whole query in one go: Command with either delete key.
    ///
    /// The delete case above used to be modifier-blind, which is how the reported bug came about.
    /// A user reaching for the two ways macOS has always meant "get rid of all of this" — Command
    /// with delete, or select-all then delete — got a one-character backspace from the first and
    /// nothing at all from the second, since Command chords were passed straight through to the
    /// application underneath. The overlay has no text field and no responder chain, so neither
    /// gesture arrives with any meaning attached; both have to be spelled out here.
    case clearSearchQuery
    /// Command-A with a query active: select all of it, so the next delete or keystroke replaces
    /// the lot.
    ///
    /// There is no caret and no selection range to act on — the query is one string — so this is
    /// select-all in the only sense that is meaningful here: a flag saying the whole query is
    /// spoken for, which the next edit consumes. That is enough to make the two gestures users
    /// actually reach for behave the way they do in every other text field.
    case selectAllSearchQuery
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
    static let letterAKeyCode: Int64 = 0
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
    ///   - isSearching: whether a query is currently active. Command-A must keep meaning
    ///     select-all *in the application underneath* when nothing is typed. The same flag
    ///     is what lets a remapped mouse button close the overlay: Logitech injects the
    ///     shortcut as a bare Space with no Option flag, which is indistinguishable from
    ///     typing — except that with an empty query there is nothing to type into, so the
    ///     Space is the shortcut. Once a query exists, a bare Space is a space.
    ///   - shortcutModifiersRecentlyHeld: whether a modifier the shortcut requires was seen as
    ///     its own key-down a moment ago. Mouse software that injects ⌥Space as Option-down
    ///     then Space-down often leaves Space with no Option flag, and a live flags query
    ///     misses it too if Option was already released. The recent key-down is the chord.
    static func forKeyDown(
        keyCode: Int64,
        activeModifiers: CGEventFlags,
        characters: String?,
        isAutorepeat: Bool = false,
        shortcutKeyCode: Int64?,
        shortcutModifiers: CGEventFlags = [],
        isSearching: Bool = false,
        shortcutModifiersRecentlyHeld: Bool = false
    ) -> KeyResponse {
        switch keyCode {
        case escapeKeyCode:
            return .dismiss
        case returnKeyCode, keypadEnterKeyCode:
            // Shift-Return is "open the first web result", not confirm. Command/Control
            // stay out of it so those chords keep reaching the application underneath.
            if activeModifiers.contains(.maskShift),
               !activeModifiers.contains(.maskCommand),
               !activeModifiers.contains(.maskControl) {
                return .openFirstWebResult
            }
            return .confirm
        case deleteKeyCode, forwardDeleteKeyCode:
            // Command with delete means "all of it" wherever else macOS accepts text, and this is
            // the only place the distinction can be drawn: by the time the delete reaches the
            // state it is one character or the whole string, and nothing downstream still knows
            // which modifiers were held.
            return activeModifiers.contains(.maskCommand)
                ? .clearSearchQuery
                : .deleteSearchCharacter
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

            if activeModifiers.isSuperset(of: shortcutModifiers)
                || (!shortcutModifiers.isEmpty && shortcutModifiersRecentlyHeld)
                || !isSearching {
                // Empty query: the shortcut's own key closes, even without its
                // modifiers. Mouse software often injects ⌥Space as a naked Space
                // — no Option on the event, none in the live flags, and no Option
                // key-down to arm from. Treating that Space as typing is what
                // filled the search field. A leading space is not a useful search,
                // so the close wins until the user has actually typed something.
                return .triggerShortcut
            }
        }

        // Command-A, and only while there is something to select. Placed after the shortcut check
        // so a user who has registered ⌘A as their trigger still gets their trigger, and before
        // the chord guard below, which would otherwise hand it to the application underneath —
        // which is exactly what it was doing: the reported symptom was Command-A appearing to do
        // nothing, and it was in fact selecting all of the user's document behind the overlay.
        if keyCode == letterAKeyCode,
           isSearching,
           activeModifiers.contains(.maskCommand),
           !activeModifiers.contains(.maskControl),
           !activeModifiers.contains(.maskAlternate) {
            return .selectAllSearchQuery
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

    /// The registered shortcut, pressed while the overlay is hidden.
    ///
    /// Carbon is silent during another application's menu tracking. The HID tap is the
    /// fallback, and it must not use `forKeyDown` — that path is written for an overlay
    /// that is already up, and would consume Escape, Return, arrows and typing
    /// system-wide. This only matches the actual chord (or a modifier that was just
    /// seen, for mouse software that injects the key bare).
    static func matchesGlobalShortcut(
        keyCode: Int64,
        activeModifiers: CGEventFlags,
        shortcutKeyCode: Int64?,
        shortcutModifiers: CGEventFlags,
        shortcutModifiersRecentlyHeld: Bool
    ) -> Bool {
        guard let shortcutKeyCode, keyCode == shortcutKeyCode else { return false }
        if shortcutModifiers.isEmpty { return true }
        if activeModifiers.isSuperset(of: shortcutModifiers) { return true }
        return shortcutModifiersRecentlyHeld
    }
}
