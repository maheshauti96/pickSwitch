import CoreGraphics
import Testing
@testable import VortexflowCore

/// Restricting the overlay to one browser window's tabs.
///
/// This is one mechanism doing the job of the two things asked for: with no query typed it lists that
/// window's tabs, which is "see all tabs", and typing narrows them, which is "search in this window's
/// tabs". Keeping it as one scope rather than two features is why the empty-query case matters as much
/// as the filtering one.
@Suite("Tab scope")
@MainActor
struct TabScopeTests {

    private static let chromeWindowA = 1_263_775_564
    private static let chromeWindowB = 1_263_775_930

    private func tab(_ title: String, window: Int, index: Int) -> WindowEntry {
        WindowEntry.tabEntry(
            BrowserTab(
                browser: .chrome,
                windowIdentifier: window,
                tabIndex: index,
                title: title,
                url: "https://example.com/\(index)"
            ),
            application: nil
        )
    }

    private func loaded() -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.load(
            entries: [
                Fixture.entry(id: 169, app: "Google Chrome", title: "Window A"),
                Fixture.entry(id: 1121, app: "Google Chrome", title: "Window B"),
                Fixture.entry(id: 130, app: "Kiro", title: "Editor"),
            ],
            selectedIndex: 0
        )
        state.setTabs([
            tab("ChatGPT", window: Self.chromeWindowB, index: 1),
            tab("Grok", window: Self.chromeWindowB, index: 2),
            tab("Google Docs", window: Self.chromeWindowA, index: 1),
        ])
        return state
    }

    /// The "see all tabs" half: a scope with nothing typed lists exactly that window's tabs.
    @Test func aScopeWithNoQueryListsThatWindowsTabs() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)

        #expect(state.entries.count == 2)
        #expect(state.entries.map(\.displayTitle).sorted() == ["ChatGPT", "Grok"])
    }

    /// The "search in this window's tabs" half.
    @Test func typingNarrowsWithinTheScope() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        state.appendToSearch("chat")

        #expect(state.entries.map(\.displayTitle) == ["ChatGPT"])
    }

    /// The other window's tabs are the thing most likely to leak in, since they share a browser and a
    /// process and differ only by the identifier being scoped on.
    @Test func anotherWindowsTabsAreExcluded() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        #expect(!state.entries.contains { $0.displayTitle == "Google Docs" })
    }

    /// Windows and web offers are withheld too. The question asked was about the inside of one
    /// window, so answering with the user's other windows would be answering a different one.
    @Test func windowsAndWebOffersAreWithheldWhileScoped() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        state.appendToSearch("chat")

        let nonTabs = state.entries.filter { !$0.isTab }
        #expect(nonTabs.isEmpty, "non-tab results leaked into a scoped list: \(nonTabs.map(\.id))")
    }

    /// Clearing the query has to clear the scope with it. A filtered list with nothing on screen
    /// explaining why, and no way back, is worse than either state on its own.
    @Test func clearingTheSearchAlsoLeavesTheScope() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        state.appendToSearch("chat")

        #expect(state.clearSearch())
        #expect(state.tabScope == nil)
        // Back to the windows the user started with.
        #expect(state.entries.contains { $0.displayTitle == "Editor" })
    }

    /// Even with no text typed, the scope alone is something to clear.
    @Test func clearingWorksWithAScopeAndNoQuery() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        #expect(state.clearSearch())
        #expect(state.tabScope == nil)
    }

    /// A scope belongs to the presentation that asked for it. Carried across, the next trigger would
    /// open showing one window's tabs and none of the user's windows.
    @Test func aNewPresentationDropsTheScope() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        state.load(entries: [Fixture.entry(id: 1, app: "Warp")], selectedIndex: 0)

        #expect(state.tabScope == nil)
        #expect(state.entries.count == 1)
    }

    /// Choosing the menu item is what fetches the tabs, so they arrive *after* the scope is set and
    /// with no query typed. The list has to keep showing the current windows until that fetch lands
    /// — applying an empty scoped list in between is what read as "No switchable windows are open".
    @Test func tabsArrivingAfterTheScopeFillTheList() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1121, app: "Google Chrome", title: "Window B")
        state.load(entries: [window], selectedIndex: 0)
        state.setTabScope(Self.chromeWindowB)

        #expect(state.entries.map(\.id) == [window.id], "windows stay until the tabs arrive")
        #expect(state.showsSearch, "the pill has to show that a scope is active")
        #expect(!state.hasLoadedTabs)

        let changed = state.setTabs([
            tab("ChatGPT", window: Self.chromeWindowB, index: 1),
            tab("Google Docs", window: Self.chromeWindowA, index: 1),
        ])

        #expect(changed)
        #expect(state.entries.map(\.displayTitle) == ["ChatGPT"])
    }

    /// Typing before the fetch lands must not empty the list either. The query is remembered and
    /// applied when the tabs arrive.
    @Test func typingBeforeTabsArriveDoesNotEmptyTheList() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1121, app: "Google Chrome", title: "Window B")
        state.load(entries: [window], selectedIndex: 0)
        state.setTabScope(Self.chromeWindowB)
        #expect(!state.appendToSearch("chat"))
        #expect(state.searchQuery == "chat")
        #expect(state.entries.map(\.id) == [window.id])

        #expect(state.setTabs([
            tab("ChatGPT", window: Self.chromeWindowB, index: 1),
            tab("Grok", window: Self.chromeWindowB, index: 2),
        ]))
        #expect(state.entries.map(\.displayTitle) == ["ChatGPT"])
    }

    @Test func theTabCountIsPerWindow() {
        let state = loaded()
        #expect(state.tabCount(forWindowIdentifier: Self.chromeWindowB) == 2)
        #expect(state.tabCount(forWindowIdentifier: Self.chromeWindowA) == 1)
        #expect(state.tabCount(forWindowIdentifier: 999) == 0)
    }

    /// Terminal's title-bar pills are other windows sharing a frame. A scope on the front
    /// window has to include those neighbours or Search through Tabs shows only one session.
    @Test func terminalWindowTabsThatShareAFrameAreListedTogether() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 42, app: "Terminal", title: "grok")
        state.load(entries: [window], selectedIndex: 0)

        let front = WindowEntry.tabEntry(
            BrowserTab(
                browser: .terminal,
                windowIdentifier: 7659,
                tabIndex: 1,
                title: "grok",
                url: "",
                groupKey: "0,70,877,605"
            ),
            application: nil
        )
        let neighbour = WindowEntry.tabEntry(
            BrowserTab(
                browser: .terminal,
                windowIdentifier: 7656,
                tabIndex: 1,
                title: "zsh",
                url: "",
                groupKey: "0,70,877,605"
            ),
            application: nil
        )
        state.setTabScope(7659)
        #expect(state.setTabs([front, neighbour]))
        #expect(state.entries.map(\.displayTitle) == ["grok", "zsh"])
        #expect(state.tabCount(forWindowIdentifier: 7659) == 2)
    }
}
