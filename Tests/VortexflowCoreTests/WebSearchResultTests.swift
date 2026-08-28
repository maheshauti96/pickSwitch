import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import VortexflowCore

/// Web search as a result you can pick, rather than only as a consolation for finding nothing.
///
/// The gap this closes: typing "grok" with Grok Bot installed matched the application, so the
/// no-matches offer never appeared and there was no way to search the web for the word at all. One
/// local match removed the option entirely, which is not what "no matches" was meant to mean.
///
/// The rules worth holding are about *when* it appears and *where* in the order, because both can
/// break without anything looking wrong: an offer that never appears is invisible, and one that
/// appears first would quietly hijack Return from the window the user was actually looking for.
@Suite("Web search result")
@MainActor
struct WebSearchResultTests {

    private func windows() -> [WindowEntry] {
        [
            Fixture.entry(id: 1, app: "Grok Bot", title: "Grok Bot", zOrder: 0),
            Fixture.entry(id: 2, app: "Safari", title: "Reading list", zOrder: 1),
        ]
    }

    private func state() -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.isVisible = true
        state.load(entries: windows(), selectedIndex: 0)
        return state
    }

    // MARK: - When it appears

    @Test("a query that matched locally still offers the web")
    func offeredAlongsideLocalMatches() {
        let subject = state()
        subject.appendToSearch("grok")

        #expect(subject.localEntries.count == 1, "the local match should still be there")
        // The offers are a trailing block rather than one entry — a search plus one prompt per
        // assistant — so this asserts the shape instead of a count that grows whenever another
        // provider is added.
        let offers = subject.entries.filter(\.isWebSearch)
        #expect(offers.count == 2 + WebSearch.PromptProvider.allCases.count)
        #expect(subject.entries.count == subject.localEntries.count + offers.count)
        #expect(subject.entries.suffix(offers.count).allSatisfy { $0.isWebSearch })
        #expect(offers.first?.sourceLabel == "Search the web")
        #expect(offers.dropFirst().first?.sourceLabel == "Open first result")
    }

    /// Switching is the point of the switcher, so the local match keeps the default selection and
    /// Return keeps meaning "go to the thing I found".
    @Test("the web offer is last and never selected by default")
    func webOfferIsLastAndNotSelected() {
        let subject = state()
        subject.appendToSearch("grok")

        #expect(subject.selectedIndex == 0)
        #expect(subject.selectedEntry?.isWebSearch == false)
        // Every offer sits after every local result, and none of them holds the selection.
        let firstOffer = subject.entries.firstIndex(where: \.isWebSearch)
        #expect(firstOffer != nil)
        if let firstOffer {
            #expect(subject.entries[firstOffer...].allSatisfy { $0.isWebSearch })
            #expect(firstOffer > 0, "an offer took the default selection")
        }
    }

    /// With nothing matching, the web is the only thing left to offer, so it becomes the results
    /// rather than a sentence about them. `hasNoSearchMatches` still has to read false-for-matched
    /// off the *local* results, or every query would look like a hit.
    @Test("a query that matched nothing offers the web as the results")
    func offeredWhenNothingMatched() {
        let subject = state()
        subject.setTabs([])
        subject.setApplications([])
        subject.appendToSearch("zzzznothing")

        #expect(subject.localEntries.isEmpty)
        #expect(subject.entries.isEmpty == false)
        #expect(subject.entries.allSatisfy { $0.isWebSearch })
        #expect(subject.hasNoSearchMatches)
        #expect(subject.canOfferWebSearch)
    }

    /// Tabs and the installed-application catalogue arrive asynchronously. Offering the web before
    /// they land would put a web result under the default selection during the moment before the
    /// application that actually matched appears, so Return pressed quickly would open a browser
    /// instead of the app.
    @Test("nothing is offered while the local sources are still answering")
    func withheldUntilLocalSourcesSettle() {
        let subject = state()
        subject.appendToSearch("zzzznothing")

        #expect(subject.entries.isEmpty, "no offer yet")
        #expect(subject.isResolvingSearch)

        subject.setTabs([])
        subject.setApplications([])

        #expect(subject.entries.isEmpty == false, "offered once the local sources have settled")
        #expect(subject.entries.allSatisfy { $0.isWebSearch })
    }

    // MARK: - An address has two answers

    /// The conservative address test cannot tell "grok.com, take me there" from "grok.com, tell me
    /// about it", and since these are results the user picks from, it does not have to.
    @Test("an address offers both going there and searching for it")
    func addressOffersBoth() {
        let subject = state()
        subject.setTabs([])
        subject.setApplications([])
        subject.appendToSearch("grok.com")

        let offers = subject.entries.filter { $0.isWebSearch }
        // Address, then search, then one prompt per assistant. The first two are the ordering
        // that decides what Return does, so they stay pinned by position.
        #expect(offers.count == 2 + WebSearch.PromptProvider.allCases.count)
        #expect(offers.first?.sourceLabel == "Go to grok.com")
        #expect(offers.dropFirst().first?.sourceLabel == "Search the web")
        #expect(
            offers.suffix(WebSearch.PromptProvider.allCases.count).map(\.sourceLabel)
                == WebSearch.PromptProvider.allCases.map { "Prompt on \($0.displayName)" }
        )
    }

    /// Address first, so Return keeps doing what it did before the second option existed.
    @Test("going there is the default of the two")
    func addressIsTheDefault() {
        let subject = state()
        subject.setTabs([])
        subject.setApplications([])
        subject.appendToSearch("grok.com")

        #expect(subject.selectedIndex == 0)
        #expect(subject.selectedEntry?.sourceLabel == "Go to grok.com")
    }

    /// Two results from one query must not share an id. The list is diffed by id, so a collision
    /// would silently drop one of the two options rather than showing both.
    @Test("the two offers have distinct identities")
    func twoOffersHaveDistinctIdentities() {
        let subject = state()
        subject.setTabs([])
        subject.setApplications([])
        subject.appendToSearch("grok.com")

        let offers = subject.entries.filter { $0.isWebSearch }
        let ids = Set(offers.map(\.id))
        #expect(ids.count == offers.count, "an id was reused, so an option was lost: \(ids)")
    }

    @Test("a phrase offers only a search")
    func phraseOffersOnlyASearch() {
        let subject = state()
        subject.setTabs([])
        subject.setApplications([])
        subject.appendToSearch("quarterly report")

        let offers = subject.entries.filter { $0.isWebSearch }
        // No address to go to, so: the search, the first hit, then the assistants.
        #expect(offers.count == 2 + WebSearch.PromptProvider.allCases.count)
        #expect(offers.first?.sourceLabel == "Search the web")
        #expect(offers.dropFirst().first?.sourceLabel == "Open first result")
        #expect(offers.allSatisfy { $0.sourceLabel != "Go to site" })
    }

    @Test("no query means no offer")
    func notOfferedWithoutAQuery() {
        let subject = state()
        #expect(subject.entries.allSatisfy { !$0.isWebSearch })
    }

    @Test("whitespace alone is not a query")
    func whitespaceIsNotAQuery() {
        let subject = state()
        subject.appendToSearch("   ")
        #expect(subject.entries.allSatisfy { !$0.isWebSearch })
    }

    @Test("clearing the query takes the offer away again")
    func clearingRemovesTheOffer() {
        let subject = state()
        subject.appendToSearch("grok")
        #expect(subject.entries.contains { $0.isWebSearch })

        subject.clearSearch()
        #expect(subject.entries.allSatisfy { !$0.isWebSearch })
        #expect(subject.entries.count == windows().count)
    }

    // MARK: - What it promises

    /// "Search the web" and "Go to somewhere" are different promises, and the query alone does not
    /// say which one Return will keep.
    @Test("a phrase offers a search, an address offers to go there")
    func labelNamesTheDestination() throws {
        let phrase = WebSearchTarget(
            query: "quarterly report",
            destination: try #require(WebSearch.destination(for: "quarterly report"))
        )
        #expect(phrase.sourceLabel == "Search the web")

        let address = WebSearchTarget(
            query: "grok.com",
            destination: try #require(WebSearch.destination(for: "grok.com"))
        )
        #expect(address.sourceLabel == "Go to grok.com")
    }

    /// The hub names the action, because a web result's title is the query — which says what was
    /// typed but not that confirming it leaves the machine.
    @Test("the hub names the action rather than leaving the line blank")
    func hubNamesTheAction() {
        let subject = state()
        subject.appendToSearch("grok")
        let entry = subject.entries.first(where: \.isWebSearch)

        #expect(entry?.isWebSearch == true)
        if let entry {
            #expect(subject.hubSummary(for: entry).sourceLine == "Search the web")
        }
        // And each assistant names itself, so the hub never says merely "prompt".
        for provider in WebSearch.PromptProvider.allCases {
            let prompt = subject.entries.first {
                $0.webSearch?.sourceLabel == "Prompt on \(provider.displayName)"
            }
            #expect(prompt != nil, "\(provider.displayName) was not offered")
            if let prompt {
                #expect(
                    subject.hubSummary(for: prompt).sourceLine
                        == "Prompt on \(provider.displayName)"
                )
            }
        }
    }

    // MARK: - It is not a window

    /// Every window-only treatment has to skip it, or a synthetic result starts collecting
    /// per-application counts, positions and desktop warnings that mean nothing.
    @Test("window-only treatments all skip it")
    func windowTreatmentsSkipIt() throws {
        let subject = state()
        subject.appendToSearch("grok")
        let entry = try #require(subject.entries.last)

        #expect(entry.isWindow == false)
        #expect(entry.isTab == false)
        #expect(entry.isApplication == false)
        #expect(subject.windowPosition(for: entry) == nil)
        #expect(subject.badgeCount(for: entry) == nil)
        #expect(subject.display(for: entry) == nil)
        #expect(subject.canClose(entry) == false)
        #expect(subject.hubSummary(for: entry).isOnAnotherDesktop == false)
    }

    /// Its identity is the query, so two different searches are two different results and the same
    /// search re-typed is the same one. Without this the list would churn on every keystroke.
    @Test("its identity follows the query")
    func identityFollowsTheQuery() {
        let first = WindowEntry.webSearchEntry(
            WebSearchTarget(query: "grok", destination: .search(URL(string: "https://e.com/?q=grok")!))
        )
        let second = WindowEntry.webSearchEntry(
            WebSearchTarget(query: "grok", destination: .search(URL(string: "https://e.com/?q=grok")!))
        )
        let other = WindowEntry.webSearchEntry(
            WebSearchTarget(query: "warp", destination: .search(URL(string: "https://e.com/?q=warp")!))
        )

        #expect(first.id == second.id)
        #expect(first.id != other.id)
        #expect(first.id.hasPrefix("web:"))
    }
}
