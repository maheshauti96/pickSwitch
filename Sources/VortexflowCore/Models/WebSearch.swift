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

    /// An assistant the query can be handed to as a prompt.
    ///
    /// ## Why these are results rather than a setting
    ///
    /// Typing a question into the switcher is already the gesture: the words are there, and where
    /// they should go is the only thing left to decide. Making that a preference would force the
    /// decision once, in advance, for every question — when in practice which assistant to ask is
    /// a per-question choice. As results they sit next to the web search, and picking one is the
    /// same keystroke as picking a window.
    ///
    /// ## Prefill, and what each of them does with it
    ///
    /// All three take the prompt in a `q` parameter, which is the convention across the assistants
    /// rather than anything specific to this app. They differ in what happens next, and the
    /// difference is theirs to make rather than ours to paper over: ChatGPT submits the prompt on
    /// load, whereas Claude fills its composer and waits for Return. Grok follows ChatGPT.
    ///
    /// Only the query the user typed is ever sent, and only when they pick one of these results.
    enum PromptProvider: String, CaseIterable, Equatable, Sendable {
        case chatGPT
        case claude
        case grok

        /// How the result names itself, which is also what the user reads before choosing.
        var displayName: String {
            switch self {
            case .chatGPT: return "ChatGPT"
            case .claude: return "Claude"
            case .grok: return "Grok"
            }
        }

        /// Everything before the encoded prompt.
        var template: String {
            switch self {
            case .chatGPT: return "https://chatgpt.com/?q="
            // `/new` rather than the root: without it an existing conversation is reopened and the
            // prefill lands in whatever thread was last used.
            case .claude: return "https://claude.ai/new?q="
            case .grok: return "https://grok.com/?q="
            }
        }

        /// The provider's own front page, used only to fetch its logo.
        ///
        /// Deliberately not the prompt URL. This value is handed to the favicon service, which
        /// makes a network request — so it must carry no part of what the user typed.
        var siteURL: String {
            switch self {
            case .chatGPT: return "https://chatgpt.com/"
            case .claude: return "https://claude.ai/"
            case .grok: return "https://grok.com/"
            }
        }
    }

    /// Where a query should take the user.
    enum Destination: Equatable {
        /// The query was an address; go straight there.
        case address(URL)
        /// The query was a search; ask a search engine.
        case search(URL)
        /// Skip the results page and open the first hit. Shift-Return is the same action.
        case firstResult(URL)
        /// The query is a prompt for an assistant.
        case prompt(PromptProvider, URL)

        var url: URL {
            switch self {
            case .address(let url), .search(let url), .firstResult(let url), .prompt(_, let url):
                return url
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

    /// Google's I'm Feeling Lucky: the same search, skipping the results page.
    ///
    /// `btnI=1` is the Lucky form button. A phrase the switcher could not match locally
    /// is often something the user already knows is on the web, and landing on the first
    /// hit is what Shift-Return is for.
    static let firstResultSearchTemplate = "https://www.google.com/search?btnI=1&q="

    /// Everywhere the query could reasonably take the user, best guess first.
    ///
    /// A phrase has one answer. An address has two, and offering only the first is a guess the
    /// switcher does not need to make: "grok.com" is almost certainly somewhere to go, but it is also
    /// a perfectly ordinary thing to want to search for, and the conservative address test cannot
    /// tell those apart. Since the results are a list the user picks from, both can be present and
    /// the ordering carries the guess instead of the filtering.
    ///
    /// Ordered address-first so that Return keeps doing what it did before this existed.
    static func destinations(for query: String) -> [Destination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var destinations: [Destination] = []
        let address = addressURL(for: trimmed)
        if let address {
            destinations.append(.address(address))
        }
        if let search = searchDestination(for: trimmed) {
            destinations.append(search)
            // Immediately after Search the web, so Down-then-Return reaches it and a
            // click can find it. Shift-Return is the same action, not a hidden extra.
            // Withheld for a typed address: "Go to grok.com" is already that first hit.
            if address == nil, let first = firstResultLuckyDestination(for: trimmed) {
                destinations.append(first)
            }
        }
        // After the search, never before it. Ordering here is what Return means, and Return has
        // meant "look this up" since before the assistants were offered — quietly promoting one of
        // them would change what an existing habit does.
        destinations.append(contentsOf: PromptProvider.allCases.compactMap { provider in
            promptDestination(for: trimmed, provider: provider)
        })
        return destinations
    }

    private static func promptDestination(
        for query: String,
        provider: PromptProvider
    ) -> Destination? {
        guard let encoded = encodedParameter(query),
              let url = URL(string: provider.template + encoded)
        else { return nil }
        return .prompt(provider, url)
    }

    /// The single best destination, which is the first of `destinations(for:)`.
    static func destination(for query: String) -> Destination? {
        destinations(for: query).first
    }

    /// Where Shift-Return should go: the query as an address, or the first search hit.
    ///
    /// An address is already the first result. A phrase uses I'm Feeling Lucky rather
    /// than the results page Return opens.
    static func firstResultDestination(for query: String) -> Destination? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let address = addressURL(for: trimmed) {
            return .address(address)
        }
        return firstResultLuckyDestination(for: trimmed)
    }

    /// Follow Google's Lucky redirect in-process and return the real page.
    ///
    /// Opening `google.com/url?q=…` in the browser is what draws the "Redirect Notice"
    /// interstitial. Taking the `q` ourselves and handing the destination to the browser
    /// is what skips it. If Lucky never leaves Google, fall back to the ordinary results
    /// page so Shift-Return still does something.
    static func resolvedFirstResult(for query: String) async -> Destination? {
        guard let planned = firstResultDestination(for: query) else { return nil }
        if case .address = planned { return planned }
        guard case .firstResult(let luckyURL) = planned else { return planned }
        if let page = await followLuckySearch(luckyURL) {
            return .address(page)
        }
        return searchDestination(for: query)
    }

    /// The page Google's `/url?q=` wrapper is sending the user to, or `nil` when the
    /// URL is still a Google results/consent page.
    ///
    /// The reported case: `https://www.google.com/url?q=https://ca.indeed.com/…`
    /// opened as a "Redirect Notice" instead of Indeed. The destination is already
    /// in `q` (or `url`); opening that directly is what avoids the notice.
    static func pageURL(skippingGoogleRedirect url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        let isGoogle = host == "google.com" || host.hasSuffix(".google.com")
        if isGoogle {
            guard url.path == "/url" || url.path.hasPrefix("/url") else { return nil }
            return encodedDestination(in: url)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private static let luckySession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static func followLuckySearch(_ luckyURL: URL) async -> URL? {
        var request = URLRequest(url: luckyURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        do {
            let (_, response) = try await luckySession.data(for: request)
            guard let final = response.url else { return nil }
            return pageURL(skippingGoogleRedirect: final)
        } catch {
            return nil
        }
    }

    private static func encodedDestination(in url: URL) -> URL? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = items.first(where: { $0.name == "q" || $0.name == "url" })?.value
        guard let value, let destination = URL(string: value) else { return nil }
        guard let scheme = destination.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return destination
    }

    private static func firstResultLuckyDestination(for query: String) -> Destination? {
        guard let encoded = encodedParameter(query),
              let url = URL(string: firstResultSearchTemplate + encoded)
        else { return nil }
        return .firstResult(url)
    }

    private static func searchDestination(for query: String) -> Destination? {
        guard let encoded = encodedParameter(query),
              let url = URL(string: searchTemplate + encoded)
        else { return nil }
        return .search(url)
    }

    /// The query, safe to sit after a `q=`.
    ///
    /// Shared by the search engine and every assistant, because the hazard is the same for all of
    /// them: `urlQueryAllowed` leaves `+`, `&`, `=`, `?` and `#` intact, and any of those in a
    /// prompt would silently truncate it or invent a second parameter.
    private static func encodedParameter(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
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
