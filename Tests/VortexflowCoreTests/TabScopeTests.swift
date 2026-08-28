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

    /// Search through Tabs is offered before the card is paired, so the chrome has to
    /// appear immediately. Esc still has to get the user back to their windows.
    @Test func awaitingAPairingIsAScopeThatEscapeClears() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.load(entries: [Fixture.entry(id: 1, app: "Google Chrome")], selectedIndex: 0)

        state.beginAwaitingTabScope()
        #expect(state.showsSearch)
        #expect(state.isAwaitingTabScope)
        #expect(state.entries.isEmpty, "the window list must not remain the search corpus")
        #expect(state.clearSearch())
        #expect(!state.isAwaitingTabScope)
        #expect(!state.showsSearch)

        state.beginAwaitingTabScope()
        state.load(entries: [Fixture.entry(id: 2, app: "Warp")], selectedIndex: 0)
        #expect(!state.isAwaitingTabScope)
    }

    @Test func aWindowTitlePicksThatWindowsTabsOutOfTheLoadedList() {
        var window = Fixture.entry(id: 1121, app: "Google Chrome", title: "taxonomy engine - Grok - Google Chrome")
        window.bundleIdentifier = "com.google.Chrome"
        #expect(
            TabWindowMatcher.scriptingIdentifier(
                for: window,
                in: [
                    BrowserTab(browser: .chrome, windowIdentifier: 10, tabIndex: 1, title: "YouTube Music", url: "https://music.youtube.com/"),
                    BrowserTab(browser: .chrome, windowIdentifier: 20, tabIndex: 1, title: "taxonomy engine", url: "https://example.com/"),
                    BrowserTab(browser: .chrome, windowIdentifier: 20, tabIndex: 2, title: "Grok", url: "https://grok.com/"),
                ]
            ) == 20
        )
    }

    @Test func aLoneBrowserWindowIsScopedWithoutATitle() {
        var window = Fixture.entry(id: 1, app: "Google Chrome", title: "")
        window.bundleIdentifier = "com.google.Chrome"
        #expect(
            TabWindowMatcher.scriptingIdentifier(
                for: window,
                in: [
                    BrowserTab(browser: .chrome, windowIdentifier: 99, tabIndex: 1, title: "ChatGPT", url: "https://chatgpt.com/"),
                ]
            ) == 99
        )
    }

    @Test func pairingAScopeClearsTheAwaitingFlag() {
        let state = loaded()
        state.beginAwaitingTabScope()
        state.setTabScope(Self.chromeWindowB)
        #expect(!state.isAwaitingTabScope)
        #expect(state.tabScope == Self.chromeWindowB)
    }

    /// A scope belongs to the presentation that asked for it. Carried across, the next trigger would
    /// open showing one window's tabs and none of the user's windows.
    @Test func aNewPresentationDropsTheScope() {
        let state = loaded()
        state.setTabScope(Self.chromeWindowB)
        state.load(entries: [Fixture.entry(id: 1, app: "Warp")], selectedIndex: 0)

        #expect(state.tabScope == nil)
        #expect(!state.isAwaitingTabScope)
        #expect(state.entries.count == 1)
    }

    /// Choosing the menu item is what fetches the tabs. The window list must not remain
    /// searchable in the meantime — that leaked every window into "Search through Tabs".
    /// The empty state says "Looking for tabs…" until the scoped list arrives.
    @Test func tabsArrivingAfterTheScopeFillTheList() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1121, app: "Google Chrome", title: "Window B")
        state.load(entries: [window], selectedIndex: 0)
        state.setTabScope(Self.chromeWindowB)

        #expect(state.entries.isEmpty, "windows must not stay as the search corpus")
        #expect(state.showsSearch, "the pill has to show that a scope is active")
        #expect(!state.hasLoadedTabs)

        let changed = state.setTabs([
            tab("ChatGPT", window: Self.chromeWindowB, index: 1),
            tab("Google Docs", window: Self.chromeWindowA, index: 1),
        ])

        #expect(changed)
        #expect(state.entries.map(\.displayTitle) == ["ChatGPT"])
        #expect(!state.entries.contains { $0.displayTitle == "Google Docs" })
    }

    /// The query is remembered and applied when the tabs arrive. Typing must not
    /// search the resting windows, and must not pull in the other window's tabs.
    @Test func typingBeforeTabsArriveRemembersTheQueryAndStaysScoped() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1121, app: "Google Chrome", title: "Window B")
        state.load(entries: [window], selectedIndex: 0)
        state.setTabScope(Self.chromeWindowB)
        // List already empty from the scope; the query is still stored.
        _ = state.appendToSearch("chat")
        #expect(state.searchQuery == "chat")
        #expect(state.entries.isEmpty)

        #expect(state.setTabs([
            tab("ChatGPT", window: Self.chromeWindowB, index: 1),
            tab("Grok", window: Self.chromeWindowB, index: 2),
            tab("Google Docs", window: Self.chromeWindowA, index: 1),
        ]))
        #expect(state.entries.map(\.displayTitle) == ["ChatGPT"])
    }

    /// Tabs that arrive while we still do not know which window was clicked must not
    /// become an unscoped search of every browser.
    @Test func tabsArrivingWhileAwaitingAPairingStayHiddenUntilScoped() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1121, app: "Google Chrome", title: "Window B")
        state.load(entries: [window], selectedIndex: 0)
        state.beginAwaitingTabScope()
        #expect(state.entries.isEmpty)

        #expect(!state.setTabs([
            tab("ChatGPT", window: Self.chromeWindowB, index: 1),
            tab("Google Docs", window: Self.chromeWindowA, index: 1),
        ]))
        #expect(state.entries.isEmpty)
        #expect(state.hasLoadedTabs)

        #expect(state.setTabScope(Self.chromeWindowB))
        #expect(state.entries.map(\.displayTitle) == ["ChatGPT"])
    }

    @Test func anEmptyWindowStaysOnTheTabMessageInsteadOfGoingBack() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1, app: "Google Chrome", title: "A window")
        state.load(entries: [window], selectedIndex: 0)
        state.beginAwaitingTabScope()
        #expect(state.entries.isEmpty)
        state.finishTabScopeWithoutTabs(
            reason: "No tabs in this window",
            windowIdentifier: Int(window.windowID)
        )
        #expect(!state.isAwaitingTabScope)
        #expect(state.tabScope == Int(window.windowID))
        #expect(state.tabScopeFailure == "No tabs in this window")
        #expect(state.entries.isEmpty)
        #expect(state.showsSearch)
        #expect(!state.hasLoadedTabs)
        #expect(state.clearSearch())
        #expect(state.tabScopeFailure == nil)
        #expect(state.tabScope == nil)
        #expect(state.entries.map(\.id) == [window.id])
    }

    /// Typing after a 0-tab window must not quietly become a search of every window.
    @Test func typingAfterAnEmptyWindowErrorDoesNotSearchWindows() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1, app: "Google Chrome", title: "A window")
        state.load(entries: [window], selectedIndex: 0)
        state.finishTabScopeWithoutTabs(
            reason: "No tabs in this window",
            windowIdentifier: Int(window.windowID)
        )

        _ = state.appendToSearch("chrome")
        #expect(state.searchQuery == "chrome")
        #expect(state.entries.isEmpty)
        #expect(state.tabScopeFailure == "No tabs in this window")
        #expect(state.showsSearch)
    }

    /// Pairing can miss without a scripting id. That is still a tab-search miss, not a
    /// reason to restore the window ring — and typing must not search those windows.
    @Test func aPairingMissStaysOnTheErrorUntilEscape() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        let window = Fixture.entry(id: 1, app: "Google Chrome", title: "A window")
        state.load(entries: [window], selectedIndex: 0)
        state.beginAwaitingTabScope()
        state.finishTabScopeWithoutTabs(reason: "Couldn't find tabs in this window")

        #expect(state.tabScope == nil)
        #expect(state.tabScopeFailure == "Couldn't find tabs in this window")
        #expect(state.entries.isEmpty)

        _ = state.appendToSearch("window")
        #expect(state.entries.isEmpty)
        #expect(state.tabScopeFailure == "Couldn't find tabs in this window")

        #expect(state.clearSearch())
        #expect(state.entries.map(\.id) == [window.id])
    }

    @Test func accessibilityTabsPickUpScriptedAddressesWithoutLosingTheScope() {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        var window = Fixture.entry(id: 1121, app: "Google Chrome", title: "taxonomy engine - Grok")
        window.bundleIdentifier = "com.google.Chrome"
        state.load(entries: [window], selectedIndex: 0)

        let listed = BrowserTab(
            browser: .chrome,
            windowIdentifier: Int(window.windowID),
            tabIndex: 1,
            title: "taxonomy engine - Grok",
            url: "",
            usesNativeWindowIdentifier: true
        )
        state.setTabs([WindowEntry.tabEntry(listed, application: nil)])
        state.setTabScope(Int(window.windowID))
        #expect(state.entries.first?.sourceLabel == "taxonomy engine - Grok")

        let scripted = BrowserTab(
            browser: .chrome,
            windowIdentifier: 99,
            tabIndex: 1,
            title: "taxonomy engine - Grok",
            url: "https://grok.com/c/1",
            allowsFaviconRequest: true
        )
        #expect(state.enrichTabAddresses([scripted], matching: window))
        #expect(state.tabScope == Int(window.windowID))
        #expect(state.entries.count == 1)
        #expect(state.entries[0].tab?.url == "https://grok.com/c/1")
        #expect(state.entries[0].tab?.allowsFaviconRequest == true)
        #expect(state.entries[0].sourceLabel == "grok.com")
        #expect(state.entries[0].tab?.usesNativeWindowIdentifier == true)
        #expect(state.entries[0].tab?.scriptedWindowIdentifier == 99)
        #expect(state.entries[0].tab?.scriptedActivation?.windowIdentifier == 99)
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
