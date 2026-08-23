import Foundation
import Testing
@testable import PeekSwitchCore

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
}
