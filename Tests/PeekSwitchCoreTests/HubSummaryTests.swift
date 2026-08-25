import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import PeekSwitchCore

/// What the spiral's middle says, and more importantly what it declines to say.
///
/// The hub is about 192 points across and every fact added costs characters of the window title, so
/// the omission rules are the substance here rather than the formatting. Each one below exists
/// because saying the thing would have been actively worse than staying quiet.
@Suite("Hub summary")
struct HubSummaryTests {

    private static let now: TimeInterval = 1_000_000

    private func window(
        id: CGWindowID = 1,
        app: String = "Google Chrome",
        title: String = "A window",
        onActiveSpace: Bool = true,
        seenAgo: TimeInterval? = nil
    ) -> WindowEntry {
        var entry = Fixture.entry(id: id, app: app, title: title)
        entry.isOnActiveSpace = onActiveSpace
        if let seenAgo { entry.lastSeenOnActiveSpace = Self.now - seenAgo }
        return entry
    }

    private func summary(
        _ entry: WindowEntry,
        siteHost: String? = nil,
        index: Int? = nil,
        count: Int? = nil
    ) -> HubSummary {
        HubSummary.make(
            entry: entry,
            siteHost: siteHost,
            windowIndex: index,
            windowCount: count,
            now: Self.now
        )
    }

    // MARK: - The source line

    /// A site always earns the line: nothing else on screen spells it out, and a Chrome window whose
    /// title never mentions GitHub is identified by the host and not at all by the browser's name.
    @Test("a site and a position read together")
    func siteAndPosition() {
        let result = summary(window(), siteHost: "github.com", index: 2, count: 3)
        #expect(result.sourceLine == "github.com · 2 of 3")
    }

    @Test("a site alone is enough")
    func siteAlone() {
        #expect(summary(window(), siteHost: "github.com").sourceLine == "github.com")
    }

    /// The application's name appears only when it is qualifying something.
    @Test("an application name earns the line once it is qualified by a position")
    func applicationNameWithPosition() {
        let result = summary(window(app: "Warp"), index: 2, count: 3)
        #expect(result.sourceLine == "Warp · 2 of 3")
    }

    /// The rule the hub was built on: the wedge under the pointer is already tinted, outlined,
    /// labelled with the application's name and showing its icon, and most titles end in it too.
    /// Repeating it a fifth time in the one place with room for the title is a straight loss.
    @Test("an application name alone does not earn the line")
    func applicationNameAloneIsOmitted() {
        #expect(summary(window(app: "Warp")).sourceLine == nil)
    }

    @Test("a single-window application reports no position")
    func singleWindowHasNoPosition() {
        #expect(summary(window(), index: 1, count: 1).position == nil)
    }

    /// Defends against a count and an index that disagree, which would otherwise render as
    /// something like "4 of 3".
    @Test("an out-of-range position is dropped", arguments: [(0, 3), (4, 3), (-1, 3)])
    func outOfRangePositionIsDropped(index: Int, count: Int) {
        #expect(summary(window(), index: index, count: count).position == nil)
    }

    // MARK: - The status line

    /// The unremarkable case says nothing at all.
    @Test("a window on this desktop has no status line")
    func onThisDesktopIsSilent() {
        let result = summary(window(onActiveSpace: true))
        #expect(result.isOnAnotherDesktop == false)
        #expect(result.statusLine() == nil)
    }

    @Test("a window on another desktop says so, with its age")
    func anotherDesktopWithAge() {
        let result = summary(window(onActiveSpace: false, seenAgo: 20 * 60))
        #expect(result.statusLine() == "Another desktop · 20m ago")
    }

    /// A window on another Space that this session has never seen has no stamp to report, and the
    /// warning is worth giving without one.
    @Test("a window on another desktop with no history still warns")
    func anotherDesktopWithoutHistory() {
        #expect(summary(window(onActiveSpace: false)).statusLine() == "Another desktop")
    }

    /// The rule that makes recency worth showing at all. Every window on the active Space is stamped
    /// with a single `seenAt` when the list is built, so an age would read "just now" on all of them
    /// at once — true, and worth nothing, repeated on every selection. It is only information off the
    /// active Space, where the stamp is the remembered one from when that desktop was last in front.
    @Test("recency is not reported for a window on this desktop, however it is stamped")
    func recencyIsSuppressedOnThisDesktop() {
        let result = summary(window(onActiveSpace: true, seenAgo: 0))
        #expect(result.lastSeen == nil)
        #expect(result.statusLine() == nil)
    }

    /// A stamp from the future means the clock moved, not that the window is about to be used.
    @Test("a stamp in the future is ignored rather than rendered")
    func futureStampIsIgnored() {
        #expect(summary(window(onActiveSpace: false, seenAgo: -500)).lastSeen == nil)
    }

    /// Only a real window belongs to a desktop: a tab is reached through its browser, and an
    /// installed application has no window to be anywhere.
    @Test("a tab never claims to be on another desktop")
    func tabIsNeverElsewhere() {
        let tab = BrowserTab(
            browser: .chrome,
            windowIdentifier: 1,
            tabIndex: 0,
            title: "Inbox",
            url: "https://mail.google.com/"
        )
        let entry = WindowEntry.tabEntry(tab, application: nil)
        #expect(summary(entry).isOnAnotherDesktop == false)
    }

    @Test("an installed application never claims to be on another desktop")
    func applicationIsNeverElsewhere() {
        let entry = WindowEntry.applicationEntry(
            LaunchableApplication(
                name: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
                icon: nil
            )
        )
        #expect(summary(entry).isOnAnotherDesktop == false)
        #expect(summary(entry).position == nil)
    }

    // MARK: - Ages

    /// Boundaries rather than midpoints: the interesting failures are all off-by-one at a unit
    /// change, where "60m ago" should already have become "1h ago".
    @Test("ages round down into the widest unit that still says something", arguments: [
        (0.0, "just now"),
        (59.0, "just now"),
        (60.0, "1m ago"),
        (3599.0, "59m ago"),
        (3600.0, "1h ago"),
        (86_399.0, "23h ago"),
        (86_400.0, "1d ago"),
        (259_200.0, "3d ago")
    ])
    func relativeAges(seconds: TimeInterval, expected: String) {
        #expect(HubSummary.relativeAge(seconds) == expected)
    }
}

extension HubSummaryTests {

    /// At its smallest the hub is about 124 points across and the full phrase truncates mid-token to
    /// something like "Another desktop · 2…". The warning is the half worth keeping.
    @Test("a scaled-down arrangement keeps the warning and drops the age")
    func scaledDownStatusDropsTheAge() {
        let result = summary(window(onActiveSpace: false, seenAgo: 20 * 60))
        #expect(result.statusLine(includingAge: true) == "Another desktop · 20m ago")
        #expect(result.statusLine(includingAge: false) == "Another desktop")
    }

    /// Dropping the age must not invent a line for a window that needs none.
    @Test("a window on this desktop stays silent at every size")
    func scaledDownStaysSilentOnThisDesktop() {
        let result = summary(window(onActiveSpace: true, seenAgo: 20 * 60))
        #expect(result.statusLine(includingAge: true) == nil)
        #expect(result.statusLine(includingAge: false) == nil)
    }
}
