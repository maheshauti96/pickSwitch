import CoreGraphics
import Testing
@testable import PeekSwitchCore

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
