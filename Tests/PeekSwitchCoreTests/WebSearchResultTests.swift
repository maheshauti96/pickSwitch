import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import PeekSwitchCore

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
        #expect(subject.entries.count == 2, "and the web offer alongside it")
        #expect(subject.entries.last?.isWebSearch == true)
    }

    /// Switching is the point of the switcher, so the local match keeps the default selection and
    /// Return keeps meaning "go to the thing I found".
    @Test("the web offer is last and never selected by default")
    func webOfferIsLastAndNotSelected() {
        let subject = state()
        subject.appendToSearch("grok")

        #expect(subject.selectedIndex == 0)
        #expect(subject.selectedEntry?.isWebSearch == false)
        #expect(subject.entries.firstIndex { $0.isWebSearch } == subject.entries.count - 1)
    }

    /// With nothing matching, the empty state makes the same offer as a full sentence, which reads
    /// better there than a single card would. So this must stay out of the way of that.
    @Test("a query that matched nothing adds no result, leaving the empty state its prompt")
    func notOfferedWhenNothingMatched() {
        let subject = state()
        subject.setTabs([])
        subject.setApplications([])
        subject.appendToSearch("zzzznothing")

        #expect(subject.entries.isEmpty)
        #expect(subject.hasNoSearchMatches)
        #expect(subject.canOfferWebSearch)
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
        let entry = subject.entries.last

        #expect(entry?.isWebSearch == true)
        if let entry {
            #expect(subject.hubSummary(for: entry).sourceLine == "Search the web")
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
