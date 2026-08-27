import CoreGraphics
import Foundation

/// The facts shown above a card's context menu, and — as with `HubSummary` — which ones are left out.
///
/// The menu asks a different question from the hub, so it earns more detail than the hub allows. By
/// the time a menu is open the user has already found the window; what they need now is enough to
/// decide what to *do* to it. "Another desktop" changes whether closing it is a good idea. A tab count
/// changes whether searching inside it is worth doing. The window's pixel size, which `HubSummary`
/// deliberately refuses because it decides nothing about switching, does decide something here: it is
/// how you tell two windows of one application apart when their titles are similar.
///
/// Still bounded, and for a concrete reason: the menu is a fixed width. Every row competes with the
/// thumbnail and the title for vertical space, so a fact that is true of *every* window earns nothing
/// — it adds a line to every menu and distinguishes none of them.
struct CardDetails: Equatable {

    /// One fact, as a short label and its value. Split so the view can align them into a column
    /// rather than running them together into a sentence that wraps unpredictably.
    struct Row: Equatable {
        let label: String
        let value: String
    }

    /// The window's own title, which is the heading.
    let title: String

    /// What the window belongs to: the application, or the site for a browser window.
    let source: String

    let rows: [Row]

    /// Which screen the window is on, shown as a coloured chip rather than a row.
    ///
    /// It was a row saying "Screen 1" and earned no line: a label spelling out a number carries the
    /// same fact as a chip in the corner while costing a full row of the height the preview needs. As
    /// a chip it is also comparable at a glance — the colour is per screen, so two menus opened on two
    /// windows say "same screen" or "different screens" without either number being read.
    let displayNumber: Int?

    /// - Parameters:
    ///   - siteHost: the active site, already checked against private browsing by the caller.
    ///   - displayNumber: the screen the window is on, for the chip.
    ///   - tabCount: tabs known to be in this window, or `nil` before they have been fetched.
    ///   - windowPosition: which of its application's windows this is, and how many there are.
    ///   - now: the clock `WindowEntry.lastSeenOnActiveSpace` is stamped from, passed in so the
    ///     wording is testable without waiting.
    static func make(
        entry: WindowEntry,
        siteHost: String?,
        displayNumber: Int?,
        tabCount: Int?,
        windowPosition: (index: Int, count: Int)?,
        isIncognito: Bool,
        isPlayingAudio: Bool,
        isUsingMicrophone: Bool,
        now: TimeInterval
    ) -> CardDetails {
        var rows: [Row] = []

        // Leads, because it is the only fact here that changes what selecting the window *does*
        // rather than describing what it is.
        if entry.isWindow, !entry.isOnActiveSpace {
            let age = entry.lastSeenOnActiveSpace.map { seen -> String in
                let elapsed = now - seen
                return elapsed >= 0 ? HubSummary.relativeAge(elapsed) : "unknown"
            }
            rows.append(Row(label: "Desktop", value: age.map { "Another · \($0)" } ?? "Another"))
        }

        if entry.isMinimized {
            rows.append(Row(label: "State", value: "Minimized"))
        }

        // Only for a browser that has actually answered. A count of zero would read as "this window
        // has no tabs", which is never true of a browser window and would be the fetch not having
        // happened.
        if let tabCount, tabCount > 0 {
            rows.append(Row(label: "Tabs", value: tabCount == 1 ? "1 tab" : "\(tabCount) tabs"))
        }

        if isIncognito {
            rows.append(Row(label: "Session", value: "Private window"))
        }

        // Combined into one row rather than two: they are the same kind of fact, they are shown
        // together on the card already, and two rows for one condition crowds a fixed-width menu.
        switch (isPlayingAudio, isUsingMicrophone) {
        case (true, true): rows.append(Row(label: "Audio", value: "Playing · microphone"))
        case (true, false): rows.append(Row(label: "Audio", value: "Playing"))
        case (false, true): rows.append(Row(label: "Audio", value: "Microphone in use"))
        case (false, false): break
        }

        if let windowPosition, windowPosition.count > 1 {
            rows.append(
                Row(
                    label: "Window",
                    value: "\(windowPosition.index) of \(windowPosition.count)"
                )
            )
        }

        // No pixel size. It was here on the argument that two windows of one application are told
        // apart by their size — and the preview above these rows now does that far better than
        // "1512 × 950" ever did, which leaves the row restating what the picture already shows.
        // `HubSummary` refused this fact outright; the reason it was an exception here is gone.

        let source: String = {
            if let siteHost, !siteHost.isEmpty, siteHost != entry.applicationName {
                // Both, because the site says which window and the application says which app to
                // expect when it comes forward.
                return "\(siteHost) · \(entry.applicationName)"
            }
            return entry.applicationName
        }()

        return CardDetails(
            title: entry.displayTitle,
            source: source,
            rows: rows,
            // Only a real window sits on a screen. A tab's screen is its browser's, so a chip on a tab
            // would be describing something other than the thing the menu is about.
            displayNumber: entry.isWindow ? displayNumber : nil
        )
    }
}
