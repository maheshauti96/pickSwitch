import AppKit
import Foundation

/// Lists and selects browser tabs through Apple Events.
///
/// ## Why this is never on the trigger path
///
/// Apple Events are inter-process round trips, and asking for tab titles the obvious way
/// — a property read per tab — measured at 3.4 seconds on a session with two Chrome
/// windows. Fetching whole lists per window instead (`title of tabs of w`) brings the
/// same work down to roughly 0.3 seconds, because it is a handful of events rather than
/// one per tab.
///
/// 0.3 seconds is still twice the entire budget for putting the overlay on screen
/// (Requirement 14.1), so tabs are never enumerated when the switcher opens. They are
/// fetched once, in the background, only after the user starts typing — the one moment
/// where the user is demonstrably looking for something by name and a short delay before
/// extra results appear reads as normal.
///
/// ## Permission
///
/// Controlling another application needs Automation authorisation, granted per target
/// application on first use. There is no way to ask for it up front, and no way to know
/// it was refused except by trying: a refusal surfaces as error −1743. That is treated as
/// "no tabs", never as a failure worth interrupting the user over.
actor BrowserTabService {

    /// Delimiters chosen from the C0 control range. Window titles routinely contain every
    /// printable separator worth trying — pipes, tabs, newlines — but never these.
    private static let fieldDelimiter = "\u{01}"
    private static let itemDelimiter = "\u{02}"
    private static let recordDelimiter = "\u{03}"

    /// macOS reports a refused Automation prompt as this error.
    private static let notAuthorizedError = -1743

    private var deniedBrowsers: Set<BrowserTab.Browser> = []

    /// Every tab open in every supported browser that is currently running.
    func tabs() async -> [BrowserTab] {
        let running = await MainActor.run { Self.runningBrowsers() }
        guard !running.isEmpty else { return [] }

        var all: [BrowserTab] = []
        for browser in running where !deniedBrowsers.contains(browser) {
            switch Self.enumerate(browser) {
            case .success(let tabs):
                all.append(contentsOf: tabs)
            case .denied:
                // Remember, so a user who declined the prompt is not asked again on every
                // keystroke for the rest of the session.
                deniedBrowsers.insert(browser)
                Log.registry.info("""
                    Automation permission for \(browser.scriptingName, privacy: .public) \
                    was refused; its tabs will not be searched
                    """)
            case .failed(let message):
                Log.registry.debug("""
                    could not list \(browser.scriptingName, privacy: .public) tabs: \
                    \(message, privacy: .public)
                    """)
            }
        }
        return all
    }

    /// Bring a tab to the front: select it within its window, raise that window, and
    /// activate the browser.
    func activate(_ tab: BrowserTab) -> Bool {
        let selection = tab.browser.usesCurrentTab
            // Safari addresses the selected tab by object, not by index.
            ? "set current tab of targetWindow to tab \(tab.tabIndex) of targetWindow"
            : "set active tab index of targetWindow to \(tab.tabIndex)"

        let source = """
        tell application "\(tab.browser.scriptingName)"
            set targetWindow to window id \(tab.windowIdentifier)
            \(selection)
            set index of targetWindow to 1
            activate
        end tell
        """

        switch Self.run(source) {
        case .success:
            return true
        case .denied, .failed:
            return false
        }
    }

    // MARK: - Enumeration

    private enum Outcome {
        case success(String)
        case denied
        case failed(String)
    }

    private enum TabsOutcome {
        case success([BrowserTab])
        case denied
        case failed(String)
    }

    @MainActor
    private static func runningBrowsers() -> [BrowserTab.Browser] {
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        return BrowserTab.Browser.allCases.filter { running.contains($0.bundleIdentifier) }
    }

    /// One event per window rather than one per tab. See the type comment for why that
    /// distinction is worth the slightly awkward script.
    private static func enumerate(_ browser: BrowserTab.Browser) -> TabsOutcome {
        let source = """
        set AppleScript's text item delimiters to "\(itemDelimiter)"
        tell application "\(browser.scriptingName)"
            set collected to {}
            repeat with w in windows
                set titles to \(browser.titleProperty) of tabs of w
                set addresses to URL of tabs of w
                set end of collected to ((id of w as text) & "\(fieldDelimiter)" ¬
                    & (titles as text) & "\(fieldDelimiter)" & (addresses as text))
            end repeat
        end tell
        set AppleScript's text item delimiters to "\(recordDelimiter)"
        return collected as text
        """

        switch run(source) {
        case .success(let output):
            return .success(parse(output, browser: browser))
        case .denied:
            return .denied
        case .failed(let message):
            return .failed(message)
        }
    }

    private static func parse(_ output: String, browser: BrowserTab.Browser) -> [BrowserTab] {
        var tabs: [BrowserTab] = []

        for record in output.components(separatedBy: recordDelimiter) where !record.isEmpty {
            let fields = record.components(separatedBy: fieldDelimiter)
            guard fields.count == 3, let windowIdentifier = Int(fields[0]) else { continue }

            let titles = fields[1].components(separatedBy: itemDelimiter)
            let addresses = fields[2].components(separatedBy: itemDelimiter)

            for (offset, title) in titles.enumerated() {
                let url = offset < addresses.count ? addresses[offset] : ""
                // A tab with neither a title nor an address is still loading and cannot be
                // matched against anything useful.
                guard !title.isEmpty || !url.isEmpty else { continue }

                tabs.append(
                    BrowserTab(
                        browser: browser,
                        windowIdentifier: windowIdentifier,
                        // AppleScript indexes from one, and the index is what selects it.
                        tabIndex: offset + 1,
                        title: title,
                        url: url
                    )
                )
            }
        }
        return tabs
    }

    private static func run(_ source: String) -> Outcome {
        guard let script = NSAppleScript(source: source) else {
            return .failed("script could not be compiled")
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == notAuthorizedError {
                return .denied
            }
            let message = error[NSAppleScript.errorMessage] as? String ?? "error \(code)"
            return .failed(message)
        }
        return .success(result.stringValue ?? "")
    }
}
