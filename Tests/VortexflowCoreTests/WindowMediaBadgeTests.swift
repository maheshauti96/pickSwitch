import CoreGraphics
import Testing
@testable import VortexflowCore

/// Which of the two readings a window's badge believes, which is the whole of the reported defect.
///
/// "We are seeing microphone and speaker icons for incognito chrome window where nothing is running."
/// CoreAudio answers per process, so a Grok tab in voice mode made every Chrome window — incognito
/// included — claim a microphone. The state now prefers the per-window answer from the browser's tab
/// strip and keeps CoreAudio only where nothing finer exists.
@Suite("Window media badge")
@MainActor
struct WindowMediaBadgeTests {

    private static let chrome: pid_t = 872
    private static let zoom: pid_t = 1400
    private static let voiceChatWindow: CGWindowID = 169
    private static let incognitoWindow: CGWindowID = 1121
    private static let zoomWindow: CGWindowID = 1186

    private func loaded() -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.load(
            entries: [
                Fixture.entry(
                    id: Self.voiceChatWindow, app: "Google Chrome", title: "Grok", pid: Self.chrome
                ),
                Fixture.entry(
                    id: Self.incognitoWindow, app: "Google Chrome", title: "Incognito",
                    pid: Self.chrome
                ),
                Fixture.entry(
                    id: Self.zoomWindow, app: "zoom.us", title: "Zoom Meeting", pid: Self.zoom
                ),
            ],
            selectedIndex: 0
        )
        return state
    }

    /// The defect, and the fix. Chrome's process is both playing and recording, exactly as CoreAudio
    /// reported it, but the tab strip puts the alert in one window — so the other Chrome window is
    /// clean despite sharing the process.
    @Test func aQuietBrowserWindowIsNotMarkedForItsNoisySibling() {
        let state = loaded()
        state.audioActivity = AudioActivity(
            playing: [Self.chrome], recording: [Self.chrome]
        )
        state.narrowedBrowserProcesses = [Self.chrome]
        state.windowMediaAlerts = [Self.voiceChatWindow: .recording]

        let voiceChat = state.entries[0]
        let incognito = state.entries[1]

        #expect(state.isUsingMicrophone(voiceChat))
        #expect(!state.isUsingMicrophone(incognito))
        // And the speaker glyph goes too: the strip did not report audio in that window either, and
        // before this it was inheriting both from the process.
        #expect(!state.isPlayingAudio(incognito))
    }

    /// A browser that could not be inspected keeps the coarse answer rather than losing the badge.
    /// Accessibility not granted, an unfamiliar tab-strip shape or a wedged browser all land here,
    /// and silently dropping the feature would be worse than being imprecise.
    @Test func anUninspectableBrowserFallsBackToTheProcessReading() {
        let state = loaded()
        state.audioActivity = AudioActivity(playing: [Self.chrome], recording: [Self.chrome])
        state.narrowedBrowserProcesses = []
        state.windowMediaAlerts = [:]

        #expect(state.isUsingMicrophone(state.entries[0]))
        #expect(state.isUsingMicrophone(state.entries[1]))
        #expect(state.isPlayingAudio(state.entries[0]))
    }

    /// Non-browsers are untouched. Zoom has no tab strip to ask, so CoreAudio remains the only
    /// reading and the badge still appears.
    @Test func aNonBrowserWindowStillUsesCoreAudio() {
        let state = loaded()
        state.audioActivity = AudioActivity(playing: [Self.zoom], recording: [Self.zoom])
        // Chrome was inspected; Zoom was never a candidate, so its process is absent from the set.
        state.narrowedBrowserProcesses = [Self.chrome]
        state.windowMediaAlerts = [:]

        let zoomWindow = state.entries[2]
        #expect(state.isPlayingAudio(zoomWindow))
        #expect(state.isUsingMicrophone(zoomWindow))
    }

    /// An inspected browser whose strips reported nothing is quiet, even while CoreAudio insists the
    /// process is busy. This is the negative the inspected-process set exists to license: without it
    /// the fix would have no way to contradict CoreAudio.
    @Test func anInspectedBrowserWithNoAlertsOverridesCoreAudio() {
        let state = loaded()
        state.audioActivity = AudioActivity(playing: [Self.chrome], recording: [Self.chrome])
        state.narrowedBrowserProcesses = [Self.chrome]
        state.windowMediaAlerts = [:]

        #expect(!state.isPlayingAudio(state.entries[0]))
        #expect(!state.isUsingMicrophone(state.entries[1]))
    }
}
