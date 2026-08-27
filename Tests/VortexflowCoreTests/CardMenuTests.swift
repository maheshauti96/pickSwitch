import AppKit
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
        id: CGWindowID = 169,
        minimized: Bool = false
    ) -> WindowEntry {
        Fixture.entry(id: id, app: app, title: "A window", minimized: minimized)
    }

    private var browserContext: CardMenu.Context {
        CardMenu.Context(
            isBrowserWindow: true,
            knownTabCount: 23,
            isAudible: false,
            hasAccessibilityElement: true,
            isPinned: false,
            isMinimized: false
        )
    }

    private func rows(_ entry: WindowEntry, _ context: CardMenu.Context) -> CardMenu.Rows {
        CardMenu.rows(for: entry, context: context)
    }

    // MARK: - Which row an action belongs in

    /// The split is the design. The window controls act on the window, and they are drawn above the
    /// preview because the preview *is* the window — the same reason a title bar carries them. The
    /// second row is about what the window contains or which application it belongs to, neither of
    /// which the preview shows.
    @Test func theRowsSplitWindowActionsFromContentActions() {
        var context = browserContext
        context.isAudible = true
        let result = rows(window(), context)

        #expect(result.windowControls == [
            .minimizeWindow,
            .closeWindow,
            .tileWindow(.leftHalf),
            .tileWindow(.rightHalf),
            .tileWindow(.topHalf),
            .tileWindow(.bottomHalf),
        ])
        #expect(result.actions == [
            .searchWindowTabs(count: 23),
            .muteAudible,
            .pinApplication(name: "Google Chrome"),
        ])
    }

    /// For a browser, the useful thing is the tab, and the fastest route to a tab is the search the
    /// overlay already has. So it leads its row.
    @Test func aBrowserWindowLeadsItsActionsWithTabSearch() {
        #expect(rows(window(), browserContext).actions.first == .searchWindowTabs(count: 23))
    }

    @Test func theTabCountIsShownWhenKnownAndOmittedWhenNot() {
        #expect(CardMenuItem.searchWindowTabs(count: 23).title == "Search this window's 23 tabs")
        // Tabs are not fetched until the user types, so the item has to stand without a number.
        #expect(CardMenuItem.searchWindowTabs(count: nil).title == "Search this window's tabs")
    }

    @Test func pinningReflectsTheCurrentState() {
        var context = CardMenu.Context()
        context.isPinned = true
        let result = rows(window(app: "Slack"), context)
        #expect(result.actions.contains(.unpinApplication(name: "Slack")))
        #expect(!result.actions.contains(.pinApplication(name: "Slack")))
    }

    /// Closing a window is not quitting its application, and the menu now offers only the first.
    /// Nothing may quietly reintroduce an action that terminates every window an application has.
    @Test func theMenuNeverOffersToQuitAnApplication() {
        var context = browserContext
        context.isAudible = true
        let result = rows(window(), context)
        let titles = (result.windowControls + result.actions).map(\.title)
        #expect(!titles.contains { $0.localizedCaseInsensitiveContains("quit") })
    }

    // MARK: - What is withheld, and why

    /// A tab result has no window of its own and an installed application has no window yet, so
    /// neither can be closed, minimised or tiled. No menu at all is the honest answer.
    @Test func onlyWindowsGetAMenu() {
        let tab = WindowEntry.tabEntry(
            BrowserTab(
                browser: .chrome, windowIdentifier: 1, tabIndex: 1,
                title: "ChatGPT", url: "https://chatgpt.com/"
            ),
            application: nil
        )
        #expect(rows(tab, browserContext).isEmpty)
    }

    /// The case that made this rule necessary: windows found on another desktop through the window
    /// server carry no Accessibility element, which is why they already show no close button. Closing,
    /// minimising and tiling them is impossible rather than unreliable.
    @Test func windowsWithNoAccessibilityElementOfferNoWindowControls() {
        var context = browserContext
        context.hasAccessibilityElement = false
        let result = rows(window(), context)

        #expect(result.windowControls.isEmpty)
        // The content and application actions survive, because they never needed Accessibility.
        #expect(result.actions.contains(.pinApplication(name: "Google Chrome")))
    }

    /// A minimized window's frame is not where it is or how big it looks, so sending it to half a
    /// screen you cannot see it on changes nothing observable.
    @Test func aMinimizedWindowIsNotOfferedTiling() {
        var context = browserContext
        context.isMinimized = true
        let result = rows(window(minimized: true), context)

        #expect(!result.windowControls.contains { if case .tileWindow = $0 { true } else { false } })
        // Close still applies: a minimized window can be closed from the Dock too.
        #expect(result.windowControls.contains(.closeWindow))
    }

    /// Muting acts on what is playing now. With nothing playing there is nothing to act on, so the
    /// item is absent rather than present and inert.
    @Test func muteAppearsOnlyForAWindowMakingNoise() {
        var quiet = browserContext
        quiet.isAudible = false
        #expect(!rows(window(), quiet).actions.contains(.muteAudible))

        var audible = browserContext
        audible.isAudible = true
        #expect(rows(window(), audible).actions.contains(.muteAudible))
    }

    @Test func aNonBrowserWindowIsNotOfferedTabSearch() {
        var context = browserContext
        context.isBrowserWindow = false
        let result = rows(window(app: "Warp"), context)
        #expect(!result.actions.contains(.searchWindowTabs(count: 23)))
        #expect(!result.actions.contains(.searchWindowTabs(count: nil)))
    }

    /// A window with nothing available on it must not produce an empty menu frame. Only the
    /// application row can carry a card this bare, and it must.
    @Test func theBarestWindowStillHasSomethingToOffer() {
        let result = rows(window(app: "Warp"), CardMenu.Context())
        #expect(result.windowControls.isEmpty)
        #expect(result.actions == [.pinApplication(name: "Warp")])
        #expect(!result.isEmpty)
    }

    // MARK: - Glyphs

    /// A glyph alone makes the user guess, so each carries a word and a symbol.
    @Test func everyActionHasAGlyphAndAName() {
        var context = browserContext
        context.isAudible = true
        let result = rows(window(), context)
        for item in result.windowControls + result.actions {
            #expect(!item.icon.symbolName.isEmpty, "\(item) has no symbol")
            #expect(!item.icon.label.isEmpty, "\(item) has no caption")
            #expect(!item.title.isEmpty, "\(item) has no title")
        }
    }

    /// A misspelled SF Symbol name renders as nothing at all, which is invisible in a diff and
    /// invisible in a passing test suite. Resolving each one is the only way to catch it.
    @Test func everySymbolResolvesOnThisSystem() {
        var context = browserContext
        context.isAudible = true
        var pinned = context
        pinned.isPinned = true

        let everyAction = rows(window(), context).windowControls
            + rows(window(), context).actions
            + rows(window(), pinned).actions
            + [.searchWindowTabs(count: nil)]

        for item in everyAction {
            let name = item.icon.symbolName
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(name) is not a symbol on this system"
            )
        }
    }

    /// The tab count rides in the caption when it is known: it is the one thing a single card cannot
    /// tell you, and it decides whether searching inside the window is worth doing.
    @Test func theTabGlyphCarriesTheCountWhenKnown() {
        #expect(CardMenuItem.searchWindowTabs(count: 23).icon.label == "23 tabs")
        #expect(CardMenuItem.searchWindowTabs(count: 1).icon.label == "1 tab")
        #expect(CardMenuItem.searchWindowTabs(count: nil).icon.label == "Tabs")
    }

    /// Pinning and unpinning are one button whose glyph says which way it will go.
    @Test func pinningAndUnpinningReadDifferently() {
        let pin = CardMenuItem.pinApplication(name: "Google Chrome").icon
        let unpin = CardMenuItem.unpinApplication(name: "Google Chrome").icon
        #expect(pin.symbolName != unpin.symbolName)
        #expect(pin.label == "Pin")
        #expect(unpin.label == "Unpin")
    }

    /// Four tiles that look alike would make the row a guessing game.
    @Test func theFourTilesAreEachDistinct() {
        let symbols = WindowTile.allCases.map { CardMenuItem.tileWindow($0).icon.symbolName }
        #expect(Set(symbols).count == WindowTile.allCases.count)
        let labels = WindowTile.allCases.map { CardMenuItem.tileWindow($0).icon.label }
        #expect(Set(labels).count == WindowTile.allCases.count)
    }
}
