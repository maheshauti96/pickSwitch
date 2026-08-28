import CoreGraphics
import Darwin
import Testing
@testable import VortexflowCore

/// Every string here was read off a live Chrome tab strip through the accessibility tree, not
/// invented. That matters more than usual: this parses another application's human-readable text, so
/// a fixture that drifts from what Chrome actually writes would test nothing at all.
struct TabMediaAlertParsingTests {

    /// Verbatim from the probe. Note both dashes: Chrome separates the alert with an en dash and its
    /// own memory note with a hyphen, and the title itself contains a hyphen too — which is exactly
    /// why the alert cannot be found by splitting on hyphens.
    private static let playing =
        "(39266) 😱SHOCKING! 1966 Jantar-Mantar Protest (3D) by Professor of How - YouTube "
        + "\u{2013} Audio playing - Memory usage - 335 MB"
    private static let recording = "Grok \u{2013} Microphone recording - Memory usage - 370 MB"
    private static let quiet = "FlowTrackr"
    private static let quietWithMemory =
        "docs(aiv): response drawer is segment-scoped by pratikb-quattr · Pull Request #6799 "
        + "- Memory usage - 251 MB"

    @Test func anAudibleTabIsRecognised() {
        #expect(TabMediaAlert.parse(accessibilityDescription: Self.playing) == .playingAudio)
    }

    @Test func aTabOnTheMicrophoneIsRecognised() {
        #expect(TabMediaAlert.parse(accessibilityDescription: Self.recording) == .recording)
    }

    @Test func thePageTitleIsTakenFromTheDescription() {
        #expect(TabMediaAlert.title(fromAccessibilityDescription: Self.quiet) == "FlowTrackr")
        #expect(TabMediaAlert.title(fromAccessibilityDescription: Self.recording) == "Grok")
        #expect(
            TabMediaAlert.title(fromAccessibilityDescription: "YouTube Music \u{2013} Audio playing")
                == "YouTube Music"
        )
    }

    @Test func aQuietTabReportsNothing() {
        #expect(TabMediaAlert.parse(accessibilityDescription: Self.quiet) == nil)
        // The memory note is not an alert, and it arrives on the same kind of separator as one.
        #expect(TabMediaAlert.parse(accessibilityDescription: Self.quietWithMemory) == nil)
    }

    /// The alert can be the whole of the suffix — Chrome only appends its memory reading for some
    /// tabs, so the parse cannot depend on anything following the phrase.
    @Test func anAlertWithNothingAfterItIsStillFound() {
        #expect(
            TabMediaAlert.parse(accessibilityDescription: "YouTube \u{2013} Audio playing")
                == .playingAudio
        )
    }

    /// A muted tab is silent, so it must not be badged. Chrome words it differently from playing, and
    /// because the phrase table is matched exactly rather than by containment, that lands on nothing
    /// without needing to be listed — which is the same protection every reworded or translated
    /// phrase gets.
    @Test func anythingUnrecognisedIsSilentRatherThanGuessedAt() {
        for description in [
            "YouTube \u{2013} Audio muting",
            "YouTube \u{2013} Audio muted",
            // A future or translated wording.
            "YouTube \u{2013} Ton wird abgespielt",
        ] {
            #expect(TabMediaAlert.parse(accessibilityDescription: description) == nil)
        }
    }

    /// A page is free to put the words in its own title, and it must not be able to badge itself.
    @Test func aTitleContainingThePhraseCannotMarkItself() {
        #expect(
            TabMediaAlert.parse(accessibilityDescription: "Audio playing - YouTube") == nil
        )
        #expect(
            TabMediaAlert.parse(
                accessibilityDescription: "How to tell if Audio playing on a tab - Stack Overflow"
            ) == nil
        )
    }

    /// A title may legitimately contain an en dash, which is the separator. The alert is still found,
    /// because every segment after the first is considered rather than only the second.
    @Test func anEnDashInTheTitleDoesNotHideTheAlert() {
        #expect(
            TabMediaAlert.parse(
                accessibilityDescription: "Album \u{2013} Artist \u{2013} Audio playing"
            ) == .playingAudio
        )
    }
}

/// Attributing an alert to one *window* rather than to a whole browser.
///
/// Reported as microphone and speaker glyphs on an incognito Chrome window with nothing running in
/// it. CoreAudio's unit is the process, so one Grok tab in voice mode marked every Chrome window —
/// right about the browser, wrong about the window, and the badge is drawn on windows. A tab strip
/// belongs to one window, which is what makes the finer answer possible.
struct TabMediaAlertWindowTests {

    private static let chrome: pid_t = 872
    private static let voiceChatWindow: CGWindowID = 169
    private static let incognitoWindow: CGWindowID = 1121

    private func reading(
        window: CGWindowID?,
        title: String,
        alert: TabMediaAlert
    ) -> TabMediaAlert.Reading {
        TabMediaAlert.Reading(
            processID: Self.chrome,
            windowID: window,
            accessibilityDescription: "\(title) \u{2013} "
                + (alert == .recording ? "Microphone recording" : "Audio playing"),
            alert: alert
        )
    }

    /// The reported case, stated as a test: the window holding the voice chat is marked and the
    /// incognito window sharing its process is not.
    @Test func onlyTheWindowHoldingTheAlertingTabIsMarked() {
        let alerts = TabMediaAlert.windowAlerts(readings: [
            reading(window: Self.voiceChatWindow, title: "Grok", alert: .recording)
        ])

        #expect(alerts[Self.voiceChatWindow] == .recording)
        #expect(alerts[Self.incognitoWindow] == nil)
    }

    /// A reading whose window could not be identified must not be spread across every window. It is
    /// dropped from the window map — the tab badge can still use it, since that is matched on title.
    @Test func anUnattributableReadingMarksNoWindow() {
        let alerts = TabMediaAlert.windowAlerts(readings: [
            reading(window: nil, title: "Grok", alert: .recording)
        ])
        #expect(alerts.isEmpty)
    }

    /// The microphone wins where a window has both, matching the order the badge draws them in:
    /// being listened to is the one a user may need to act on.
    @Test func aWindowWithBothReportsTheMicrophone() {
        for ordering in [
            [TabMediaAlert.playingAudio, .recording],
            [TabMediaAlert.recording, .playingAudio],
        ] {
            let alerts = TabMediaAlert.windowAlerts(
                readings: ordering.enumerated().map { index, alert in
                    reading(window: Self.voiceChatWindow, title: "Tab \(index)", alert: alert)
                }
            )
            #expect(alerts[Self.voiceChatWindow] == .recording, "order \(ordering) lost the mic")
        }
    }

    @Test func twoWindowsEachKeepTheirOwnAlert() {
        let alerts = TabMediaAlert.windowAlerts(readings: [
            reading(window: Self.voiceChatWindow, title: "Grok", alert: .recording),
            reading(window: Self.incognitoWindow, title: "YouTube", alert: .playingAudio),
        ])

        #expect(alerts[Self.voiceChatWindow] == .recording)
        #expect(alerts[Self.incognitoWindow] == .playingAudio)
    }

    @Test func noReadingsMarksNoWindows() {
        #expect(TabMediaAlert.windowAlerts(readings: []).isEmpty)
    }
}

/// Pairing is title-based, because the two keys that would be better are both unavailable: tab
/// buttons advertise AXURL and return nothing for it, and a strip's position is numbered per
/// accessibility window while a scripted tab is numbered per browser window.
struct TabMediaAlertPairingTests {

    private static let chrome: pid_t = 872
    private static let safari: pid_t = 640

    private func tabEntry(
        title: String,
        url: String = "https://example.com",
        index: Int,
        pid: pid_t,
        browser: BrowserTab.Browser = .chrome
    ) -> WindowEntry {
        var entry = WindowEntry.tabEntry(
            BrowserTab(
                browser: browser,
                windowIdentifier: 1,
                tabIndex: index,
                title: title,
                url: url
            ),
            application: nil
        )
        // `tabEntry` takes the pid from a running application, which a test has none of.
        entry = WindowEntry(
            windowID: 0,
            processID: pid,
            applicationName: entry.applicationName,
            applicationIcon: nil,
            bundleIdentifier: entry.bundleIdentifier,
            title: entry.title,
            frame: .zero,
            isMinimized: false,
            zOrder: Int.max,
            axElement: nil,
            tab: entry.tab,
            launchableApplication: nil
        )
        return entry
    }

    @Test func theAlertingTabIsTheOneMarked() {
        let entries = [
            tabEntry(title: "FlowTrackr", index: 1, pid: Self.chrome),
            tabEntry(title: "Grok", index: 2, pid: Self.chrome),
            tabEntry(title: "New tab", index: 3, pid: Self.chrome),
        ]
        let readings = [
            TabMediaAlert.Reading(
                processID: Self.chrome,
                accessibilityDescription: "Grok \u{2013} Microphone recording - Memory usage - 370 MB",
                alert: .recording
            )
        ]

        let alerts = TabMediaAlert.alerts(forTabsIn: entries, readings: readings)

        #expect(alerts.count == 1)
        #expect(alerts[entries[1].id] == .recording)
        #expect(alerts[entries[0].id] == nil)
        #expect(alerts[entries[2].id] == nil)
    }

    /// The failure a title key invites: a prefix match alone would let the shorter title claim the
    /// longer one's alert.
    @Test func aShorterTitleDoesNotClaimALongerOnesAlert() {
        let entries = [
            tabEntry(title: "YouTube", index: 1, pid: Self.chrome),
            tabEntry(title: "YouTube Music", index: 2, pid: Self.chrome),
        ]
        let readings = [
            TabMediaAlert.Reading(
                processID: Self.chrome,
                accessibilityDescription: "YouTube Music \u{2013} Audio playing",
                alert: .playingAudio
            )
        ]

        let alerts = TabMediaAlert.alerts(forTabsIn: entries, readings: readings)

        #expect(alerts[entries[1].id] == .playingAudio)
        #expect(alerts[entries[0].id] == nil)
    }

    /// Two browsers can hold same-titled tabs, and a reading belongs to the one it was read from.
    @Test func aReadingDoesNotCrossBetweenBrowsers() {
        let entries = [
            tabEntry(title: "Grok", index: 1, pid: Self.chrome, browser: .chrome),
            tabEntry(title: "Grok", index: 1, pid: Self.safari, browser: .safari),
        ]
        let readings = [
            TabMediaAlert.Reading(
                processID: Self.safari,
                accessibilityDescription: "Grok \u{2013} Audio playing",
                alert: .playingAudio
            )
        ]

        let alerts = TabMediaAlert.alerts(forTabsIn: entries, readings: readings)

        #expect(alerts[entries[1].id] == .playingAudio)
        #expect(alerts[entries[0].id] == nil)
    }

    /// Windows are answered by CoreAudio, not by this, so a window must never pick up a reading even
    /// when its title would match one.
    @Test func windowsAreLeftAlone() {
        let window = WindowEntry(
            windowID: 41,
            processID: Self.chrome,
            applicationName: "Google Chrome",
            applicationIcon: nil,
            title: "Grok",
            frame: .zero,
            isMinimized: false,
            zOrder: 0,
            axElement: nil
        )
        let readings = [
            TabMediaAlert.Reading(
                processID: Self.chrome,
                accessibilityDescription: "Grok \u{2013} Audio playing",
                alert: .playingAudio
            )
        ]

        #expect(TabMediaAlert.alerts(forTabsIn: [window], readings: readings).isEmpty)
    }

    /// The two titles come from different places — one from the browser over Apple Events, one from
    /// the accessibility tree — and a single trailing space between them would otherwise lose the
    /// match entirely.
    @Test func straySpaceAroundATitleDoesNotLoseTheMatch() {
        let entries = [tabEntry(title: "  Grok ", index: 1, pid: Self.chrome)]
        let readings = [
            TabMediaAlert.Reading(
                processID: Self.chrome,
                accessibilityDescription: "Grok \u{2013} Audio playing",
                alert: .playingAudio
            )
        ]

        #expect(
            TabMediaAlert.alerts(forTabsIn: entries, readings: readings)[entries[0].id]
                == .playingAudio
        )
    }

    @Test func noReadingsMeansNoMarks() {
        let entries = [tabEntry(title: "Grok", index: 1, pid: Self.chrome)]
        #expect(TabMediaAlert.alerts(forTabsIn: entries, readings: []).isEmpty)
    }

    /// A tab whose title Chrome did not report an alert for stays unmarked even though its browser
    /// has one that is alerting. This is the whole difference from the process-level reading.
    @Test func onlyTheNamedTabOfANoisyBrowserIsMarked() {
        let entries = (1...5).map { index in
            tabEntry(title: "Pull Request #\(index)", index: index, pid: Self.chrome)
        }
        let readings = [
            TabMediaAlert.Reading(
                processID: Self.chrome,
                accessibilityDescription: "Pull Request #3 \u{2013} Audio playing",
                alert: .playingAudio
            )
        ]

        let alerts = TabMediaAlert.alerts(forTabsIn: entries, readings: readings)

        #expect(alerts.count == 1)
        #expect(alerts[entries[2].id] == .playingAudio)
    }
}
