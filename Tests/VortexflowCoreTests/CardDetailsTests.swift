import CoreGraphics
import Foundation
import Testing
@testable import VortexflowCore

/// Which facts appear above a card's context menu, and which are withheld.
///
/// The menu is a fixed width, so every row competes with the thumbnail and the title for vertical
/// space. A fact that is true of every window costs a line on every menu and distinguishes none of
/// them, which is the test most of these are really making.
struct CardDetailsTests {

    private static let now: TimeInterval = 1_000_000

    private func window(
        app: String = "Google Chrome",
        title: String = "A window",
        frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
        onActiveSpace: Bool = true,
        minimized: Bool = false,
        lastSeen: TimeInterval? = nil
    ) -> WindowEntry {
        var entry = Fixture.entry(id: 169, app: app, title: title, minimized: minimized, frame: frame)
        entry.isOnActiveSpace = onActiveSpace
        entry.lastSeenOnActiveSpace = lastSeen
        return entry
    }

    private func details(
        for entry: WindowEntry,
        siteHost: String? = nil,
        tabCount: Int? = nil,
        windowPosition: (index: Int, count: Int)? = nil,
        isIncognito: Bool = false,
        isPlayingAudio: Bool = false,
        isUsingMicrophone: Bool = false
    ) -> CardDetails {
        CardDetails.make(
            entry: entry,
            siteHost: siteHost,
            tabCount: tabCount,
            windowPosition: windowPosition,
            isIncognito: isIncognito,
            isPlayingAudio: isPlayingAudio,
            isUsingMicrophone: isUsingMicrophone,
            now: Self.now
        )
    }

    private func value(_ label: String, in details: CardDetails) -> String? {
        details.rows.first { $0.label == label }?.value
    }

    // MARK: - The plain case

    /// A window on this desktop with nothing playing earns no rows at all. The preview and the title
    /// say everything there is to say about it, and a row that appears on every menu distinguishes
    /// nothing while costing the height the preview needs.
    @Test func anUnremarkableWindowShowsNoRowsAtAll() {
        let result = details(for: window())
        #expect(result.rows.isEmpty)
    }

    /// The window's pixel size was a row and is not any more: the preview above these rows tells two
    /// windows of one application apart far better than "1920 × 1080" did.
    @Test func thePixelSizeIsNeverARow() {
        let result = details(for: window(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)))
        #expect(value("Size", in: result) == nil)
    }

    /// The screen is not a fact. It used to be a coloured chip, and before that a row, and both
    /// spent height on a number the menu does not act on.
    @Test func theScreenIsNotMentioned() {
        let result = details(for: window())
        #expect(value("Screen", in: result) == nil)
        #expect(value("Display", in: result) == nil)
    }

    @Test func theTitleAndSourceAreAlwaysPresent() {
        let result = details(for: window(title: "Quarterly plan"))
        #expect(result.title == "Quarterly plan")
        #expect(result.source == "Google Chrome")
        #expect(result.applicationName == "Google Chrome")
    }

    /// A browser window is identified by its site, but the application is kept too: the site says
    /// which window, the application says what will come forward.
    @Test func aBrowserWindowNamesBothSiteAndApplication() {
        let result = details(for: window(), siteHost: "github.com")
        #expect(result.source == "github.com · Google Chrome")
    }

    /// A site host equal to the application name would print it twice.
    @Test func aRedundantSiteHostIsNotRepeated() {
        let result = details(for: window(app: "zoom.us"), siteHost: "zoom.us")
        #expect(result.source == "zoom.us")
    }

    // MARK: - What earns a row

    /// Leads, because it is the only fact that changes what selecting the window does rather than
    /// describing what it is.
    @Test func anotherDesktopLeadsAndCarriesItsAge() {
        let result = details(
            for: window(onActiveSpace: false, lastSeen: Self.now - 1_200)
        )
        #expect(result.rows.first?.label == "Desktop")
        #expect(value("Desktop", in: result) == "Another · 20m ago")
    }

    /// A window on another desktop this session has never seen has no age to report, and must not
    /// invent one.
    @Test func anotherDesktopWithNoHistorySaysOnlyThat() {
        let result = details(for: window(onActiveSpace: false, lastSeen: nil))
        #expect(value("Desktop", in: result) == "Another")
    }

    @Test func tabsAreCountedWhenKnown() {
        #expect(value("Tabs", in: details(for: window(), tabCount: 23)) == "23 tabs")
        #expect(value("Tabs", in: details(for: window(), tabCount: 1)) == "1 tab")
    }

    /// Nothing before the tabs have been fetched, and nothing for a count of zero — which is never
    /// true of a browser window and really means the fetch has not happened.
    @Test func anUnknownOrZeroTabCountIsNotShown() {
        #expect(value("Tabs", in: details(for: window(), tabCount: nil)) == nil)
        #expect(value("Tabs", in: details(for: window(), tabCount: 0)) == nil)
    }

    /// One row for both, because they are the same kind of fact and two rows for one condition
    /// crowds a fixed-width menu.
    @Test func audioAndMicrophoneShareOneRow() {
        #expect(value("Audio", in: details(for: window(), isPlayingAudio: true)) == "Playing")
        #expect(
            value("Audio", in: details(for: window(), isUsingMicrophone: true)) == "Microphone in use"
        )
        #expect(
            value(
                "Audio",
                in: details(for: window(), isPlayingAudio: true, isUsingMicrophone: true)
            ) == "Playing · microphone"
        )
        #expect(value("Audio", in: details(for: window())) == nil)
    }

    @Test func theWindowPositionAppearsOnlyWithSiblings() {
        #expect(
            value("Window", in: details(for: window(), windowPosition: (2, 3))) == "2 of 3"
        )
        // A lone window's "1 of 1" says nothing.
        #expect(value("Window", in: details(for: window(), windowPosition: (1, 1))) == nil)
        #expect(value("Window", in: details(for: window(), windowPosition: nil)) == nil)
    }

    @Test func aPrivateWindowSaysSo() {
        #expect(value("Session", in: details(for: window(), isIncognito: true)) == "Private window")
        #expect(value("Session", in: details(for: window())) == nil)
    }

    // MARK: - Geometry that describes nothing

    /// A minimized window's frame is not where it is or how big it looks, so the size is dropped and
    /// the state is stated instead.
    @Test func aMinimizedWindowReportsItsStateNotItsSize() {
        let result = details(for: window(minimized: true))
        #expect(value("State", in: result) == "Minimized")
        #expect(value("Size", in: result) == nil)
    }

    @Test func aDegenerateFrameIsNotReportedAsASize() {
        let result = details(for: window(frame: CGRect(x: 0, y: 0, width: 0, height: 0)))
        #expect(value("Size", in: result) == nil)
    }

    // MARK: - Non-windows

    /// A tab has no desktop, no geometry and no screen of its own; every one of those rows would be
    /// a statement about its browser rather than about it.
    @Test func aTabGetsNoWindowGeometry() {
        let tab = WindowEntry.tabEntry(
            BrowserTab(
                browser: .chrome, windowIdentifier: 1, tabIndex: 2,
                title: "ChatGPT", url: "https://chatgpt.com/"
            ),
            application: nil
        )
        let result = details(for: tab)
        #expect(value("Size", in: result) == nil)
        #expect(value("Desktop", in: result) == nil)
    }

    /// Ordering is part of the design: the fact that changes the decision comes first, and the merely
    /// descriptive ones follow.
    @Test func rowsAreOrderedFromConsequentialToDescriptive() {
        let result = details(
            for: window(onActiveSpace: false, lastSeen: Self.now - 60),
            tabCount: 12,
            windowPosition: (2, 3),
            isPlayingAudio: true
        )
        #expect(
            result.rows.map(\CardDetails.Row.label)
                == ["Desktop", "Tabs", "Audio", "Window"]
        )
    }
}
