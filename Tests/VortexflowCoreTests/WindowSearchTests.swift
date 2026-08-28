import AppKit
import CoreGraphics
import Testing
@testable import VortexflowCore

/// Type-to-filter.
///
/// The ranking is what makes two keystrokes enough to commit without looking, so it is
/// pinned here rather than left to whatever `contains` happens to return.
@Suite("Window search")
struct WindowSearchTests {

    private static let windows: [WindowEntry] = [
        Fixture.entry(id: 1, app: "Safari", title: "Apple"),
        Fixture.entry(id: 2, app: "Notes", title: "Safari bookmarks to sort"),
        Fixture.entry(id: 3, app: "Cursor", title: ".env.local — Quattr-5"),
        Fixture.entry(id: 4, app: "Comet", title: "Sprint 331 - Scrum Board - Jira"),
        Fixture.entry(id: 5, app: "Warp", title: "~/Documents"),
    ]

    // MARK: - Matching

    @Test("An empty query matches everything, unchanged")
    func emptyQueryMatchesEverything() {
        #expect(WindowSearch.filter(Self.windows, query: "").count == Self.windows.count)
        #expect(WindowSearch.filter(Self.windows, query: "   ").map(\.windowID)
            == Self.windows.map(\.windowID))
    }

    /// The application name is what people type first, so a window whose *app* matches
    /// must beat one that merely mentions the word in its title.
    @Test("The application name outranks a title mention")
    func applicationNameOutranksTitle() {
        let results = WindowSearch.filter(Self.windows, query: "safari")
        #expect(results.count == 2)
        #expect(results.first?.applicationName == "Safari")
        #expect(results.last?.applicationName == "Notes")
    }

    @Test("A prefix of the application name is enough")
    func prefixOfApplicationNameMatches() {
        #expect(WindowSearch.filter(Self.windows, query: "cur").map(\.applicationName) == ["Cursor"])
        #expect(WindowSearch.filter(Self.windows, query: "wa").map(\.applicationName) == ["Warp"])
    }

    @Test("Titles are searchable too")
    func titlesAreSearchable() {
        #expect(WindowSearch.filter(Self.windows, query: "jira").map(\.applicationName) == ["Comet"])
        #expect(WindowSearch.filter(Self.windows, query: "documents").map(\.applicationName) == ["Warp"])
    }

    /// Real window titles are full of punctuation, so a word inside one has to be findable
    /// without typing the leading dot or dash.
    @Test("A word inside a punctuated title is findable")
    func wordInsidePunctuatedTitleIsFindable() {
        #expect(WindowSearch.filter(Self.windows, query: "env").map(\.applicationName) == ["Cursor"])
        #expect(WindowSearch.filter(Self.windows, query: "board").map(\.applicationName) == ["Comet"])
    }

    @Test("Matching ignores case and accents")
    func matchingIgnoresCaseAndAccents() {
        #expect(WindowSearch.filter(Self.windows, query: "SAFARI").count == 2)

        let accented = [Fixture.entry(id: 9, app: "Café", title: "Menu")]
        #expect(WindowSearch.filter(accented, query: "cafe").count == 1)
        #expect(WindowSearch.filter(accented, query: "CAFÉ").count == 1)
    }

    @Test("A query that matches nothing returns nothing")
    func noMatchesReturnsNothing() {
        #expect(WindowSearch.filter(Self.windows, query: "zzzz").isEmpty)
    }

    /// Equally good matches must keep the order they arrived in, which is
    /// most-recently-used — otherwise the top result would move for no visible reason.
    @Test("Equal matches keep their most-recently-used order")
    func equalMatchesKeepIncomingOrder() {
        let entries = [
            Fixture.entry(id: 1, app: "Chrome", title: "One"),
            Fixture.entry(id: 2, app: "Chrome", title: "Two"),
            Fixture.entry(id: 3, app: "Chrome", title: "Three"),
        ]
        #expect(WindowSearch.filter(entries, query: "chrome").map(\.windowID) == [1, 2, 3])
    }

    // MARK: - Which keystrokes are typing

    @Test("Printable characters are treated as typing")
    func printableCharactersAreTyping() {
        for text in ["a", "Z", "7", " ", "-", ".", "é"] {
            #expect(WindowSearch.isSearchable(text), "\(text) should be searchable")
        }
    }

    /// Arrow keys and function keys arrive as private-use characters. Treating those as
    /// text would put invisible junk in the query.
    @Test("Function and arrow keys are not typing")
    func functionKeysAreNotTyping() {
        #expect(!WindowSearch.isSearchable(""))
        // Private-use range, which is how AppKit reports arrows and function keys.
        #expect(!WindowSearch.isSearchable("\u{F700}"))
        #expect(!WindowSearch.isSearchable("\u{F704}"))
        // Control characters.
        #expect(!WindowSearch.isSearchable("\u{1B}"))
        #expect(!WindowSearch.isSearchable("\u{7F}"))
    }

    // MARK: - State integration

    @Test("Typing narrows the list and selects the best match")
    @MainActor
    func typingNarrowsAndSelects() {
        let state = OverlayState()
        state.load(entries: Self.windows, selectedIndex: 1)

        #expect(state.appendToSearch("saf"))
        #expect(state.isSearching)
        #expect(state.searchQuery == "saf")
        #expect(state.localEntries.count == 2)
        // Selection returns to the top, because after typing the best match is the intent.
        #expect(state.selectedIndex == 0)
        #expect(state.selectedEntry?.applicationName == "Safari")
    }

    @Test("Backspacing widens the list again")
    @MainActor
    func backspacingWidensTheList() {
        let state = OverlayState()
        state.load(entries: Self.windows, selectedIndex: 0)

        state.appendToSearch("cur")
        #expect(state.localEntries.count == 1)

        // "cu" is a looser query, so it matches more: Cursor by application prefix, and
        // Warp because its title contains "do(cu)ments".
        #expect(state.backspaceSearch())
        #expect(state.searchQuery == "cu")
        #expect(state.localEntries.count == 2)
        #expect(state.entries.first?.applicationName == "Cursor")

        state.backspaceSearch()
        state.backspaceSearch()
        #expect(state.searchQuery.isEmpty)
        #expect(!state.isSearching)
        #expect(state.entries.count == Self.windows.count)
    }

    @Test("Clearing the search restores every window")
    @MainActor
    func clearingRestoresEveryWindow() {
        let state = OverlayState()
        state.load(entries: Self.windows, selectedIndex: 0)
        state.appendToSearch("warp")
        #expect(state.localEntries.count == 1)

        #expect(state.clearSearch())
        #expect(state.entries.count == Self.windows.count)
        // Nothing to clear the second time, which is what lets Escape fall through to
        // dismissing the overlay.
        #expect(!state.clearSearch())
    }

    @Test("A query matching nothing is distinguishable from an empty desktop")
    @MainActor
    func noMatchesIsDistinguishable() {
        let state = OverlayState()
        state.load(entries: Self.windows, selectedIndex: 0)
        state.appendToSearch("zzzz")

        #expect(state.entries.isEmpty)
        #expect(state.selectedIndex == nil)
        #expect(state.hasNoSearchMatches)

        state.clearSearch()
        #expect(!state.hasNoSearchMatches)
    }

    /// An empty desktop is not a failed search, and must not claim to be one.
    @Test("An empty desktop is not reported as a failed search")
    @MainActor
    func emptyDesktopIsNotAFailedSearch() {
        let state = OverlayState()
        state.load(entries: [], selectedIndex: nil)
        #expect(!state.hasNoSearchMatches)
    }

    /// Closing a filtered window must remove it for good, not just from the filtered view.
    @Test("Closing a window while searching does not resurrect it")
    @MainActor
    func closingWhileSearchingDoesNotResurrect() {
        let state = OverlayState()
        state.load(entries: Self.windows, selectedIndex: 0)
        state.appendToSearch("safari")
        #expect(state.localEntries.count == 2)

        #expect(state.remove(windowID: 1))
        #expect(state.localEntries.count == 1)

        state.clearSearch()
        #expect(state.entries.count == Self.windows.count - 1)
        #expect(!state.entries.contains { $0.windowID == 1 })
    }

    /// A fresh presentation must not inherit the last one's query.
    @Test("A new presentation starts unfiltered")
    @MainActor
    func newPresentationStartsUnfiltered() {
        let state = OverlayState()
        state.load(entries: Self.windows, selectedIndex: 0)
        state.appendToSearch("warp")
        #expect(state.isSearching)

        state.load(entries: Self.windows, selectedIndex: 0)
        #expect(!state.isSearching)
        #expect(state.entries.count == Self.windows.count)
    }

    // MARK: - Layout

    /// The field is part of the layout, not an overlay on top of it, or it would cover the
    /// first row of cards.
    @Test("The search field reserves space without changing capacity", arguments: OverlayLayoutStyle.allCases)
    func searchFieldReservesSpace(style: OverlayLayoutStyle) {
        func layout(searching: Bool) -> OverlayLayout {
            OverlayLayout(
                style: style,
                cardCount: 12,
                selectedIndex: 0,
                availableContentWidth: 1400,
                availableContentHeight: 860,
                isSearching: searching
            )
        }

        let plain = layout(searching: false)
        let searching = layout(searching: true)

        #expect(isClose(
            searching.panelSize.height,
            plain.panelSize.height + OverlayLayout.searchFieldHeight
        ))
        #expect(isClose(searching.panelSize.width, plain.panelSize.width))
        // Reserving space must not change how many cards fit, or typing would reshuffle
        // the arrangement as well as filtering it.
        #expect(searching.visibleRange == plain.visibleRange)
        #expect(searching.capacity == plain.capacity)

        // Every card shifts down by exactly the reserved amount.
        for (plainCard, searchCard) in zip(plain.positionedCards(), searching.positionedCards()) {
            #expect(plainCard.index == searchCard.index)
            #expect(isClose(searchCard.frame.minY, plainCard.frame.minY + OverlayLayout.searchFieldHeight))
            #expect(isClose(searchCard.frame.minX, plainCard.frame.minX))
        }
    }

    // MARK: - Select all

    /// The gesture that was reported broken: Command-A, then delete, clears the query.
    @Test("select all then delete wipes the query")
    @MainActor
    func selectAllThenDeleteClears() {
        let subject = OverlayState()
        subject.load(entries: Self.windows, selectedIndex: 0)
        subject.appendToSearch("saf")
        #expect(subject.searchQuery == "saf")
        #expect(subject.isQuerySelected == false)

        #expect(subject.selectAllSearch())
        #expect(subject.isQuerySelected)
        // Selecting changes nothing about what matched, so nothing is re-filtered.
        #expect(subject.searchQuery == "saf")

        subject.backspaceSearch()
        #expect(subject.searchQuery.isEmpty)
        #expect(subject.isQuerySelected == false)
    }

    /// Typing over a selection replaces it, as it does in every other text field.
    @Test("typing over a selected query replaces it")
    @MainActor
    func typingOverSelectionReplaces() {
        let subject = OverlayState()
        subject.load(entries: Self.windows, selectedIndex: 0)
        subject.appendToSearch("saf")
        #expect(subject.selectAllSearch())

        subject.appendToSearch("cur")
        #expect(subject.searchQuery == "cur")
        #expect(subject.isQuerySelected == false)
    }

    /// A selection may not outlive the string it referred to. Sources settling mid-selection is
    /// the realistic way that happens: tabs and the application catalogue both arrive late.
    @Test("any edit drops the selection")
    @MainActor
    func editsDropTheSelection() {
        let subject = OverlayState()
        subject.load(entries: Self.windows, selectedIndex: 0)
        subject.appendToSearch("saf")

        #expect(subject.selectAllSearch())
        subject.setTabs([])
        #expect(subject.isQuerySelected == false)

        // Nothing to select when nothing is typed, and selecting twice is not a change.
        #expect(subject.clearSearch())
        #expect(subject.selectAllSearch() == false)
        subject.appendToSearch("x")
        #expect(subject.selectAllSearch())
        #expect(subject.selectAllSearch() == false)
    }

    /// The band has to hold the pill that is drawn in it.
    ///
    /// These were two unrelated literals until the pill was enlarged — a 12pt query inside a
    /// fixed 40pt strip — and they had already drifted apart in the harmless direction: a third
    /// of the reserved height was empty, which is why the field looked smaller than the space it
    /// was being given. Drifting the other way is not harmless: the pill is centred in the band,
    /// so it would spill over the first row of cards.
    @Test("The reserved band holds the pill that is drawn in it")
    func reservedBandHoldsThePill() {
        let metrics = OverlayLayout.Search.self
        #expect(metrics.pillHeight <= OverlayLayout.searchFieldHeight)
        #expect(metrics.pillHeight >= metrics.lineHeight)
        // And the caret stays a caret rather than becoming a stripe the height of the pill.
        #expect(metrics.caretHeight < metrics.pillHeight)
        #expect(metrics.caretHeight > metrics.queryFontSize)

        // The radial budget takes min(0.94 x height, height - band), so a band past 6% of the
        // display starts shrinking the ring. Worth failing on rather than discovering as a
        // smaller hub — the reference's canvas is the 0.94 one.
        #expect(OverlayLayout.searchFieldHeight <= 982 * 0.06)
    }

    /// A long query may not run the pill out of the panel it is drawn on.
    ///
    /// The narrowest panel is the empty state's plate, which is reached exactly when a long
    /// query matches nothing — so it is the case a long query is most likely to be seen in
    /// rather than a corner of one. Swept over character widths because the widest and
    /// narrowest glyphs differ by a factor of nearly two at this size, which is what rules out
    /// bounding this by a character count.
    @Test("The query pill stays inside every panel it is drawn over")
    func queryPillStaysInsideThePanel() {
        let metrics = OverlayLayout.Search.self
        let font = NSFont.systemFont(ofSize: metrics.queryFontSize, weight: .semibold)
        func width(_ text: String) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }

        let narrowest = OverlayLayout(
            style: .strip,
            cardCount: 0,
            selectedIndex: nil,
            availableContentWidth: 1400,
            availableContentHeight: 860,
            isSearching: true
        ).panelSize.width

        for panel in [narrowest, 480, 824, 1200] {
            for query in [
                "how to",
                String(repeating: "M", count: 120),
                String(repeating: "8", count: 120),
                String(repeating: "verylongquery ", count: 12),
                String(repeating: "i", count: 200),
            ] {
                let shown = metrics.fittedQuery(query, panelWidth: panel, width: width)
                let pill = width(shown) + metrics.furniture
                #expect(
                    pill <= panel - metrics.panelMargin * 2 + 0.5,
                    "\(Int(panel))pt panel: \(query.count) chars drew a \(pill)pt pill"
                )
                // Nothing is trimmed that did not need to be.
                if width(query) + metrics.furniture
                    <= panel - metrics.panelMargin * 2 {
                    #expect(shown == query, "\(Int(panel))pt panel trimmed a query that fitted")
                }
                // What survives is the end of the query, which is what the caret sits against.
                if shown != query {
                    #expect(shown.hasPrefix("\u{2026}"))
                    #expect(query.hasSuffix(shown.dropFirst()))
                }
            }
        }
    }

    /// Hit-testing has to follow the shift, or clicks would land one row off while
    /// searching.
    @Test("Cards stay hittable while searching", arguments: OverlayLayoutStyle.allCases)
    func cardsStayHittableWhileSearching(style: OverlayLayoutStyle) {
        let subject = OverlayLayout(
            style: style,
            cardCount: 9,
            selectedIndex: 1,
            availableContentWidth: 1400,
            availableContentHeight: 860,
            isSearching: true
        )

        for card in subject.positionedCards() {
            let point = CGPoint(
                x: card.frame.midX,
                y: subject.panelSize.height - card.frame.midY
            )
            #expect(
                subject.cardIndex(
                    atPanelPoint: point,
                    scrollOffset: 0,
                    selectedScale: style.selectedScale
                ) == card.index,
                "\(style): card \(card.index) missed while searching"
            )
        }
    }
}

/// What the history depth is allowed to affect, and what it must not.
///
/// The reported failure was that a running application was missing from the switcher. The half of it
/// that lived here was worse than the missing card: the trimmed list was the *only* list the state
/// held, so a window over the depth could not be found by typing either — the switcher answered "that
/// application is not running" about an application that was.
@MainActor
struct RestingListAndSearchTests {

    private func window(_ id: CGWindowID, _ app: String) -> WindowEntry {
        Fixture.entry(id: id, app: app, title: "\(app) window", zOrder: Int(id))
    }

    /// Ten drawn, eleven known.
    private func loaded() -> (state: OverlayState, trimmed: WindowEntry) {
        let shown = (1...10).map { window(CGWindowID($0), "App\($0)") }
        let slack = window(99, "Slack")
        let state = OverlayState()
        state.load(entries: shown, searchable: shown + [slack], selectedIndex: 0)
        return (state, slack)
    }

    @Test("The resting list is what the depth allowed, not everything")
    func restingListHonoursTheDepth() {
        let (state, _) = loaded()
        #expect(state.entries.count == 10)
        #expect(!state.entries.contains { $0.applicationName == "Slack" })
    }

    /// The fix. A window the depth trimmed is one keystroke away rather than denied.
    @Test("A window the depth trimmed is still found by typing")
    func aTrimmedWindowIsStillSearchable() {
        let (state, _) = loaded()
        #expect(state.appendToSearch("slack"))
        #expect(state.entries.contains { $0.applicationName == "Slack" })
    }

    /// The trap in holding two lists: clearing a search has to return to the resting one. Reading the
    /// searchable list back for an empty query would silently ignore the depth from then on.
    @Test("Clearing the search returns to the resting list, not to everything")
    func clearingTheSearchReturnsToTheRestingList() {
        let (state, _) = loaded()
        state.appendToSearch("slack")
        #expect(state.entries.contains { $0.applicationName == "Slack" })

        state.clearSearch()
        #expect(state.entries.count == 10)
        #expect(!state.entries.contains { $0.applicationName == "Slack" })
    }

    /// Closing a window has to remove it from both lists, or clearing a search brings the dead card
    /// back from whichever list the empty query reads.
    @Test("A closed window does not come back when the search is cleared")
    func aClosedWindowStaysGone() {
        let (state, _) = loaded()
        state.appendToSearch("slack")
        #expect(state.remove(windowID: 99))

        state.clearSearch()
        #expect(!state.entries.contains { $0.applicationName == "Slack" })
        #expect(!state.appendToSearch("slack") || !state.entries.contains { $0.windowID == 99 })
    }

    /// Callers with nothing trimmed pass one list and must behave exactly as before.
    @Test("Loading without a wider list leaves search over the same entries")
    func loadingWithoutAWiderListIsUnchanged() {
        let shown = [window(1, "Finder"), window(2, "Warp"), window(3, "Slack")]
        let state = OverlayState()
        state.load(entries: shown, selectedIndex: 0)
        #expect(state.entries.count == 3)

        #expect(state.appendToSearch("slack"))
        #expect(state.localEntries.map(\.applicationName) == ["Slack"])

        state.clearSearch()
        #expect(state.entries.count == 3)
    }
}
