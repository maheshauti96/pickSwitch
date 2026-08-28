import Testing
@testable import VortexflowCore

/// The order of operations in the tab-activation script, which is the whole of the bug it fixes.
///
/// Reported as: with several Chrome windows open, searching for a ChatGPT tab opened a *different*
/// Chrome window, and repeating the search opened the right tab. The cause was that the script raised
/// the tab's window before activating the browser, and raising a window while its application is in
/// the background does not move it when the window is on another desktop. Measured against a live
/// Chrome with one window per desktop: raise-then-activate put the wrong window in front 3 times out
/// of 3, activate-then-raise put the right one in front 3 times out of 3.
///
/// So what is asserted here is sequence, not syntax. Nothing else in the test suite can see it — the
/// script only proves itself against a running browser with windows spread over two desktops.
struct TabActivationScriptTests {

    private func tab(
        browser: BrowserTab.Browser = .chrome,
        windowIdentifier: Int = 1_263_775_930,
        tabIndex: Int = 6
    ) -> BrowserTab {
        BrowserTab(
            browser: browser,
            windowIdentifier: windowIdentifier,
            tabIndex: tabIndex,
            title: "ChatGPT",
            url: "https://chatgpt.com/"
        )
    }

    private func offset(of needle: String, in haystack: String) -> Int? {
        haystack.range(of: needle).map { haystack.distance(from: haystack.startIndex, to: $0.lowerBound) }
    }

    /// The regression itself: `activate` must precede the raise.
    @Test func theBrowserIsActivatedBeforeItsWindowIsRaised() throws {
        let script = BrowserTabService.activationScript(for: tab())
        let activate = try #require(offset(of: "activate", in: script))
        let raise = try #require(offset(of: "set index of targetWindow to 1", in: script))
        #expect(
            activate < raise,
            "activate must come first, or an off-desktop window will not be moved:\n\(script)"
        )
    }

    /// Selecting the tab has to happen before the raise too, so the window arrives already showing
    /// the tab the user picked rather than visibly switching to it afterwards.
    @Test func theTabIsSelectedBeforeTheWindowIsRaised() throws {
        let script = BrowserTabService.activationScript(for: tab())
        let select = try #require(offset(of: "set active tab index", in: script))
        let raise = try #require(offset(of: "set index of targetWindow to 1", in: script))
        #expect(select < raise)
    }

    /// No waiting and no delay, which is the part that had to be measured rather than reasoned about.
    /// A `repeat until frontmost` guard looked necessary and did nothing — AppleScript reports
    /// `frontmost` true as soon as activation is requested, so it ran zero times and the script it
    /// guarded still failed. Activating first is sufficient on its own.
    @Test func theScriptNeitherWaitsNorSleeps() {
        let script = BrowserTabService.activationScript(for: tab())
        #expect(!script.contains("repeat until frontmost"))
        #expect(!script.contains("delay"))
    }

    /// The window is addressed by id, which is the identifier the tab list was built from. Matching
    /// by index instead would drift the moment the user reorders or closes a window.
    @Test func theWindowIsAddressedByTheIdTheTabWasEnumeratedWith() {
        let script = BrowserTabService.activationScript(for: tab(windowIdentifier: 4242))
        #expect(script.contains("window id 4242"))
    }

    /// Accessibility tabs keep a CGWindowID for listing. Activation has to use Chrome's
    /// own window id, or `window id N` is a no-op and the click never leaves this desktop.
    @Test func aPairedAccessibilityTabActivatesThroughTheScriptedWindowId() throws {
        let listed = BrowserTab(
            browser: .chrome,
            windowIdentifier: 5_575,
            tabIndex: 3,
            title: "ChatGPT",
            url: "https://chatgpt.com/",
            usesNativeWindowIdentifier: true,
            scriptedWindowIdentifier: 1_263_775_930,
            scriptedTabIndex: 6
        )
        let target = try #require(listed.scriptedActivation)
        let script = BrowserTabService.activationScript(for: target)
        #expect(script.contains("window id 1263775930"))
        #expect(script.contains("set active tab index of targetWindow to 6"))
        #expect(!script.contains("window id 5575"))
    }

    /// Safari names the selected tab by object rather than by index, and that difference has to
    /// survive the reordering.
    @Test func safariKeepsItsOwnSelectionForm() throws {
        let script = BrowserTabService.activationScript(for: tab(browser: .safari, tabIndex: 3))
        #expect(script.contains("set current tab of targetWindow to tab 3 of targetWindow"))
        #expect(!script.contains("active tab index"))
        let activate = try #require(offset(of: "activate", in: script))
        let raise = try #require(offset(of: "set index of targetWindow to 1", in: script))
        #expect(activate < raise, "Safari lost the ordering fix")
    }

    /// Terminal selects by setting `selected` on the tab, not an index on the window.
    @Test func terminalKeepsItsOwnSelectionForm() throws {
        let script = BrowserTabService.activationScript(
            for: tab(browser: .terminal, windowIdentifier: 7659, tabIndex: 2)
        )
        #expect(script.contains("tell application \"Terminal\""))
        #expect(script.contains("window id 7659"))
        #expect(script.contains("set selected of tab 2 of targetWindow to true"))
        #expect(!script.contains("active tab index"))
        #expect(!script.contains("current tab"))
        let activate = try #require(offset(of: "activate", in: script))
        let select = try #require(offset(of: "set selected of tab 2", in: script))
        let raise = try #require(offset(of: "set index of targetWindow to 1", in: script))
        #expect(activate < raise, "Terminal lost the ordering fix")
        #expect(select < raise)
    }
}
