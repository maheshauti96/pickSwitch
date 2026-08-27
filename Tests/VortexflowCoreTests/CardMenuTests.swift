import CoreGraphics
import Testing
@testable import VortexflowCore

/// What the card menu offers, and — mostly — what it withholds.
///
/// The omissions are the part worth testing. An item that cannot do anything is worse than no item:
/// it invites a click, does nothing, and leaves the user to guess whether they misunderstood the
/// feature or the feature is broken. Every rule below exists because something is genuinely
/// unavailable, not to keep the menu short.
struct CardMenuTests {

    private func window(
        app: String = "Google Chrome",
        id: CGWindowID = 169
    ) -> WindowEntry {
        Fixture.entry(id: id, app: app, title: "A window")
    }

    private var browserContext: CardMenu.Context {
        CardMenu.Context(
            isBrowserWindow: true,
            knownTabCount: 23,
            isAudible: false,
            hasAccessibilityElement: true,
            isPinned: false
        )
    }

    // MARK: - What appears

    /// The reported priority: for a browser, the useful thing is the tab, and the fastest route to a
    /// tab is the search the overlay already has. So it leads.
    @Test func aBrowserWindowLeadsWithTabSearch() {
        let items = CardMenu.items(for: window(), context: browserContext)
        #expect(items.first == .searchWindowTabs(count: 23))
    }

    @Test func theTabCountIsShownWhenKnownAndOmittedWhenNot() {
        #expect(CardMenuItem.searchWindowTabs(count: 23).title == "Search this window's 23 tabs")
        // Tabs are not fetched until the user types, so the item has to stand without a number.
        #expect(CardMenuItem.searchWindowTabs(count: nil).title == "Search this window's tabs")
    }

    @Test func everyWindowOffersItsApplicationActions() {
        let items = CardMenu.items(for: window(app: "Warp"), context: CardMenu.Context())
        #expect(items.contains(.quitApplication(name: "Warp")))
        #expect(items.contains(.pinApplication(name: "Warp")))
    }

    @Test func pinningReflectsTheCurrentState() {
        var context = CardMenu.Context()
        context.isPinned = true
        let items = CardMenu.items(for: window(app: "Slack"), context: context)
        #expect(items.contains(.unpinApplication(name: "Slack")))
        #expect(!items.contains(.pinApplication(name: "Slack")))
    }

    // MARK: - What is withheld, and why

    /// A tab result has no window of its own and an installed application has no window yet, so
    /// neither can be closed, minimised or pinned as a window. No menu at all is the honest answer.
    @Test func onlyWindowsGetAMenu() {
        let tab = WindowEntry.tabEntry(
            BrowserTab(
                browser: .chrome, windowIdentifier: 1, tabIndex: 1,
                title: "ChatGPT", url: "https://chatgpt.com/"
            ),
            application: nil
        )
        #expect(CardMenu.items(for: tab, context: browserContext).isEmpty)
    }

    /// The case that made this rule necessary: windows found on another desktop through the window
    /// server carry no Accessibility element, which is why they already show no close button. Closing
    /// and minimising them is impossible rather than unreliable.
    @Test func windowsWithNoAccessibilityElementOfferNoWindowActions() {
        var context = browserContext
        context.hasAccessibilityElement = false
        let items = CardMenu.items(for: window(), context: context)

        #expect(!items.contains(.closeWindow))
        #expect(!items.contains(.minimizeWindow))
        // The application-level actions survive, because they never needed Accessibility.
        #expect(items.contains(.quitApplication(name: "Google Chrome")))
    }

    /// Muting acts on what is playing now. With nothing playing there is nothing to act on, so the
    /// item is absent rather than present and inert.
    @Test func muteAppearsOnlyForAWindowMakingNoise() {
        var quiet = browserContext
        quiet.isAudible = false
        #expect(!CardMenu.items(for: window(), context: quiet).contains(.muteAudible))

        var audible = browserContext
        audible.isAudible = true
        #expect(CardMenu.items(for: window(), context: audible).contains(.muteAudible))
    }

    @Test func aNonBrowserWindowIsNotOfferedTabSearch() {
        var context = browserContext
        context.isBrowserWindow = false
        let items = CardMenu.items(for: window(app: "Warp"), context: context)
        #expect(!items.contains(.searchWindowTabs(count: 23)))
        #expect(!items.contains(.searchWindowTabs(count: nil)))
    }

    // MARK: - Shape

    /// A withheld group must not leave a separator behind it, or the menu grows blank gaps exactly
    /// where something was unavailable — which looks like a rendering fault rather than a decision.
    @Test func withheldGroupsLeaveNoStraySeparators() {
        // Only the application group survives: not a browser, no Accessibility element.
        let items = CardMenu.items(for: window(app: "Warp"), context: CardMenu.Context())

        #expect(items.first != .separator)
        #expect(items.last != .separator)
        for (index, item) in items.enumerated() where item == .separator {
            #expect(index > 0 && index < items.count - 1, "separator at the edge of the menu")
            #expect(items[index - 1] != .separator, "two separators in a row")
        }
    }

    @Test func theFullMenuIsGroupedInOrder() {
        var context = browserContext
        context.isAudible = true
        let items = CardMenu.items(for: window(), context: context)

        #expect(items == [
            .searchWindowTabs(count: 23),
            .muteAudible,
            .separator,
            .minimizeWindow,
            .closeWindow,
            .separator,
            .pinApplication(name: "Google Chrome"),
            .quitApplication(name: "Google Chrome"),
        ])
    }

    @Test func noItemHasAnEmptyTitleExceptSeparators() {
        var context = browserContext
        context.isAudible = true
        for item in CardMenu.items(for: window(), context: context) where item != .separator {
            #expect(!item.title.isEmpty, "\(item) has no title")
        }
    }
}
