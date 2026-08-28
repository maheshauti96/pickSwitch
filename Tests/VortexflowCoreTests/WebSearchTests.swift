import Foundation
import Testing
@testable import VortexflowCore

/// Turning a search that matched nothing into somewhere to go.
///
/// The whole risk here is misreading intent. Sending "grok.com" to a search engine is a small
/// daily annoyance; navigating to "quarterly report" as if it were a host is worse, because it
/// loads a page nobody asked for. So the tests are mostly about which side of that line a given
/// string falls on.
@Suite("Web search fallback")
struct WebSearchTests {

    private func destination(_ query: String) -> WebSearch.Destination? {
        WebSearch.destination(for: query)
    }

    @Test("A phrase becomes a search")
    func phrasesBecomeSearches() {
        guard case .search(let url)? = destination("quarterly report") else {
            Issue.record("expected a search")
            return
        }
        #expect(url.absoluteString.hasPrefix(WebSearch.searchTemplate))
        #expect(url.absoluteString.contains("quarterly%20report"))
    }

    @Test("A bare domain becomes an address")
    func domainsBecomeAddresses() {
        for query in ["grok.com", "news.ycombinator.com", "example.co.uk", "GROK.COM"] {
            guard case .address(let url)? = destination(query) else {
                Issue.record("\(query) should be an address")
                continue
            }
            #expect(url.scheme == "https")
        }
    }

    @Test("An explicit scheme is honoured")
    func explicitSchemesAreHonoured() {
        for query in ["https://example.com/path", "http://example.com"] {
            guard case .address(let url)? = destination(query) else {
                Issue.record("\(query) should be an address")
                continue
            }
            #expect(url.absoluteString == query)
        }
    }

    /// The conservative half of the rule. Each of these has a dot but is not somewhere to go.
    @Test("Dotted text that is not a host stays a search")
    func dottedNonHostsStaySearches() {
        for query in ["3.5", "v1.2", "file.", ".hidden", "a..b", "swift 5.9"] {
            let result = destination(query)
            #expect(result != nil, "\(query) should still be actionable")
            if case .address = result {
                Issue.record("\(query) should not have been treated as an address")
            }
        }
    }

    /// Anything with a space in it is a phrase, whatever else it looks like.
    @Test("Whitespace forces a search")
    func whitespaceForcesSearch() {
        guard case .search = destination("example.com and more")! else {
            Issue.record("expected a search")
            return
        }
    }

    @Test("An empty or blank query offers nothing")
    func blankQueriesOfferNothing() {
        #expect(destination("") == nil)
        #expect(destination("   ") == nil)
        #expect(destination("\n\t") == nil)
    }

    /// Shift-Return skips the results page. `btnI=1` is Google's Lucky button; the
    /// query still has to be encoded the same way as an ordinary search.
    @Test("A phrase's first result uses I'm Feeling Lucky")
    func phrasesOpenTheFirstSearchHit() {
        guard case .firstResult(let url)? = WebSearch.firstResultDestination(for: "how to use this") else {
            Issue.record("expected a first-result search")
            return
        }
        #expect(url.absoluteString.hasPrefix(WebSearch.firstResultSearchTemplate))
        #expect(url.absoluteString.contains("how%20to%20use%20this"))
        #expect(!url.absoluteString.hasPrefix(WebSearch.searchTemplate))
    }

    /// An address is already the first result, so Lucky must not wrap it in a search.
    @Test("An address's first result is the address")
    func anAddressFirstResultIsTheAddress() {
        guard case .address = WebSearch.firstResultDestination(for: "grok.com") else {
            Issue.record("expected the address itself")
            return
        }
        #expect(WebSearch.firstResultDestination(for: "   ") == nil)
    }

    /// The reported interstitial: Google wraps the Lucky hit in `/url?q=`. Opening that
    /// in the browser is the "Redirect Notice". The destination is already in `q`.
    @Test("A Google redirect wrapper yields the destination page")
    func aGoogleRedirectWrapperYieldsThePage() throws {
        let wrapped = try #require(URL(
            string: "https://www.google.com/url?q=https://ca.indeed.com/career-advice/how-to-respond"
        ))
        let page = try #require(WebSearch.pageURL(skippingGoogleRedirect: wrapped))
        #expect(page.host == "ca.indeed.com")
        #expect(page.scheme == "https")

        let search = try #require(URL(string: "https://www.google.com/search?q=how+to+use+this"))
        #expect(WebSearch.pageURL(skippingGoogleRedirect: search) == nil)

        let direct = try #require(URL(string: "https://ca.indeed.com/career-advice"))
        #expect(WebSearch.pageURL(skippingGoogleRedirect: direct) == direct)
    }

    /// Query-string metacharacters have to be encoded, or they truncate or corrupt the parameter.
    @Test("Characters that would break the query are encoded")
    func metacharactersAreEncoded() {
        guard case .search(let url)? = destination("a&b=c?d#e+f") else {
            Issue.record("expected a search")
            return
        }
        let query = url.absoluteString.dropFirst(WebSearch.searchTemplate.count)
        // None of these may survive literally, or they would be read as URL syntax.
        for character in ["&", "=", "?", "#", "+"] {
            #expect(!query.contains(character), "\(character) survived unencoded")
        }
        // And the whole thing still parses.
        #expect(URL(string: url.absoluteString) != nil)
    }

    @Test("Surrounding whitespace is trimmed before deciding")
    func surroundingWhitespaceIsTrimmed() {
        guard case .address(let url)? = destination("  grok.com  ") else {
            Issue.record("expected an address")
            return
        }
        #expect(url.absoluteString == "https://grok.com")
    }

    @Test("Both kinds of destination expose a usable URL")
    func destinationsExposeAURL() {
        #expect(destination("grok.com")?.url.host == "grok.com")
        #expect(destination("hello world")?.url.host == "www.google.com")
    }

    /// Non-Latin queries are the case where naive encoding falls over.
    @Test("A non-Latin query still produces a valid URL")
    func nonLatinQueriesEncode() {
        guard case .search(let url)? = destination("日本語 検索") else {
            Issue.record("expected a search")
            return
        }
        #expect(url.absoluteString.hasPrefix(WebSearch.searchTemplate))
        #expect(!url.absoluteString.contains(" "))
    }

    // MARK: - Assistants

    /// Every provider is offered, in a stable order, after the search.
    ///
    /// Order is the contract here: it decides what Return does, and Return has meant "look this
    /// up" since before the assistants existed.
    @Test("a phrase is offered to every assistant, after the search")
    func promptsFollowTheSearch() {
        let offers = WebSearch.destinations(for: "how do I revert a merge commit")
        #expect(offers.count == 2 + WebSearch.PromptProvider.allCases.count)

        guard case .search = offers.first else {
            Issue.record("the search should still come first")
            return
        }
        guard case .firstResult = offers.dropFirst().first else {
            Issue.record("the first-result offer should sit under Search the web")
            return
        }

        let providers: [WebSearch.PromptProvider] = offers.dropFirst().compactMap { offer in
            guard case .prompt(let provider, _) = offer else { return nil }
            return provider
        }
        #expect(providers == WebSearch.PromptProvider.allCases)
    }

    /// An address keeps its own default, and still gets the assistants after it.
    @Test("an address is still offered to the assistants, but never first")
    func addressKeepsItsDefault() {
        let offers = WebSearch.destinations(for: "grok.com")
        guard case .address = offers.first else {
            Issue.record("an address must still be the default")
            return
        }
        #expect(offers.count == 2 + WebSearch.PromptProvider.allCases.count)
    }

    /// The prompt has to arrive intact. Every one of these characters is ordinary in a question
    /// and every one of them would otherwise truncate the parameter or invent a second one.
    @Test("the prompt survives the characters that break query strings")
    func promptSurvivesEncoding() {
        let query = "a+b & c=d? e#f 100%"
        for offer in WebSearch.destinations(for: query) {
            guard case .prompt(let provider, let url) = offer else { continue }
            let text = url.absoluteString
            #expect(text.hasPrefix(provider.template), "\(provider) used the wrong template")

            let parameter = String(text.dropFirst(provider.template.count))
            #expect(!parameter.contains("+"), "\(provider) left a bare + in the prompt")
            #expect(!parameter.contains("&"), "\(provider) left a bare & in the prompt")
            #expect(!parameter.contains("="), "\(provider) left a bare = in the prompt")
            #expect(!parameter.contains("?"), "\(provider) left a bare ? in the prompt")
            #expect(!parameter.contains("#"), "\(provider) left a bare # in the prompt")
            #expect(!parameter.contains(" "), "\(provider) left a bare space in the prompt")

            // And it round-trips: what the assistant receives is what was typed.
            #expect(parameter.removingPercentEncoding == query, "\(provider) mangled the prompt")
        }
    }

    /// Every provider goes somewhere over TLS, at the host it says it does.
    @Test("each provider's template is an https URL at its own host")
    func templatesAreWellFormed() {
        for provider in WebSearch.PromptProvider.allCases {
            #expect(provider.template.hasPrefix("https://"))
            #expect(provider.template.hasSuffix("q="))
            #expect(provider.siteURL.hasPrefix("https://"))
            #expect(!provider.displayName.isEmpty)

            let host = URL(string: provider.siteURL)?.host
            #expect(host != nil)
            if let host {
                #expect(provider.template.contains(host), "\(provider) prompts a different host")
            }
        }
    }

    /// The logo request must carry no part of what the user typed.
    ///
    /// `logoSourceURL` is handed to the favicon service, which puts it on the network. The prompt
    /// URL is never fetched — it is only ever handed to the browser, and only once the user has
    /// picked that result — so this is the boundary that keeps a half-typed question off the wire.
    @Test("fetching a provider's logo sends nothing the user typed")
    func logoRequestCarriesNoQuery() {
        let query = "something private and identifying"
        for offer in WebSearch.destinations(for: query) {
            guard case .prompt = offer else { continue }
            let target = WebSearchTarget(query: query, destination: offer)
            let source = try? #require(target.logoSourceURL)
            #expect(source != nil)
            guard let source else { continue }

            #expect(!source.contains("?"), "the logo URL carries a query string: \(source)")
            for word in query.split(separator: " ") {
                #expect(!source.contains(word), "the logo URL leaked \(word)")
            }
        }

        // And the non-prompt offers have no logo to fetch at all.
        for offer in WebSearch.destinations(for: "grok.com") {
            switch offer {
            case .prompt: continue
            case .address, .search, .firstResult:
                #expect(WebSearchTarget(query: "grok.com", destination: offer)
                    .logoSourceURL == nil)
            }
        }
    }
}
