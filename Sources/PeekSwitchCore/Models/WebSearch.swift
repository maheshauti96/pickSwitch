import Foundation

/// Turns a search query the switcher could not satisfy into somewhere to go.
///
/// ## Why this exists
///
/// Typing a name into the switcher and finding nothing used to be a dead end: a message saying
/// so, and Escape. But the intent behind the keystrokes is not "find me a window" so much as
/// "get me to this thing", and a window not existing yet is a weak reason to refuse. So the
/// no-matches state becomes an offer instead, and Return takes it.
///
/// ## Address or query
///
/// "grok.com" and "quarterly report" are both plausible things to type, and sending the first to
/// a search engine when the user plainly meant to go there would be a small daily annoyance. So a
/// query that looks like somewhere is treated as somewhere.
///
/// The test for that is deliberately conservative — an explicit scheme, or a single word with a
/// dot and a plausible suffix. Guessing wrong in this direction is the more annoying failure:
/// searching for something that was a domain merely costs a click, whereas navigating to
/// something that was a phrase can load a page the user never asked for.
enum WebSearch {

    /// Where a query should take the user.
    enum Destination: Equatable {
        /// The query was an address; go straight there.
        case address(URL)
        /// The query was a search; ask a search engine.
        case search(URL)

        var url: URL {
            switch self {
            case .address(let url), .search(let url): return url
            }
        }
    }

    /// Search engine used for queries that are not addresses.
    ///
    /// Fixed rather than read from the system, because macOS keeps the default search engine
    /// private to each browser and offers no API for it. The default *browser* is respected —
    /// the URL is handed to the system to open — so this only decides which engine answers, and
    /// only for text that was never going to resolve on its own.
    static let searchTemplate = "https://www.google.com/search?q="

    static func destination(for query: String) -> Destination? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let address = addressURL(for: trimmed) {
            return .address(address)
        }

        // `urlQueryAllowed` leaves "+" and "&" intact, which would corrupt the parameter, so
        // they are removed from the allowed set.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        guard
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: searchTemplate + encoded)
        else { return nil }
        return .search(url)
    }

    /// The query as an address, if it plainly is one.
    private static func addressURL(for query: String) -> URL? {
        // Anything with whitespace inside is a phrase, whatever else it contains.
        guard !query.contains(where: \.isWhitespace) else { return nil }

        let lowercased = query.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return URL(string: query)
        }

        // No scheme, so it has to look like a host: something.something, where the last part is
        // letters only and long enough to be a suffix. "3.5" and "v1.2" are not addresses.
        let host = lowercased.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lowercased
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard
            labels.count >= 2,
            let suffix = labels.last,
            suffix.count >= 2,
            suffix.allSatisfy(\.isLetter),
            labels.allSatisfy({ !$0.isEmpty })
        else { return nil }

        return URL(string: "https://" + query)
    }
}
