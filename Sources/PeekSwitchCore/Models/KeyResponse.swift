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
/// So the decision is made from the key code, which is always present, and it lives here where
/// every branch can be enumerated in a test.
enum KeyResponse: Equatable, Sendable {

    case dismiss
    case confirm
    case deleteSearchCharacter
    case typeIntoSearch(String)
    /// Leave the event alone and let it continue down the pipeline.
    case passThrough

    // Virtual key codes, which are layout-independent.
    static let escapeKeyCode: Int64 = 53
    static let returnKeyCode: Int64 = 36
    static let keypadEnterKeyCode: Int64 = 76
    static let deleteKeyCode: Int64 = 51
    static let forwardDeleteKeyCode: Int64 = 117

    /// Resolve one `keyDown`.
    ///
    /// - Parameters:
    ///   - keyCode: the virtual key code.
    ///   - flags: the event's modifier flags. Treated as a hint only, for the reason above.
    ///   - characters: what the key would type on the active layout, or `nil` for keys that type
    ///     nothing.
    ///   - shortcutKeyCode: the key code of the registered global shortcut, when there is one.
    static func forKeyDown(
        keyCode: Int64,
        flags: CGEventFlags,
        characters: String?,
        shortcutKeyCode: Int64?
    ) -> KeyResponse {
        switch keyCode {
        case escapeKeyCode:
            return .dismiss
        case returnKeyCode, keypadEnterKeyCode:
            return .confirm
        case deleteKeyCode, forwardDeleteKeyCode:
            return .deleteSearchCharacter
        default:
            break
        }

        // The shortcut's own key is never typing while the overlay is up, whatever the flags say.
        // Passing it through is what lets the hotkey receive it and close the overlay.
        //
        // The cost is deliberate and small: with ⌥Space as the shortcut, a literal space cannot be
        // typed into the search filter. Search matches within titles and application names, so a
        // space is rarely the character that finds a window — and a shortcut that cannot close the
        // thing it opened is a far worse trade.
        if let shortcutKeyCode, keyCode == shortcutKeyCode {
            return .passThrough
        }

        // A command or control chord is a shortcut, not typing — passing those through is what
        // keeps ⌘Tab and the like working while the overlay is up. Option is included because a
        // chord is not text, even though it cannot be relied on to *appear* here.
        guard !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate)
        else { return .passThrough }

        guard let characters, WindowSearch.isSearchable(characters) else { return .passThrough }
        return .typeIntoSearch(characters)
    }
}
