import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// Searching browser tabs.
///
/// The point of the feature is that a tab you cannot see — not the active tab, maybe not
/// even the front window — is findable by name. So the tests are about it being reachable
/// through search, ranked sensibly, and kept out of the way otherwise.
@Suite("Browser tabs")
struct BrowserTabTests {

    private func tab(
        _ browser: BrowserTab.Browser = .chrome,
        window: Int = 1,
        index: Int,
        title: String,
        url: String
    ) -> BrowserTab {
        BrowserTab(
            browser: browser,
            windowIdentifier: window,
            tabIndex: index,
            title: title,
            url: url
        )
    }

    private func entry(_ tab: BrowserTab) -> WindowEntry {
        WindowEntry.tabEntry(tab, application: nil)
    }

    /// Taken from a live Chrome session, including the awkward parts: a tab whose title
    /// says nothing about its address, and two tabs sharing one.
    private var chromeTabs: [WindowEntry] {
        [
            entry(tab(index: 1, title: "OpenMausBot: Your own team of AI bots", url: "https://www.openmausbot.com/#pricing")),
            entry(tab(index: 2, title: "taxonomy engine - Grok", url: "https://grok.com/c/01b2e981?rid=d283ef")),
            entry(tab(index: 3, title: "YouTube", url: "https://www.youtube.com/")),
            entry(tab(window: 2, index: 4, title: "Explore Opportunities | Mercor", url: "https://work.mercor.com/explore")),
        ]
    }

    // MARK: - Identity

    /// Every tab in a window would share the window's `CGWindowID`, so identity cannot come
    /// from there — two tabs colliding would break the card list and the hit-test mapping.
    @Test("Tabs are distinguishable from each other and from windows")
    func tabsHaveDistinctIdentities() {
        let entries = chromeTabs
        let identities = Set(entries.map(\.id))
        #expect(identities.count == entries.count)

        for entry in entries {
            #expect(entry.isTab)
            // No window identity, so the window-shaped machinery skips them.
            #expect(entry.windowID == 0)
            #expect(entry.axElement == nil)
        }

        let window = Fixture.entry(id: 1, app: "Google Chrome")
        #expect(!window.isTab)
        #expect(window.id != entries[0].id)
    }

    @Test("A tab shows its own title, falling back to its host")
    func tabTitleFallsBackToHost() {
        #expect(entry(tab(index: 1, title: "taxonomy engine - Grok", url: "https://grok.com/c/1")).displayTitle
            == "taxonomy engine - Grok")
        // A tab still loading has no title yet.
        #expect(entry(tab(index: 1, title: "", url: "https://grok.com/c/1")).displayTitle == "grok.com")
    }

    @Test("The host is the readable part of a URL")
    func hostIsTheReadablePart() {
        #expect(tab(index: 1, title: "", url: "https://grok.com/c/01b2?rid=x").host == "grok.com")
        // "www." carries no information and costs card width.
        #expect(tab(index: 1, title: "", url: "https://www.youtube.com/").host == "youtube.com")
        #expect(tab(index: 1, title: "", url: "http://localhost:3000/explorer").host == "localhost")
    }

    // MARK: - Search

    /// The case that prompted the feature: "grok" should find the Grok tab even though its
    /// title never begins with it and the tab is not the active one.
    @Test("Typing a site name finds the tab")
    func typingSiteNameFindsTheTab() {
        let results = WindowSearch.filter(chromeTabs, query: "grok")
        #expect(results.count == 1)
        #expect(results.first?.tab?.host == "grok.com")
        #expect(results.first?.tab?.tabIndex == 2)
    }

    /// A host match has to rank at least as highly as a title match, because the address is
    /// usually what the user remembers.
    @Test("A host match outranks an incidental title mention")
    func hostMatchOutranksTitleMention() {
        let entries = [
            entry(tab(index: 1, title: "Alternative to Grok Bot", url: "https://github.com/openmaus")),
            entry(tab(index: 2, title: "taxonomy engine", url: "https://grok.com/c/1")),
        ]
        let results = WindowSearch.filter(entries, query: "grok")
        #expect(results.count == 2)
        #expect(results.first?.tab?.host == "grok.com")
    }

    @Test("Tab titles are searchable too")
    func tabTitlesAreSearchable() {
        #expect(WindowSearch.filter(chromeTabs, query: "mercor").count == 1)
        #expect(WindowSearch.filter(chromeTabs, query: "youtube").count == 1)
    }

    @Test("A query matching no tab returns none")
    func nonMatchingQueryReturnsNoTabs() {
        #expect(WindowSearch.filter(chromeTabs, query: "zzzz").isEmpty)
    }

    // MARK: - State integration

    /// Tabs must not appear until asked for. A browser with forty tabs would otherwise bury
    /// every real window in the switcher.
    @Test("Tabs stay out of the default list")
    @MainActor
    func tabsStayOutOfTheDefaultList() {
        let state = OverlayState()
        state.load(
            entries: [Fixture.entry(id: 1, app: "Google Chrome"), Fixture.entry(id: 2, app: "Slack")],
            selectedIndex: 0
        )
        #expect(!state.hasLoadedTabs)

        state.setTabs(chromeTabs)
        #expect(state.hasLoadedTabs)
        // Loaded, but not shown: no query is active.
        #expect(state.entries.count == 2)
        #expect(state.entries.allSatisfy { !$0.isTab })
    }

    @Test("Typing brings matching tabs into the results")
    @MainActor
    func typingBringsTabsIntoResults() {
        let state = OverlayState()
        state.load(entries: [Fixture.entry(id: 1, app: "Slack", title: "#peek-dev")], selectedIndex: 0)
        state.setTabs(chromeTabs)

        #expect(state.appendToSearch("grok"))
        #expect(state.localEntries.count == 1)
        #expect(state.entries.first?.isTab == true)
        #expect(state.selectedIndex == 0)
        #expect(state.selectedEntry?.tab?.host == "grok.com")
    }

    /// Tabs arriving asynchronously must fold into a query the user has already typed,
    /// rather than being ignored because the search ran before they loaded.
    @Test("Tabs loaded after typing still join the results")
    @MainActor
    func tabsLoadedAfterTypingJoinResults() {
        let state = OverlayState()
        state.load(entries: [Fixture.entry(id: 1, app: "Slack")], selectedIndex: 0)

        state.appendToSearch("grok")
        #expect(state.entries.isEmpty)

        // The browsers answer a moment later.
        #expect(state.setTabs(chromeTabs))
        #expect(state.localEntries.count == 1)
        #expect(state.entries.first?.tab?.host == "grok.com")
    }

    /// A real window should win a tie against a tab: switching windows is the primary job.
    @Test("A window outranks a tab that scores the same")
    @MainActor
    func windowOutranksEquallyScoringTab() {
        let state = OverlayState()
        state.load(entries: [Fixture.entry(id: 1, app: "Grok Bot", title: "Grok Bot")], selectedIndex: 0)
        state.setTabs(chromeTabs)

        state.appendToSearch("grok")
        #expect(state.localEntries.count == 2)
        #expect(state.entries.first?.isTab == false)
        #expect(state.localEntries.last?.isTab == true)
    }

    @Test("Clearing the search puts the tabs away again")
    @MainActor
    func clearingSearchPutsTabsAway() {
        let state = OverlayState()
        state.load(entries: [Fixture.entry(id: 1, app: "Slack")], selectedIndex: 0)
        state.setTabs(chromeTabs)
        state.appendToSearch("grok")
        #expect(state.entries.first?.isTab == true)

        state.clearSearch()
        #expect(state.entries.count == 1)
        #expect(state.entries.allSatisfy { !$0.isTab })
    }

    /// A new presentation re-enumerates, so stale tabs from the last one must not linger.
    @Test("A new presentation forgets the previous tabs")
    @MainActor
    func newPresentationForgetsTabs() {
        let state = OverlayState()
        state.load(entries: [Fixture.entry(id: 1, app: "Slack")], selectedIndex: 0)
        state.setTabs(chromeTabs)
        #expect(state.hasLoadedTabs)

        state.load(entries: [Fixture.entry(id: 1, app: "Slack")], selectedIndex: 0)
        #expect(!state.hasLoadedTabs)

        state.appendToSearch("grok")
        #expect(state.entries.isEmpty)
    }

    /// A tab cannot be closed from the switcher, so the affordance must not be offered —
    /// otherwise clicking it would close the browser window instead.
    @Test("Tabs offer no close button")
    @MainActor
    func tabsOfferNoCloseButton() {
        let state = OverlayState()
        state.canCloseWindows = true
        state.load(entries: [Fixture.entry(id: 1, app: "Slack")], selectedIndex: 0)
        state.setTabs(chromeTabs)
        state.appendToSearch("grok")

        for entry in state.entries {
            #expect(!state.canClose(entry))
        }
    }

    // MARK: - Browser support

    @Test("Every supported browser is addressable")
    func everyBrowserIsAddressable() {
        for browser in BrowserTab.Browser.allCases {
            #expect(!browser.bundleIdentifier.isEmpty)
            #expect(!browser.scriptingName.isEmpty)
            #expect(browser.bundleIdentifier.contains("."))
        }
        let identifiers = Set(BrowserTab.Browser.allCases.map(\.bundleIdentifier))
        #expect(identifiers.count == BrowserTab.Browser.allCases.count)
    }

    /// Safari's scripting vocabulary differs from Chrome's, and using the wrong term fails
    /// at runtime rather than at compile time.
    @Test("Safari uses its own scripting terms")
    func safariUsesItsOwnTerms() {
        #expect(BrowserTab.Browser.safari.titleProperty == "name")
        #expect(BrowserTab.Browser.safari.usesCurrentTab)

        for browser in BrowserTab.Browser.allCases where browser != .safari {
            #expect(browser.titleProperty == "title")
            #expect(!browser.usesCurrentTab)
        }
    }

    // MARK: - Parsing tabs

    private static let field = "\u{01}"
    private static let item = "\u{02}"
    private static let record = "\u{03}"

    private func tabRecord(
        window: Int,
        mode: String,
        titles: [String],
        urls: [String]
    ) -> String {
        [
            String(window),
            mode,
            titles.joined(separator: Self.item),
            urls.joined(separator: Self.item),
        ].joined(separator: Self.field)
    }

    @Test("A tab record parses into tabs with their window's mode")
    func tabRecordParses() {
        let output = [
            tabRecord(
                window: 7,
                mode: "normal",
                titles: ["Home / X", "Inbox"],
                urls: ["https://x.com/home", "https://mail.example.com"]
            ),
            tabRecord(
                window: 8,
                mode: "incognito",
                titles: ["Private"],
                urls: ["https://example.com"]
            ),
        ].joined(separator: Self.record)

        let tabs = BrowserTabService.parseTabs(output, browser: .chrome)
        #expect(tabs.count == 3)

        #expect(tabs[0].windowIdentifier == 7)
        #expect(tabs[0].tabIndex == 1)
        #expect(tabs[0].host == "x.com")
        #expect(tabs[1].tabIndex == 2)

        // The eligibility that decides whether a request is ever made.
        #expect(tabs[0].allowsFaviconRequest)
        #expect(tabs[1].allowsFaviconRequest)
        #expect(!tabs[2].allowsFaviconRequest, "an incognito window's tabs must never be fetched")
    }

    /// Fails closed. An unrecognised mode is treated as private, because the cost of guessing
    /// wrong is a private address going out over the network.
    @Test("An unknown window mode blocks the icon request", arguments: ["", "guest", "unknown", "Normal-ish"])
    func unknownModeBlocksTheRequest(mode: String) {
        let output = tabRecord(
            window: 1,
            mode: mode,
            titles: ["Something"],
            urls: ["https://example.com"]
        )

        let tabs = BrowserTabService.parseTabs(output, browser: .chrome)
        #expect(tabs.count == 1)
        #expect(!tabs[0].allowsFaviconRequest, "mode \"\(mode)\" should not be eligible")
    }

    /// Safari cannot report a mode at all, so the script substitutes a literal and every Safari
    /// tab is ineligible — the same fail-closed treatment its windows already get.
    @Test("Safari tabs are never eligible")
    func safariTabsAreNeverEligible() {
        let output = tabRecord(
            window: 3,
            mode: "unknown",
            titles: ["Page"],
            urls: ["https://example.com"]
        )

        let tabs = BrowserTabService.parseTabs(output, browser: .safari)
        #expect(tabs.count == 1)
        #expect(!tabs[0].allowsFaviconRequest)
    }

    @Test("A malformed tab record is skipped rather than crashing")
    func malformedTabRecordsAreSkipped() {
        let output = [
            "not-a-number\u{01}normal\u{01}Title\u{01}https://example.com",
            ["5", "normal"].joined(separator: Self.field),
            tabRecord(window: 9, mode: "normal", titles: ["Good"], urls: ["https://good.example"]),
        ].joined(separator: Self.record)

        let tabs = BrowserTabService.parseTabs(output, browser: .chrome)
        #expect(tabs.count == 1)
        #expect(tabs[0].windowIdentifier == 9)
    }

    /// A tab with neither a title nor an address is still loading and cannot be matched.
    @Test("Empty tabs are dropped")
    func emptyTabsAreDropped() {
        let output = tabRecord(
            window: 2,
            mode: "normal",
            titles: ["", "Real"],
            urls: ["", "https://real.example"]
        )

        let tabs = BrowserTabService.parseTabs(output, browser: .chrome)
        #expect(tabs.count == 1)
        #expect(tabs[0].title == "Real")
    }
}
