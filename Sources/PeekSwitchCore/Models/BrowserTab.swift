import AppKit
import Foundation

/// One open browser tab, as a thing the user can switch to.
///
/// Tabs are not windows, and PeekSwitch's whole enumeration path is built on windows —
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

    /// Stable within a presentation, which is all the UI needs to key a card by.
    var identity: String {
        "\(browser.bundleIdentifier):\(windowIdentifier):\(tabIndex)"
    }

    /// The bit of the URL worth reading on a card: "grok.com" rather than the full
    /// query-string-laden address.
    var host: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Browsers whose tabs can be listed and selected.
    ///
    /// Chromium-derived browsers share Chrome's scripting terminology (`title of tabs`,
    /// `active tab index`); Safari uses its own (`name of tabs`, `current tab`). Anything
    /// not on this list is simply not searched — there is no generic way to ask an
    /// arbitrary application for its tabs.
    enum Browser: String, CaseIterable, Sendable {
        case chrome
        case safari
        case edge
        case brave
        case chromium
        case arc

        var bundleIdentifier: String {
            switch self {
            case .chrome: return "com.google.Chrome"
            case .safari: return "com.apple.Safari"
            case .edge: return "com.microsoft.edgemac"
            case .brave: return "com.brave.Browser"
            case .chromium: return "org.chromium.Chromium"
            case .arc: return "company.thebrowser.Browser"
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
            }
        }

        /// Safari names a tab's title `name`; Chromium calls it `title`.
        var titleProperty: String {
            self == .safari ? "name" : "title"
        }

        /// Safari has no `active tab index`; the tab is selected by setting `current tab`.
        var usesCurrentTab: Bool { self == .safari }
    }
}
