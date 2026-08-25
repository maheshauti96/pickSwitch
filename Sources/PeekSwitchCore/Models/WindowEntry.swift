import AppKit
import ApplicationServices
import CoreGraphics

/// One individual open window (Requirement 1.1, 1.3).
///
/// Deliberately a struct with a value-typed identity (`windowID`) so the strip can
/// diff cheaply, plus an escape hatch to the live `axElement` for activation.
/// `axElement` is not part of equality: the same window keeps its identity across
/// re-enumeration even though AX handn't guaranteed to hand back an identical
/// element reference.
struct WindowEntry: Identifiable {

    /// CGWindowID. Stable for the lifetime of the window and the shared vocabulary
    /// between Accessibility, CGWindowList and ScreenCaptureKit.
    let windowID: CGWindowID
    let processID: pid_t
    let applicationName: String
    let applicationIcon: NSImage?
    /// Stable identity for the owning application, for settings that name applications.
    /// `nil` for the rare process that has no bundle.
    var bundleIdentifier: String?
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    /// Front-to-back position in the system window list at enumeration time.
    /// `0` is frontmost. Used to seed MRU order for windows this session has never
    /// seen activate (Requirement 2.6).
    let zOrder: Int
    let axElement: AXUIElement?

    /// Whether this window is on the desktop the user is looking at right now.
    ///
    /// True only for windows Accessibility returned this time round, which is precisely the
    /// active Space. Used to decide whether geometry can be trusted for on-screen effects: a
    /// window on another Space has a frame in the same coordinate space, but switching to it
    /// changes desktop, so animating anything to that rectangle would be nonsense.
    var isOnActiveSpace: Bool = false

    /// When PeekSwitch last saw this window on the active Space, if ever.
    ///
    /// Distinct from "used": a window can be seen without being switched to. It exists
    /// because Accessibility only reports the active Space, so a window sitting on another
    /// desktop has no focus history from this session and would otherwise be ordered by its
    /// position in the window server's all-Spaces list — which is arbitrary. When you last
    /// had it in front of you is a far better answer than that.
    var lastSeenOnActiveSpace: TimeInterval?

    /// Set when this entry is a browser tab rather than a window.
    ///
    /// A tab is reached through its browser's scripting interface, so it has no
    /// `CGWindowID`, Accessibility element or z-order.
    private(set) var tab: BrowserTab?

    /// Set when search is offering an installed application that has no matching window.
    ///
    /// Its bundle URL is the thing activation opens. Keeping this distinct from both windows
    /// and tabs makes every window-only operation opt in through `isWindow` rather than
    /// accidentally accepting a synthetic entry because it happens not to be a tab.
    private(set) var launchableApplication: LaunchableApplication?

    /// Set when search is offering to take the query to the web.
    ///
    /// Web search used to be reachable only from the empty state: type something that matches
    /// nothing, and Return would offer it. That left a real gap. Typing "grok" with Grok Bot
    /// installed matched the application, so the offer never appeared and there was no way to
    /// search for the word — the presence of one local match removed the option entirely, which is
    /// not what "no matches" was supposed to mean.
    ///
    /// Making it an entry rather than another special case is what fixes that: it sits at the end of
    /// the results, it is selected and confirmed like anything else, and every arrangement already
    /// knows how to draw a list of entries. The empty state keeps its own prompt, because with
    /// nothing else on screen a full sentence reads better than a lone card.
    private(set) var webSearch: WebSearchTarget?

    /// A `CGWindowID` is not unique across tabs, and launchable applications have no window id
    /// at all, so each target kind owns a stable namespace. Application takes precedence in the
    /// impossible malformed case where both optional payloads are supplied, matching activation.
    var id: String {
        if let webSearch { return "web:\(webSearch.kind):\(webSearch.query)" }
        if let launchableApplication { return "application:\(launchableApplication.id)" }
        if let tab { return "tab:\(tab.identity)" }
        return "window:\(windowID)"
    }

    var isWebSearch: Bool { webSearch != nil }
    var isApplication: Bool { webSearch == nil && launchableApplication != nil }
    var isTab: Bool { webSearch == nil && launchableApplication == nil && tab != nil }
    var isWindow: Bool { webSearch == nil && tab == nil && launchableApplication == nil }

    /// What a card shows where it names the *source* of an entry rather than the entry itself.
    ///
    /// For a window that is the application, which is the useful answer. For a tab it is the site,
    /// because the application is not: every tab in a search shares one browser name, so a list of
    /// them read as fifteen results all called "Google Chrome" with nothing to tell them apart.
    /// "x.com" identifies a result; the browser it happens to live in does not.
    ///
    /// Deliberately separate from `applicationName`, which still names the browser. That value is
    /// what groups windows per application, what search matches against, and what the tint is keyed
    /// on, and none of those should start treating one browser as many applications.
    var sourceLabel: String {
        if let webSearch { return webSearch.sourceLabel }
        if let tab, !tab.host.isEmpty { return tab.host }
        return applicationName
    }

    /// What the card shows on its title line. Some windows genuinely have no
    /// title (utility panels, freshly opened documents).
    var displayTitle: String {
        if let webSearch { return webSearch.query }
        if let tab {
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? tab.host : title
        }
        if isApplication { return "Open application" }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? applicationName : title
    }

    /// A tab entry for `tab`, borrowing its browser's name and icon.
    static func tabEntry(_ tab: BrowserTab, application: NSRunningApplication?) -> WindowEntry {
        WindowEntry(
            windowID: 0,
            processID: application?.processIdentifier ?? 0,
            applicationName: application?.localizedName ?? tab.browser.scriptingName,
            applicationIcon: application?.icon,
            bundleIdentifier: tab.browser.bundleIdentifier,
            title: tab.title,
            frame: .zero,
            isMinimized: false,
            zOrder: Int.max,
            axElement: nil,
            tab: tab,
            launchableApplication: nil
        )
    }

    /// A selectable result that takes the query to the web.
    ///
    /// Named from the destination rather than generically, because "Search the web" and "Go to
    /// grok.com" are different promises and the query alone does not say which one Return will keep.
    static func webSearchEntry(_ target: WebSearchTarget) -> WindowEntry {
        WindowEntry(
            windowID: 0,
            processID: 0,
            // Never a real application name. This value is the key for per-application window
            // counts, for grouping and for icon tints, and a synthetic result must not join any of
            // those — a web search is not a fourth window of some application.
            applicationName: target.sourceLabel,
            applicationIcon: target.icon,
            title: target.query,
            frame: .zero,
            isMinimized: false,
            zOrder: Int.max,
            axElement: nil,
            tab: nil,
            launchableApplication: nil,
            webSearch: target
        )
    }

    /// A selectable result that opens an installed application instead of raising a window.
    static func applicationEntry(_ application: LaunchableApplication) -> WindowEntry {
        WindowEntry(
            windowID: 0,
            processID: 0,
            applicationName: application.name,
            applicationIcon: application.icon,
            bundleIdentifier: application.bundleIdentifier,
            title: "",
            frame: .zero,
            isMinimized: false,
            zOrder: Int.max,
            axElement: nil,
            tab: nil,
            launchableApplication: application
        )
    }
}

extension WindowEntry: Equatable {
    static func == (lhs: WindowEntry, rhs: WindowEntry) -> Bool {
        lhs.windowID == rhs.windowID
            && lhs.title == rhs.title
            && lhs.isMinimized == rhs.isMinimized
            && lhs.frame == rhs.frame
            && lhs.zOrder == rhs.zOrder
            && lhs.tab == rhs.tab
            && lhs.launchableApplication == rhs.launchableApplication
            && lhs.webSearch == rhs.webSearch
    }
}

/// A web search offered as a selectable result.
struct WebSearchTarget: Equatable {

    /// Exactly what the user typed, which is what the result shows and what the destination encodes.
    let query: String
    let destination: WebSearch.Destination

    /// Which of the two offers this is, for the entry's identity.
    ///
    /// One query can produce both — go to the address, or search for it — and they are two results
    /// that must not share an id. Two entries with one id is not a cosmetic problem: the list is
    /// diffed by id, so the second would replace the first and only one option would ever appear.
    var kind: String {
        switch destination {
        case .address: return "address"
        case .search: return "search"
        }
    }

    /// The line naming what confirming this will do.
    ///
    /// Distinguishes the two destinations, because they are different promises: one opens a site the
    /// user named, the other asks a search engine about a phrase. A single label for both would make
    /// Return unpredictable in the one place where the switcher leaves the machine entirely.
    var sourceLabel: String {
        switch destination {
        case .address(let url): return url.host.map { "Go to \($0)" } ?? "Go to site"
        case .search: return "Search the web"
        }
    }

    /// A template symbol, so it takes the palette's own text colour in either theme rather than
    /// carrying a fixed one that would be wrong in one of them.
    var icon: NSImage? {
        let name: String
        switch destination {
        case .address: name = "arrow.up.forward.square"
        case .search: name = "magnifyingglass"
        }
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: sourceLabel
        ) else { return nil }

        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)
        ) ?? symbol
        configured.isTemplate = true
        return configured
    }
}
