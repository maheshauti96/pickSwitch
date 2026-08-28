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
            hasSearchableTabs: true,
            knownTabCount: 23,
            isAudible: false,
            hasAccessibilityElement: true,
            isMinimized: false
        )
    }

    private func rows(_ entry: WindowEntry, _ context: CardMenu.Context) -> CardMenu.Rows {
        CardMenu.rows(for: entry, context: context)
    }

    // MARK: - Which row an action belongs in

    /// Three groups, because they end up in three places: what a title bar carries goes in one corner,
    /// where the window can be sent goes in the opposite one, and what the window *contains* gets a row
    /// of its own because it needs words.
    @Test func theActionsSplitIntoThreeGroups() {
        var context = browserContext
        context.isAudible = true
        context.isPlayingAudio = true
        let result = rows(window(), context)

        #expect(result.windowControls == [.minimizeWindow, .closeWindow])
        #expect(result.moveResize == WindowTile.moveResize.map(CardMenuItem.tileWindow))
        #expect(result.fillArrange == WindowTile.fillArrange.map(CardMenuItem.tileWindow))
        #expect(result.placement == [.enterFullScreen])
        #expect(result.contents == [.searchWindowTabs(count: 23)])
        #expect(result.media == [.previousTrack, .pausePlayback, .nextTrack])
        #expect(result.actions == [.muteAudible])
    }

    /// Close is last, so it lands furthest into the corner. The pointer is least accurate at the end of
    /// its travel, and the reversible action is the one that should absorb a slightly long throw.
    @Test func closeSitsOutsideMinimize() {
        #expect(rows(window(), browserContext).windowControls.last == .closeWindow)
    }

    /// For a browser, the useful thing is the tab, and the fastest route to a tab is the search the
    /// overlay already has. So it leads its row.
    @Test func aBrowserWindowOffersTabSearchUnderThePreview() {
        #expect(rows(window(), browserContext).contents == [.searchWindowTabs(count: 23)])
        #expect(!rows(window(), browserContext).actions.contains(.searchWindowTabs(count: 23)))
    }

    @Test func theTabCountIsShownWhenKnownAndOmittedWhenNot() {
        #expect(CardMenuItem.searchWindowTabs(count: 23).title == "Search through 23 Tabs")
        #expect(CardMenuItem.searchWindowTabs(count: 1).title == "Search through 1 Tab")
        // Tabs are not fetched until the user types, so the item has to stand without a number.
        #expect(CardMenuItem.searchWindowTabs(count: nil).title == "Search through Tabs")
    }

    // MARK: - What was deliberately taken away

    /// Closing a window is not quitting its application, and the menu offers only the first. Nothing
    /// may quietly reintroduce an action that terminates every window an application has.
    @Test func theMenuNeverOffersToQuitAnApplication() {
        var context = browserContext
        context.isAudible = true
        context.isPlayingAudio = true
        let titles = everyAction(in: rows(window(), context)).map(\.title)
        #expect(!titles.contains { $0.localizedCaseInsensitiveContains("quit") })
    }

    /// Pinning was offered here and removed as not worth the room. It is still reachable in Settings,
    /// so this is a menu decision rather than a lost capability.
    @Test func theMenuNoLongerOffersPinning() {
        var context = browserContext
        context.isAudible = true
        context.isPlayingAudio = true
        let titles = everyAction(in: rows(window(), context)).map(\.title)
        #expect(!titles.contains { $0.localizedCaseInsensitiveContains("pin") })
    }

    /// The two rows match macOS's own window menu: four halves, then fill and the remaining
    /// arrangements, then Full Screen. Move to Display is absent until there is another screen.
    @Test func thePlacementsMatchTheSystemWindowMenu() {
        let result = rows(window(), browserContext)
        let move = result.moveResize.compactMap(Self.tile)
        let fill = result.fillArrange.compactMap(Self.tile)
        #expect(move == WindowTile.moveResize)
        #expect(fill == WindowTile.fillArrange)
        #expect(result.placement == [.enterFullScreen])
    }

    @Test func anotherDisplayIsOfferedAsAMoveTarget() {
        let other = DisplayInfo(
            number: 2,
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            isBuiltIn: false,
            name: "DELL U2720Q"
        )
        var context = browserContext
        context.otherDisplays = [other]
        let result = rows(window(), context)
        #expect(result.placement == [.enterFullScreen, .moveToDisplay(other)])
        #expect(CardMenuItem.moveToDisplay(other).title == "Move to DELL U2720Q")
    }

    /// Full Screen is a Space, not a resizable frame. macOS greys out tiling and Move to Display
    /// there because they cannot act; we omit them and offer Exit Full Screen instead.
    @Test func aFullScreenWindowOffersExitInsteadOfTiling() {
        var context = browserContext
        context.isFullScreen = true
        let other = DisplayInfo(
            number: 2,
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            isBuiltIn: false,
            name: "Built-in Retina Display"
        )
        context.otherDisplays = [other]
        let result = rows(window(), context)
        #expect(result.placement == [.exitFullScreen])
        #expect(result.moveResize.isEmpty)
        #expect(result.fillArrange.isEmpty)
        #expect(result.windowControls.contains(.closeWindow))
        #expect(CardMenuItem.exitFullScreen.title == "Exit Full Screen")
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
        #expect(result.moveResize.isEmpty)
        #expect(result.fillArrange.isEmpty)
        #expect(result.placement.isEmpty)
        // Tab search survives: it never needed Accessibility, only that this is a scriptable browser.
        #expect(result.contents == [.searchWindowTabs(count: 23)])
        #expect(result.actions.isEmpty)
    }

    /// A minimized window's frame is not where it is or how big it looks, so sending it to half a
    /// screen you cannot see it on changes nothing observable.
    @Test func aMinimizedWindowIsNotOfferedTiling() {
        var context = browserContext
        context.isMinimized = true
        let result = rows(window(minimized: true), context)

        #expect(result.moveResize.isEmpty)
        #expect(result.fillArrange.isEmpty)
        #expect(result.placement.isEmpty)
        // Close still applies: a minimized window can be closed from the Dock too.
        #expect(result.windowControls.contains(.closeWindow))
    }

    /// Muting acts on what is playing now. With nothing playing there is nothing to act on, so the
    /// item is absent rather than present and inert.
    @Test func muteAppearsOnlyForAWindowMakingNoise() {
        var quiet = browserContext
        quiet.isAudible = false
        #expect(!rows(window(), quiet).actions.contains(.muteAudible))
        #expect(rows(window(), quiet).media.isEmpty)

        var audible = browserContext
        audible.isAudible = true
        audible.isPlayingAudio = true
        #expect(rows(window(), audible).actions.contains(.muteAudible))
        #expect(rows(window(), audible).media == [.previousTrack, .pausePlayback, .nextTrack])
    }

    /// Previous / pause / next are a media session. A window that is only on the microphone
    /// is audible enough to mute, but it has no track to skip.
    @Test func transportAppearsOnlyWhilePlaying() {
        var microphoneOnly = browserContext
        microphoneOnly.isAudible = true
        microphoneOnly.isPlayingAudio = false
        let silentPlay = rows(window(), microphoneOnly)
        #expect(silentPlay.actions.contains(.muteAudible))
        #expect(silentPlay.media.isEmpty)

        var playing = browserContext
        playing.isAudible = true
        playing.isPlayingAudio = true
        #expect(rows(window(), playing).media == [.previousTrack, .pausePlayback, .nextTrack])
    }

    @Test func aNonBrowserWindowIsNotOfferedTabSearch() {
        var context = browserContext
        context.hasSearchableTabs = false
        let result = rows(window(app: "Warp"), context)
        #expect(result.contents.isEmpty)
        #expect(!result.actions.contains(.searchWindowTabs(count: 23)))
        #expect(!result.actions.contains(.searchWindowTabs(count: nil)))
    }

    /// A consequence of dropping pinning worth stating out loud: with no application-level action left,
    /// a window that offers nothing at all now produces no menu rather than a menu of one useless
    /// entry. An empty frame under the pointer would be worse than nothing happening.
    @Test func aWindowWithNothingAvailableGetsNoMenu() {
        let result = rows(window(app: "Warp"), CardMenu.Context())
        #expect(result.windowControls.isEmpty)
        #expect(result.moveResize.isEmpty)
        #expect(result.fillArrange.isEmpty)
        #expect(result.placement.isEmpty)
        #expect(result.contents.isEmpty)
        #expect(result.media.isEmpty)
        #expect(result.actions.isEmpty)
        #expect(result.isEmpty)
    }

    /// The ordinary case still has a menu: a window on this desktop has an Accessibility element, so it
    /// gets its controls even when there is nothing to say about its contents.
    @Test func anOrdinaryWindowStillGetsItsControls() {
        var context = CardMenu.Context()
        context.hasAccessibilityElement = true
        let result = rows(window(app: "Warp"), context)
        #expect(result.windowControls == [.minimizeWindow, .closeWindow])
        #expect(result.moveResize.count == 4)
        #expect(result.fillArrange.count == 4)
        #expect(result.placement == [.enterFullScreen])
        #expect(result.contents.isEmpty)
        #expect(result.actions.isEmpty)
        #expect(!result.isEmpty)
    }

    // MARK: - Glyphs

    /// Pause / next stay in the open menu so they can be used as a player. Tiling
    /// and close still dismiss, because those actions tear the overlay down.
    @Test func mediaControlsKeepTheMenuOpen() {
        #expect(CardMenuItem.pausePlayback.keepsMenuOpen)
        #expect(CardMenuItem.nextTrack.keepsMenuOpen)
        #expect(CardMenuItem.previousTrack.keepsMenuOpen)
        #expect(!CardMenuItem.tileWindow(.leftHalf).keepsMenuOpen)
        #expect(!CardMenuItem.closeWindow.keepsMenuOpen)
        #expect(CardMenuItem.pausePlayback.title == "Play/Pause")
    }

    /// A glyph alone makes the user guess, so each carries a word and a symbol.
    @Test func everyActionHasAGlyphAndAName() {
        var context = browserContext
        context.isAudible = true
        context.isPlayingAudio = true
        for item in everyAction(in: rows(window(), context)) {
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
        context.isPlayingAudio = true
        let extra: [CardMenuItem] = [
            .searchWindowTabs(count: nil),
            .enterFullScreen,
            .exitFullScreen,
            .moveToDisplay(DisplayInfo(
                number: 1, bounds: .zero, isBuiltIn: true, name: "Built-in Retina Display"
            )),
        ]
        for item in everyAction(in: rows(window(), context)) + extra {
            let name = item.icon.symbolName
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(name) is not a symbol on this system"
            )
        }
    }

    /// Closing is the only irreversible action here, and the only one coloured to say so. Minimizing
    /// is undone from the Dock and tiling by dragging, but a closed window with unsaved work is gone.
    @Test func onlyClosingIsMarkedDestructive() {
        var context = browserContext
        context.isAudible = true
        context.isPlayingAudio = true
        let destructive = everyAction(in: rows(window(), context)).filter(\.isDestructive)
        #expect(destructive == [.closeWindow])
    }

    /// The tab count rides in the caption when it is known: it is the one thing a single card cannot
    /// tell you, and it decides whether searching inside the window is worth doing.
    @Test func theTabGlyphCarriesTheCountWhenKnown() {
        #expect(CardMenuItem.searchWindowTabs(count: 23).icon.label == "23 tabs")
        #expect(CardMenuItem.searchWindowTabs(count: 1).icon.label == "1 tab")
        #expect(CardMenuItem.searchWindowTabs(count: nil).icon.label == "Tabs")
    }

    /// Two tiles that looked alike would make the row a guessing game.
    @Test func theTilesAreDistinct() {
        let symbols = WindowTile.allCases.map { CardMenuItem.tileWindow($0).icon.symbolName }
        #expect(Set(symbols).count == WindowTile.allCases.count)
        let labels = WindowTile.allCases.map { CardMenuItem.tileWindow($0).icon.label }
        #expect(Set(labels).count == WindowTile.allCases.count)
    }

    private func everyAction(in rows: CardMenu.Rows) -> [CardMenuItem] {
        rows.windowControls
            + rows.contents
            + rows.media
            + rows.moveResize
            + rows.fillArrange
            + rows.placement
            + rows.actions
    }

    private static func tile(_ item: CardMenuItem) -> WindowTile? {
        if case .tileWindow(let tile) = item { return tile }
        return nil
    }
}
