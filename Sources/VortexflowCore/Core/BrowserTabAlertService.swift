import AppKit
import ApplicationServices
import Foundation

/// Reads which individual browser tabs are playing audio or recording, from the tab strip's
/// accessibility tree.
///
/// This is the only route to per-tab media state that exists outside a browser extension. Neither
/// Chrome's nor Safari's scripting dictionary has an audio property — Chrome's `tab` class offers
/// exactly `id`, `title`, `URL` and `loading` — and CoreAudio works in processes, which a browser
/// shares across every tab it has open.
///
/// ## Cost
///
/// Measured against a live Chrome with 18 tabs, over 10 samples of the whole thing including finding
/// the strip: min 3.5 ms, median 7.0 ms, max 11.7 ms. Called off the presentation path anyway, since
/// AX calls are IPC round trips into an application that may be busy, and `AXBridge`'s timeout bounds
/// a stall rather than preventing one.
///
/// ## Requires Accessibility
///
/// Without that grant this returns nothing, and tabs simply go unmarked while windows keep their
/// badge from CoreAudio, which needs no permission at all.
enum BrowserTabAlertService {

    /// Depth limit for finding a tab strip.
    ///
    /// The strip sat 9 levels below the application on the Chrome measured here, nested in
    /// browser-chrome groups. The allowance is a little larger because that nesting is Chrome's
    /// business and changes between versions.
    private static let maximumStripDepth = 14

    /// Ceiling on tabs read per strip, so a window with a pathological number of them cannot turn
    /// this into an unbounded walk.
    private static let maximumTabsPerStrip = 200

    /// Every alerting tab across the given browser processes.
    ///
    /// - Parameter processes: the browser pids that own tab results on screen. Nothing else is
    ///   walked: this is an expensive tree to descend and there is no reason to visit a browser
    ///   whose tabs are not being shown.
    static func survey(browserProcesses processes: Set<pid_t>) -> TabMediaAlert.Survey {
        guard !processes.isEmpty, AXIsProcessTrusted() else { return .empty }

        var survey = TabMediaAlert.Survey()
        for pid in processes {
            let application = AXUIElementCreateApplication(pid)
            AXBridge.applyMessagingTimeout(application)

            for (windowID, strip) in tabStrips(under: application) {
                for tab in tabButtons(of: strip) {
                    guard
                        let description = AXBridge.string(tab, kAXDescriptionAttribute as String),
                        let alert = TabMediaAlert.parse(accessibilityDescription: description)
                    else { continue }
                    survey.readings.append(
                        TabMediaAlert.Reading(
                            processID: pid,
                            windowID: windowID,
                            accessibilityDescription: description,
                            alert: alert
                        )
                    )
                }
            }
        }
        return survey
    }

    /// Find the tab strips, breadth-first, descending only through container roles.
    ///
    /// Breadth-first and stopping at the first level that yields a strip, because a browser window's
    /// tree is mostly page content and a depth-first walk would wander into it. Refusing to descend
    /// into anything but a window, group or toolbar is the other half of that: the rendered document
    /// is an `AXWebArea`, which is never entered, so this cannot end up reading the page.
    /// - Returns: each strip with the window it belongs to, so an alert can be attributed to one
    ///   window rather than to the whole browser. Descent is per window for exactly that reason: a
    ///   single flat sweep would find every strip and lose which window each came from.
    private static func tabStrips(under application: AXUIElement) -> [(CGWindowID?, AXUIElement)] {
        let windows = AXBridge.elements(application, kAXWindowsAttribute as String) ?? []
        var found: [(CGWindowID?, AXUIElement)] = []

        for window in windows {
            let windowID = AXBridge.windowID(for: window)
            var frontier = [window]
            var depth = 0
            var strip: AXUIElement?

            while !frontier.isEmpty, depth < maximumStripDepth, strip == nil {
                var next: [AXUIElement] = []
                for element in frontier {
                    let role = AXBridge.string(element, kAXRoleAttribute as String) ?? ""
                    if role == "AXTabGroup" {
                        strip = element
                        break
                    }
                    guard role == "AXWindow" || role == "AXGroup" || role == "AXToolbar"
                    else { continue }
                    next.append(
                        contentsOf: AXBridge.elements(element, kAXChildrenAttribute as String) ?? []
                    )
                }
                frontier = next
                depth += 1
            }

            if let strip { found.append((windowID, strip)) }
        }
        return found
    }

    /// The tabs of a strip, which are its radio buttons.
    ///
    /// Filtered on the subrole rather than the role: a strip also holds the new-tab button and,
    /// depending on the version, tab-search and tab-group affordances, and only a real tab carries
    /// `AXTabButton`.
    private static func tabButtons(of strip: AXUIElement) -> [AXUIElement] {
        let children = AXBridge.elements(strip, kAXChildrenAttribute as String) ?? []
        return children.prefix(maximumTabsPerStrip).filter { child in
            AXBridge.string(child, kAXSubroleAttribute as String) == "AXTabButton"
        }
    }
}
