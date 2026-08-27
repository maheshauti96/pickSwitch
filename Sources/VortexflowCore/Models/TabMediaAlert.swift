import CoreGraphics
import Foundation

/// What a Chromium tab strip says about one tab's media, read out of the accessibility tree.
///
/// ## Why this exists when `AudioActivity` already answers the question
///
/// It does not answer it. CoreAudio reports per process, and every tab of a browser shares one, so
/// the most it can say is "this browser is making noise" — no use at all when the browser has forty
/// tabs and the whole point is finding the one. Chrome's own tab strip clearly knows, and this is
/// where it says so: an alerting tab gets a phrase appended to its accessibility description, and a
/// button to mute it appears as a child that quiet tabs do not have.
///
///     quiet tab      desc=[FlowTrackr]                          children=[AXButton:Close]
///     playing        desc=[… - YouTube – Audio playing …]        children=[AXButton:Mute tab, Close]
///     on the mic     desc=[Grok – Microphone recording …]        children=[AXButton:Mute tab, Close]
///
/// ## What this costs in robustness, stated plainly
///
/// The phrase is a localised Chromium string, so this reads English Chrome and fails closed on
/// anything else — no badge rather than a wrong one. It is also not contractual: Chrome is free to
/// reword it, and if it does, tabs quietly stop being marked while windows carry on. That is the
/// trade for having the information at all; there is no scripting property and no public API for it,
/// and an extension is the only supported route.
enum TabMediaAlert: Equatable, Sendable {

    /// The tab is audible.
    case playingAudio

    /// The tab is capturing from the microphone or the camera.
    ///
    /// One case for both because they mean the same thing to someone scanning a switcher — something
    /// is recording me — and because the indicator for them is the same glyph.
    case recording

    /// Phrases observed on this machine, exactly as Chrome writes them.
    ///
    /// `Audio playing` and `Microphone recording` were both read off a live tab strip. `Camera
    /// recording` is Chromium's sibling string for the video case and is included on that basis
    /// rather than from observation, which is worth knowing if it ever turns out not to match.
    ///
    /// Muting is deliberately absent. A muted tab reports something like `Audio muting`, which
    /// matches no phrase here and so produces no badge — correct, because a muted tab is making no
    /// sound. Anything unrecognised behaves the same way, which is what makes reading a localised
    /// string tolerable: the failure is silence.
    private static let phrases: [(phrase: String, alert: TabMediaAlert)] = [
        ("Audio playing", .playingAudio),
        ("Microphone recording", .recording),
        ("Camera recording", .recording),
        ("Microphone and camera recording", .recording),
    ]

    /// Chrome separates a tab's title from its alert with an en dash, and appends its own memory
    /// reading after a hyphen: `Grok – Microphone recording - Memory usage - 370 MB`.
    private static let alertSeparator = " \u{2013} "
    private static let annotationSeparator = " - "

    /// The alert Chrome has appended to a tab's accessibility description, if any.
    ///
    /// Only segments *after* the first en dash are considered, so a page whose title merely contains
    /// the words cannot mark itself. The segment must equal a known phrase outright — containment
    /// would let `Audio playing tips - YouTube` badge itself.
    static func parse(accessibilityDescription description: String) -> TabMediaAlert? {
        let segments = description.components(separatedBy: alertSeparator)
        guard segments.count > 1 else { return nil }

        for segment in segments.dropFirst() {
            // Chrome's memory note rides along after the alert, on a hyphen rather than an en dash.
            let candidate = segment
                .components(separatedBy: annotationSeparator)[0]
                .trimmingCharacters(in: .whitespaces)
            if let match = phrases.first(where: { $0.phrase == candidate }) {
                return match.alert
            }
        }
        return nil
    }

    /// Whether `description` is Chrome's annotated form of a tab titled `title`.
    ///
    /// The title is the description's prefix and Chrome's annotations follow it, so this asks about
    /// the prefix rather than trying to strip suffixes whose shape and wording are not known. The
    /// separator check is what makes it exact: without it a tab called `YouTube` would claim the
    /// description belonging to `YouTube Music`.
    /// Both sides are trimmed first. Not speculative: `WindowEntry.displayTitle` already trims a
    /// tab's title before showing it, which is there because scripted titles do arrive with stray
    /// whitespace — and an exact prefix test would be defeated by a single trailing space.
    static func describes(title: String, accessibilityDescription description: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, description.hasPrefix(title) else { return false }
        let remainder = description.dropFirst(title.count)
        return remainder.isEmpty
            || remainder.hasPrefix(alertSeparator)
            || remainder.hasPrefix(annotationSeparator)
    }
}

// MARK: - Pairing what the tab strip said with what the overlay is showing

extension TabMediaAlert {

    /// One alerting tab, as read from a browser's tab strip.
    struct Reading: Equatable, Sendable {
        /// The browser process the strip belongs to. A tab entry carries the same pid, which keeps
        /// two browsers with same-titled tabs from being confused for one another.
        let processID: pid_t
        /// The window whose tab strip this was read from, when it could be identified.
        ///
        /// This is what makes a *window* badge honest. CoreAudio knows only that a browser process
        /// is on the microphone, so keyed on the process every window of that browser is marked —
        /// which is how an incognito window with nothing running in it came to show a microphone for
        /// a voice chat in a different window. A tab strip belongs to one window, so an alert read
        /// from it belongs to that window and to no other.
        let windowID: CGWindowID?
        /// The tab's accessibility description, annotations and all.
        let accessibilityDescription: String
        let alert: TabMediaAlert

        /// `windowID` defaults to absent because it is only needed for the *window* badge. Pairing a
        /// reading to a tab result does not use it — a tab is matched on title and process — so the
        /// tab path is not obliged to supply one.
        init(
            processID: pid_t,
            windowID: CGWindowID? = nil,
            accessibilityDescription: String,
            alert: TabMediaAlert
        ) {
            self.processID = processID
            self.windowID = windowID
            self.accessibilityDescription = accessibilityDescription
            self.alert = alert
        }
    }

    /// Everything one sweep of the tab strips found.
    struct Survey: Equatable, Sendable {
        var readings: [Reading] = []

        static let empty = Survey()

        /// Processes the strip may be believed *about*, which is narrower than the processes that
        /// were looked at.
        ///
        /// A process qualifies only by having produced a reading. That distinction is the difference
        /// between fixing one bug and shipping another: a browser can be walked successfully and
        /// still report nothing, because the alert phrase is a localised Chromium string and a
        /// non-English Chrome matches none of them. Treating "walked it, found nothing" as silence
        /// would take the badge away from those users entirely — where treating it as "no finer
        /// answer available" leaves them with CoreAudio's coarse one, which is what they have today.
        ///
        /// Where a reading *was* found, the strip has demonstrably been understood, so a sibling
        /// window's absence from it is real information. That is the incognito window's case.
        var narrowedProcesses: Set<pid_t> {
            Set(readings.map(\.processID))
        }
    }

    /// The alert to show on each *window*, keyed by window id.
    ///
    /// Windows the sweep inspected and found nothing in are deliberately absent rather than present
    /// with a "silent" value: the caller distinguishes "inspected and quiet" from "not inspected" by
    /// `Survey.inspectedProcesses`, which is a property of the browser rather than of the window.
    static func windowAlerts(readings: [Reading]) -> [CGWindowID: TabMediaAlert] {
        var resolved: [CGWindowID: TabMediaAlert] = [:]
        for reading in readings {
            guard let windowID = reading.windowID else { continue }
            // A window with both a recording tab and an audible one reports the microphone, matching
            // the order the badge itself puts them in: being listened to outranks making noise.
            if resolved[windowID] == .recording { continue }
            resolved[windowID] = reading.alert
        }
        return resolved
    }

    /// Match each reading to the tab entries it describes, keyed by entry id.
    ///
    /// Matching is on title and owning process, because the obvious key is not available: tab
    /// buttons advertise `AXURL` and it comes back empty, so the address cannot be used. Position
    /// is not usable either — the strip is per accessibility window, while a scripted tab is
    /// numbered within the browser's own window, and those are different identifier spaces.
    ///
    /// Two tabs with the same title in the same browser will therefore both be marked when one of
    /// them alerts. That is the known cost of a title key. It stays small because it only applies
    /// to duplicates of a tab that is *actually* playing, and the alternative — marking nothing —
    /// is what this whole exercise was for.
    static func alerts(
        forTabsIn entries: [WindowEntry],
        readings: [Reading]
    ) -> [String: TabMediaAlert] {
        guard !readings.isEmpty else { return [:] }

        var resolved: [String: TabMediaAlert] = [:]
        for entry in entries where entry.isTab {
            guard let tab = entry.tab else { continue }
            let match = readings.first { reading in
                reading.processID == entry.processID
                    && describes(
                        title: tab.title,
                        accessibilityDescription: reading.accessibilityDescription
                    )
            }
            if let match { resolved[entry.id] = match.alert }
        }
        return resolved
    }
}
