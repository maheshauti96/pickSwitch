import Foundation

/// What confirming the overlay should actually do.
///
/// ## Why this is a type
///
/// It was a chain of conditions inside `SwitcherController.commitSelection`, and it shipped a bug
/// that no test could have reached — the same reason `KeyResponse` exists. The chain put a
/// Return-only web fallback *in front of* the selected entry, so with a query that had matched
/// nothing locally, Return opened `WebSearch.destination(for:)` — the first offer — no matter which
/// offer the user had actually moved the selection to. Selecting "Prompt on ChatGPT" and pressing
/// Return opened a Google search.
///
/// It went unnoticed for as long as it did because the fallback was written when the offers were
/// not entries: back then a query that matched nothing left nothing selected at all, so "Return
/// means the web" and "Return means the selection" could not disagree. Once each offer became a
/// selectable result they could, and the older rule won.
///
/// It also explains why one provider appeared to work. The override only fires when nothing matched
/// locally, so typing "claude" with Claude installed matched the application, took the other branch,
/// and honoured the selection — while "chatgpt" and "grok", matching nothing, did not.
///
/// ## The rule
///
/// The selection decides, whatever confirmed it. The web fallback is what happens when there is no
/// selection to honour, which is the empty state it was written for.
enum ConfirmationTarget: Equatable {

    /// Raise or launch this entry.
    case activate(WindowEntry)
    /// Leave the machine for this destination.
    case open(WebSearch.Destination)
    /// Close without doing anything else.
    case dismiss

    /// - Parameters:
    ///   - isReturn: whether Return confirmed, rather than a click or the trigger coming up. Only
    ///     consulted for the fallback: mouse and trigger confirmation have never opened a browser
    ///     without something being selected, and should not start.
    ///   - selectedEntry: whatever is selected, which is what decides when there is one.
    ///   - canOfferWebSearch: whether every local source has settled without a match.
    ///   - query: what was typed, for the fallback destination.
    static func resolve(
        isReturn: Bool,
        selectedEntry: WindowEntry?,
        canOfferWebSearch: Bool,
        query: String
    ) -> ConfirmationTarget {
        // First, and unconditionally. A selected entry already knows where it goes — including the
        // web offers, each of which carries its own destination — so nothing above this may
        // substitute a different one.
        if let selectedEntry {
            if let webSearch = selectedEntry.webSearch {
                return .open(webSearch.destination)
            }
            return .activate(selectedEntry)
        }

        // Nothing selectable. Return still owns the web fallback here, which is the case it was
        // written for: a query that produced no result to select at all.
        if isReturn, canOfferWebSearch, let destination = WebSearch.destination(for: query) {
            return .open(destination)
        }

        return .dismiss
    }
}
