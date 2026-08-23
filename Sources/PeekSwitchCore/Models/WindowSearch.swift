import Foundation

/// Filtering the window list by a typed query.
///
/// Pure and total, so the ranking can be tested without a running desktop.
///
/// ## Why substring rather than fuzzy matching
///
/// The list being searched is small — at most a couple of dozen windows — and the user
/// is typing to narrow something they can already see. Fuzzy matching earns its
/// complexity when the corpus is large and the target is remembered rather than visible;
/// here it mostly produces surprising matches. A plain case- and diacritic-insensitive
/// substring test is predictable, and predictability is what lets someone type two
/// letters and commit without looking.
enum WindowSearch {

    /// How well one window matches, higher being better. `nil` means no match.
    ///
    /// The ranking exists so that typing "saf" puts Safari's windows above a Notes window
    /// that happens to mention Safari in its title.
    static func score(_ entry: WindowEntry, query: String) -> Int? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return 0 }

        let application = normalize(entry.applicationName)
        let title = normalize(entry.displayTitle)

        // A tab's address is often the most memorable thing about it — "grok" is the site,
        // not the page title — so the host is matched as strongly as an application name.
        if let tab = entry.tab {
            let host = normalize(tab.host)
            if host.hasPrefix(needle) { return 4 }
            if host.contains(needle) { return 2 }
        }

        if application.hasPrefix(needle) { return 4 }
        if title.hasPrefix(needle) { return 3 }
        if application.contains(needle) { return 2 }
        if title.contains(needle) { return 1 }

        // Last resort: the words of the title, so "env" finds ".env.local" and "board"
        // finds "Scrum Board".
        if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains(where: { $0.hasPrefix(needle) }) {
            return 1
        }
        return nil
    }

    /// Windows matching `query`, best first.
    ///
    /// Ties keep their incoming order, which is most-recently-used, so the ranking never
    /// reshuffles equally good matches into an order the user has no model for.
    static func filter(_ entries: [WindowEntry], query: String) -> [WindowEntry] {
        guard !normalize(query).isEmpty else { return entries }

        return entries.enumerated()
            .compactMap { position, entry -> (entry: WindowEntry, score: Int, position: Int)? in
                guard let score = score(entry, query: query) else { return nil }
                return (entry, score, position)
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.position < rhs.position : lhs.score > rhs.score
            }
            .map(\.entry)
    }

    /// Whether a typed character should extend the query.
    ///
    /// Deliberately narrow. Anything that is not a plain printable character is left for
    /// the overlay's own keys — Escape, Return — or passed through untouched, so a
    /// keyboard shortcut arriving while the overlay happens to be up is not silently
    /// eaten by the search field.
    static func isSearchable(_ characters: String) -> Bool {
        guard !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            // Printable, and not a control or private-use character. Space counts: window
            // titles have spaces in them.
            scalar.value >= 32 && scalar.value != 127 && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    /// Case- and diacritic-insensitive, so "cafe" matches "Café".
    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
