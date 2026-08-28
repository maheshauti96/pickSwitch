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
    /// Browsers that have answered at least one Apple Event this session. A window refresh while
    /// the overlay is visible is restricted to this set, so it can never summon a first-time
    /// Automation consent dialog over the switcher.
    private var authorizedBrowsers: Set<BrowserTab.Browser> = []

    /// Every tab open in every supported browser that is currently running.
    func tabs() async -> [BrowserTab] {
        let running = await MainActor.run { Self.runningBrowsers() }
        guard !running.isEmpty else { return [] }

        var all: [BrowserTab] = []
        for browser in running where !deniedBrowsers.contains(browser) {
            switch Self.enumerate(browser) {
            case .success(let tabs):
                authorizedBrowsers.insert(browser)
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

    /// Every window of every running Chromium browser, including its active-tab URL when the
    /// browser exposes one.
    ///
    /// - Parameter allowPermissionPrompt: When `false`, only browsers that have already answered
    ///   an Apple Event this session are queried. This is the only mode used while the overlay is
    ///   visible, preventing a first-time Automation dialog from taking focus. The `true` mode is
    ///   used after dismissal, where macOS may safely ask for access.
    ///
    /// Much cheaper than `tabs()`: one Apple Event per browser rather than one per window, and no
    /// per-tab lists to marshal — around 60 ms for a session with three Chrome windows against
    /// roughly 300 ms to enumerate their tabs. It still never runs on the 150 ms trigger path.
    ///
    /// Safari is excluded. Its scripting dictionary has no equivalent of `mode`, so a Safari
    /// private window is indistinguishable from an ordinary one from out here. Terminal is
    /// included even without a mode: its windows have to be paired so "Search through Tabs"
    /// can name the window whose tabs to list.
    func windows(allowPermissionPrompt: Bool = true) async -> [ScriptedBrowserWindow] {
        let running = await MainActor.run { Self.runningBrowsers() }
        let scriptable = running.filter {
            $0.needsWindowInspection
                && !deniedBrowsers.contains($0)
                && (allowPermissionPrompt || authorizedBrowsers.contains($0))
        }
        guard !scriptable.isEmpty else { return [] }

        var all: [ScriptedBrowserWindow] = []
        for browser in scriptable {
            switch Self.enumerateWindows(browser) {
            case .success(let windows):
                authorizedBrowsers.insert(browser)
                all.append(contentsOf: windows)
            case .denied:
                deniedBrowsers.insert(browser)
                Log.registry.info("""
                    Automation permission for \(browser.scriptingName, privacy: .public) \
                    was refused; its windows will not be inspected
                    """)
            case .failed(let message):
                Log.registry.debug("""
                    could not list \(browser.scriptingName, privacy: .public) windows: \
                    \(message, privacy: .public)
                    """)
            }
        }
        return all
    }

    /// The script that brings a tab to the front: activate the browser, then select the tab within
    /// its window and raise that window.
    ///
    /// ## Why `activate` comes first
    ///
    /// It used to come last, which reads more naturally — set everything up, then bring the browser
    /// forward — and it does not work when the tab's window is on another desktop. Raising a window
    /// while its application is in the background does not move it: measured against a Chrome with
    /// one window on this Space and one on another, raising the off-Space window and then activating
    /// left the *on-Space* window in front, three times out of three. Activating first and raising
    /// second put the right window in front, and pulled its desktop with it, three times out of
    /// three.
    ///
    /// That is exactly the reported symptom — "it opened another Chrome window, and the second
    /// attempt opened the right tab". The first attempt's `activate` made the browser frontmost
    /// without honouring the raise, so the second attempt found it already frontmost and the raise
    /// then worked. Two presses did the job of one, and the first press looked like it had picked
    /// the wrong window.
    ///
    /// Only the order changes, and it is worth saying what did *not* need to. A first attempt at this
    /// waited for the browser to report itself frontmost before raising, on the assumption that
    /// `activate` returns too early. It does return early, but the wait was useless: AppleScript's
    /// `frontmost` is already true the moment activation is *requested*, so the loop ran zero times
    /// and the script it guarded still failed. A fixed delay in its place was not needed either —
    /// activating first works with no pause at all, across every delay tried from 0 to 0.5 s.
    static func activationScript(for tab: BrowserTab) -> String {
        let selection: String
        if tab.browser.usesCurrentTab {
            // Safari addresses the selected tab by object, not by index.
            selection = "set current tab of targetWindow to tab \(tab.tabIndex) of targetWindow"
        } else if tab.browser.usesSelectedTab {
            selection = "set selected of tab \(tab.tabIndex) of targetWindow to true"
        } else {
            selection = "set active tab index of targetWindow to \(tab.tabIndex)"
        }

        return """
        tell application "\(tab.browser.scriptingName)"
            activate
            set targetWindow to window id \(tab.windowIdentifier)
            \(selection)
            set index of targetWindow to 1
        end tell
        """
    }

    /// Bring a tab to the front: activate the browser, select the tab within its window, and raise
    /// that window. See `activationScript(for:)` for why that order.
    func activate(_ tab: BrowserTab) -> Bool {
        switch Self.run(Self.activationScript(for: tab)) {
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
        if browser == .terminal {
            return enumerateTerminalTabs()
        }

        // Safari has no `mode`, and asking for a property a dictionary does not declare fails the
        // whole script rather than that one field. Substituting a literal keeps one script for
        // every browser while leaving Safari's tabs correctly ineligible for an icon request.
        let modeExpression = browser.reportsWindowMode ? "(mode of w as text)" : "\"unknown\""

        let source = """
        set AppleScript's text item delimiters to "\(itemDelimiter)"
        tell application "\(browser.scriptingName)"
            set collected to {}
            repeat with w in windows
                set titles to \(browser.titleProperty) of tabs of w
                set addresses to URL of tabs of w
                set end of collected to ((id of w as text) & "\(fieldDelimiter)" ¬
                    & \(modeExpression) & "\(fieldDelimiter)" ¬
                    & (titles as text) & "\(fieldDelimiter)" & (addresses as text))
            end repeat
        end tell
        set AppleScript's text item delimiters to "\(recordDelimiter)"
        return collected as text
        """

        switch run(source) {
        case .success(let output):
            return .success(parseTabs(output, browser: browser))
        case .denied:
            return .denied
        case .failed(let message):
            return .failed(message)
        }
    }

    /// Terminal has no `name` or `URL` on a tab. `custom title` is what the user set; `tty` is
    /// always present and is the fallback so an untitled session is still findable.
    ///
    /// Indexed loops rather than `repeat with w in windows`: Terminal's dictionary does not
    /// resolve `item N of every window`, which is what that form of repeat produces.
    ///
    /// Each record also carries the window's bounds. Terminal's title-bar pills are often
    /// *other windows* merged by macOS window-tabbing, each with one session, sharing a
    /// rectangle. `parseTerminalTabs` groups those so a scope on the front window includes
    /// its neighbours.
    private static func enumerateTerminalTabs() -> TabsOutcome {
        let source = """
        set AppleScript's text item delimiters to "\(itemDelimiter)"
        tell application "Terminal"
            set collected to {}
            repeat with i from 1 to (count of windows)
                set w to window i
                set edges to bounds of w
                set labels to {}
                repeat with j from 1 to (count of tabs of w)
                    set t to tab j of w
                    set label to ""
                    try
                        set label to custom title of t
                    end try
                    if label is "" then set label to tty of t
                    set end of labels to label
                end repeat
                set end of collected to ((id of w as text) & "\(fieldDelimiter)" ¬
                    & (item 1 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 2 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 3 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 4 of edges as text) & "\(fieldDelimiter)" ¬
                    & (labels as text))
            end repeat
        end tell
        set AppleScript's text item delimiters to "\(recordDelimiter)"
        return collected as text
        """

        switch run(source) {
        case .success(let output):
            return .success(parseTerminalTabs(output))
        case .denied:
            return .denied
        case .failed(let message):
            return .failed(message)
        }
    }

    private enum WindowsOutcome {
        case success([ScriptedBrowserWindow])
        case denied
        case failed(String)
    }

    /// One event for the whole browser: id, mode, title, rectangle and active-tab URL for each
    /// window. The URL read is isolated per window: one transient or browser-specific failure
    /// leaves that record usable with the browser icon fallback instead of failing the batch.
    private static func enumerateWindows(_ browser: BrowserTab.Browser) -> WindowsOutcome {
        if browser == .terminal {
            return enumerateTerminalWindows()
        }

        let source = """
        set collected to {}
        tell application "\(browser.scriptingName)"
            repeat with w in windows
                set edges to bounds of w
                set activeAddress to ""
                try
                    set activeAddress to URL of active tab of w as text
                end try
                set end of collected to ((id of w as text) & "\(fieldDelimiter)" ¬
                    & (mode of w as text) & "\(fieldDelimiter)" ¬
                    & (name of w as text) & "\(fieldDelimiter)" ¬
                    & (item 1 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 2 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 3 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 4 of edges as text) & "\(fieldDelimiter)" ¬
                    & activeAddress)
            end repeat
        end tell
        set AppleScript's text item delimiters to "\(recordDelimiter)"
        return collected as text
        """

        switch run(source) {
        case .success(let output):
            return .success(parseWindows(output, browser: browser))
        case .denied:
            return .denied
        case .failed(let message):
            return .failed(message)
        }
    }

    /// Terminal has no `mode` and no active-tab URL. Asking for either fails the whole window
    /// listing. The rest of the record is the same shape `parseWindows` already understands.
    private static func enumerateTerminalWindows() -> WindowsOutcome {
        let source = """
        set collected to {}
        tell application "Terminal"
            repeat with i from 1 to (count of windows)
                set w to window i
                set edges to bounds of w
                set end of collected to ((id of w as text) & "\(fieldDelimiter)" ¬
                    & "unknown" & "\(fieldDelimiter)" ¬
                    & (name of w as text) & "\(fieldDelimiter)" ¬
                    & (item 1 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 2 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 3 of edges as text) & "\(fieldDelimiter)" ¬
                    & (item 4 of edges as text) & "\(fieldDelimiter)" ¬
                    & "")
            end repeat
        end tell
        set AppleScript's text item delimiters to "\(recordDelimiter)"
        return collected as text
        """

        switch run(source) {
        case .success(let output):
            return .success(parseWindows(output, browser: .terminal))
        case .denied:
            return .denied
        case .failed(let message):
            return .failed(message)
        }
    }

    static func parseWindows(
        _ output: String,
        browser: BrowserTab.Browser
    ) -> [ScriptedBrowserWindow] {
        var windows: [ScriptedBrowserWindow] = []

        for record in output.components(separatedBy: recordDelimiter) where !record.isEmpty {
            let fields = record.components(separatedBy: fieldDelimiter)
            guard
                fields.count == 7 || fields.count == 8,
                let identifier = Int(fields[0]),
                let left = Double(fields[3]),
                let top = Double(fields[4]),
                let right = Double(fields[5]),
                let bottom = Double(fields[6])
            else { continue }

            let mode = fields[1].trimmingCharacters(in: .whitespaces).lowercased()
            let activeTabURL = fields.count == 8 && !fields[7].isEmpty ? fields[7] : nil
            windows.append(
                ScriptedBrowserWindow(
                    browser: browser,
                    identifier: identifier,
                    // Unknown modes stay visually unbadged, but only an explicit `normal` is
                    // eligible for a network favicon request.
                    isIncognito: mode == "incognito",
                    title: fields[2],
                    // AppleScript gives edges, not an origin and a size.
                    frame: CGRect(
                        x: left,
                        y: top,
                        width: max(0, right - left),
                        height: max(0, bottom - top)
                    ),
                    activeTabURL: activeTabURL,
                    allowsFaviconRequest: mode == "normal"
                )
            )
        }
        return windows
    }

    /// Terminal records: window id, four bound edges, then session titles. Windows that share
    /// a rectangle get the same `groupKey` so a tab scope on the front one includes the rest.
    static func parseTerminalTabs(_ output: String) -> [BrowserTab] {
        struct Record {
            let identifier: Int
            let groupKey: String
            let titles: [String]
        }

        var records: [Record] = []
        for record in output.components(separatedBy: recordDelimiter) where !record.isEmpty {
            let fields = record.components(separatedBy: fieldDelimiter)
            guard
                fields.count == 6,
                let identifier = Int(fields[0]),
                let left = Double(fields[1]),
                let top = Double(fields[2]),
                let right = Double(fields[3]),
                let bottom = Double(fields[4])
            else { continue }
            let titles = fields[5].components(separatedBy: itemDelimiter).filter { !$0.isEmpty }
            guard !titles.isEmpty else { continue }
            let groupKey = "\(Int(left.rounded())),\(Int(top.rounded())),\(Int(right.rounded())),\(Int(bottom.rounded()))"
            records.append(Record(identifier: identifier, groupKey: groupKey, titles: titles))
        }

        let groupedCounts = Dictionary(grouping: records, by: \.groupKey).mapValues(\.count)
        var tabs: [BrowserTab] = []
        for record in records {
            // A unique frame is just a window, not a tab bar.
            let groupKey = (groupedCounts[record.groupKey] ?? 0) > 1 ? record.groupKey : nil
            for (offset, title) in record.titles.enumerated() {
                tabs.append(
                    BrowserTab(
                        browser: .terminal,
                        windowIdentifier: record.identifier,
                        tabIndex: offset + 1,
                        title: title,
                        url: "",
                        allowsFaviconRequest: false,
                        groupKey: groupKey
                    )
                )
            }
        }
        return tabs
    }

    static func parseTabs(_ output: String, browser: BrowserTab.Browser) -> [BrowserTab] {
        var tabs: [BrowserTab] = []

        for record in output.components(separatedBy: recordDelimiter) where !record.isEmpty {
            let fields = record.components(separatedBy: fieldDelimiter)
            guard fields.count == 4, let windowIdentifier = Int(fields[0]) else { continue }

            // Only the browser's exact `normal` answer permits a network request for this tab's
            // icon. Anything else — incognito, an unrecognised mode, or a browser that cannot
            // report one at all — is treated as private.
            let mode = fields[1].trimmingCharacters(in: .whitespaces).lowercased()
            let allowsFaviconRequest = mode == "normal"

            let titles = fields[2].components(separatedBy: itemDelimiter)
            let addresses = fields[3].components(separatedBy: itemDelimiter)

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
                        url: url,
                        allowsFaviconRequest: allowsFaviconRequest
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
