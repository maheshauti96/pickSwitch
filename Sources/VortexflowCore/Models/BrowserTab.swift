import AppKit
import Foundation

/// One open browser tab, as a thing the user can switch to.
///
/// Tabs are not windows, and Vortexflow's whole enumeration path is built on windows —
/// CGWindowIDs, Accessibility elements, z-order. A tab has none of those. It is
/// addressable only through the browser's own scripting interface, by the browser's
/// internal window identifier plus a position in that window's tab list.
struct BrowserTab: Equatable, Hashable, Sendable {

    /// Which browser owns it, so the right scripting dictionary is used.
    let browser: Browser
    /// The browser's own window id, not a `CGWindowID`. Only meaningful to that browser.
    let windowIdentifier: Int
    /// 1-based, matching AppleScript's indexing.
    let tabIndex: Int
    let title: String
    let url: String

    /// Windows that share an on-screen frame, used by Terminal's macOS window-tabbing.
    ///
    /// Terminal's AppleScript `tabs of window` are sessions inside one window. The pills in
    /// the title bar are often *other windows* merged by the system, each with one session,
    /// and they share a rectangle. A scope keyed only on `windowIdentifier` would list the
    /// session in the front window and miss its neighbours. Tabs with the same `groupKey`
    /// are one visual tab bar.
    let groupKey: String?

    /// Whether the icon of this tab's site may be fetched over the network.
    ///
    /// True only when the tab's window reported the browser's exact `normal` mode. It fails
    /// closed, and the default is `false`, because the cost of getting this wrong is asymmetric:
    /// requesting an icon for a private tab would put a private destination on the network, and no
    /// icon is a far smaller loss than that.
    let allowsFaviconRequest: Bool

    init(
        browser: Browser,
        windowIdentifier: Int,
        tabIndex: Int,
        title: String,
        url: String,
        allowsFaviconRequest: Bool = false,
        groupKey: String? = nil
    ) {
        self.browser = browser
        self.windowIdentifier = windowIdentifier
        self.tabIndex = tabIndex
        self.title = title
        self.url = url
        self.allowsFaviconRequest = allowsFaviconRequest
        self.groupKey = groupKey
    }

    /// Stable within a presentation, which is all the UI needs to key a card by.
    var identity: String {
        "\(browser.bundleIdentifier):\(windowIdentifier):\(tabIndex)"
    }

    /// The bit of the URL worth reading on a card: "grok.com" rather than the full
    /// query-string-laden address.
    var host: String { Self.host(ofURL: url) }

    /// The readable host of any page address.
    ///
    /// Shared with browser *windows*, whose active tab address arrives from a different place
    /// entirely — the window record rather than a tab listing. Stripping `www.` in two places
    /// would eventually mean one of them stopping, and a window reading `www.github.com` beside a
    /// tab reading `github.com` looks like two different sites.
    static func host(ofURL url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Applications whose tabs can be listed and selected through their own scripting interface.
    ///
    /// Chromium-derived browsers share Chrome's scripting terminology (`title of tabs`,
    /// `active tab index`); Safari uses its own (`name of tabs`, `current tab`); Terminal
    /// uses `custom title` / `tty` and `selected`. Anything not on this list is simply not
    /// searched — there is no generic way to ask an arbitrary application for its tabs.
    ///
    /// Membership is checked against the application's own scripting dictionary rather than
    /// assumed from a family. Being built on Chromium does not guarantee the terms survive:
    /// an application can ship with scripting stripped out entirely, and then every query
    /// fails silently at runtime. Comet was added after confirming its dictionary declares
    /// `mode`, `active tab`, `active tab index`, `title` and `URL`. Terminal was added after
    /// confirming `tabs`, `custom title`, `tty` and `selected`.
    enum Browser: String, CaseIterable, Sendable {
        case chrome
        case safari
        case edge
        case brave
        case chromium
        case arc
        case comet
        case terminal

        var bundleIdentifier: String {
            switch self {
            case .chrome: return "com.google.Chrome"
            case .safari: return "com.apple.Safari"
            case .edge: return "com.microsoft.edgemac"
            case .brave: return "com.brave.Browser"
            case .chromium: return "org.chromium.Chromium"
            case .arc: return "company.thebrowser.Browser"
            case .comet: return "ai.perplexity.comet"
            case .terminal: return "com.apple.Terminal"
            }
        }

        /// The name AppleScript addresses the application by.
        var scriptingName: String {
            switch self {
            case .chrome: return "Google Chrome"
            case .safari: return "Safari"
            case .edge: return "Microsoft Edge"
            case .brave: return "Brave Browser"
            case .chromium: return "Chromium"
            case .arc: return "Arc"
            case .comet: return "Comet"
            case .terminal: return "Terminal"
            }
        }

        /// Safari names a tab's title `name`; Chromium calls it `title`; Terminal has no
        /// `name` on a tab and uses `custom title`, falling back to `tty`.
        var titleProperty: String {
            switch self {
            case .safari: return "name"
            case .terminal: return "custom title"
            default: return "title"
            }
        }

        /// Safari has no `active tab index`; the tab is selected by setting `current tab`.
        var usesCurrentTab: Bool { self == .safari }

        /// Terminal selects a tab by setting `selected` on that tab, not an index on the window.
        var usesSelectedTab: Bool { self == .terminal }

        /// Whether tabs have a URL that can be listed in bulk. Terminal tabs do not, and asking
        /// for `URL of tabs` fails the whole script rather than that one field.
        var hasTabURLs: Bool { self != .terminal }

        /// Whether a window will say if it is a private one.
        ///
        /// Chromium exposes `mode` per window, reading "normal" or "incognito". Safari's
        /// dictionary has no equivalent, so a Safari private window cannot be told apart from an
        /// ordinary one and is left unbadged rather than guessed at. Terminal has no browsing
        /// mode at all.
        var reportsWindowMode: Bool { self != .safari && self != .terminal }

        /// Whether this application's windows are queried so a card can be tied to the
        /// scripting id its tab list is numbered by. Chromium needs that for incognito and
        /// for tab scope; Terminal needs it only for tab scope.
        var needsWindowInspection: Bool { reportsWindowMode || self == .terminal }
    }
}
