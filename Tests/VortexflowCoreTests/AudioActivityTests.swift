import Darwin
import Testing
@testable import VortexflowCore

/// Attribution is the whole of what can be tested here, and it is the part that decides whether a
/// badge appears at all.
///
/// CoreAudio itself is not exercised: `AudioActivityService` reads live hardware state, so a test
/// against it would assert whatever happened to be playing on the machine running it. What *is*
/// testable is the rule that turns "pid 28239 is on the speakers" into "the Chrome window is playing",
/// which is where this went wrong in the obvious implementation — Chrome's audio comes from a helper
/// process, so taking CoreAudio's pids at face value badges nothing.
struct AudioActivityTests {

    /// A process table shaped like the one measured on this machine: browsers and chat apps play
    /// their audio through a helper whose parent is the application.
    private enum Machine {
        static let chrome: pid_t = 872
        static let chromeHelperA: pid_t = 28239
        static let chromeHelperB: pid_t = 28240
        static let slack: pid_t = 1375
        static let slackHelper: pid_t = 1409
        /// A daemon that holds the input device open permanently and owns no window.
        static let historicalAudioDaemon: pid_t = 210
        /// The ancestor of everything, and so the one that decides whether an unrelated daemon's
        /// activity can reach an application. See `aDaemonWithNoWindowIsAttributedToNothing`.
        static let launchd: pid_t = 1

        static let parents: [pid_t: pid_t] = [
            chrome: launchd,
            chromeHelperA: chrome,
            chromeHelperB: chrome,
            slack: launchd,
            slackHelper: slack,
            historicalAudioDaemon: launchd,
        ]

        static func parent(of pid: pid_t) -> pid_t? { parents[pid] }
    }

    @Test func helperAudioIsAttributedToTheApplicationThatOwnsTheWindow() {
        let activity = AudioActivity.attributed(
            playing: [Machine.chromeHelperA],
            recording: [],
            to: [Machine.chrome, Machine.slack],
            parent: Machine.parent
        )

        #expect(activity.isPlaying(Machine.chrome))
        // The helper itself owns no window, so nothing should be keyed to it.
        #expect(!activity.isPlaying(Machine.chromeHelperA))
        #expect(!activity.isPlaying(Machine.slack))
    }

    @Test func anApplicationPlayingDirectlyIsStillFound() {
        let activity = AudioActivity.attributed(
            playing: [Machine.slack],
            recording: [],
            to: [Machine.chrome, Machine.slack],
            parent: Machine.parent
        )

        #expect(activity.isPlaying(Machine.slack))
        #expect(!activity.isPlaying(Machine.chrome))
    }

    @Test func twoHelpersOfOneApplicationCollapseToOneMark() {
        let activity = AudioActivity.attributed(
            playing: [Machine.chromeHelperA, Machine.chromeHelperB],
            recording: [],
            to: [Machine.chrome],
            parent: Machine.parent
        )

        #expect(activity.playing == [Machine.chrome])
    }

    /// The reading that would otherwise light up every window on screen. `historicalaudiod` reported
    /// input active on an idle machine during measurement, and it descends from `launchd` — so a walk
    /// that did not stop at pid 1 would attribute the microphone to whatever else happened to be
    /// there.
    @Test func aDaemonWithNoWindowIsAttributedToNothing() {
        let activity = AudioActivity.attributed(
            playing: [],
            recording: [Machine.historicalAudioDaemon],
            to: [Machine.chrome, Machine.slack],
            parent: Machine.parent
        )

        #expect(activity.isSilent)
    }

    @Test func playingAndRecordingAreKeptApart() {
        let activity = AudioActivity.attributed(
            playing: [Machine.chromeHelperA],
            recording: [Machine.slackHelper],
            to: [Machine.chrome, Machine.slack],
            parent: Machine.parent
        )

        #expect(activity.playing == [Machine.chrome])
        #expect(activity.recording == [Machine.slack])
    }

    @Test func noCandidatesMeansNoWork() {
        let activity = AudioActivity.attributed(
            playing: [Machine.chrome],
            recording: [Machine.slack],
            to: [],
            parent: Machine.parent
        )

        #expect(activity == .silent)
    }

    /// A chain that never reaches a candidate must terminate rather than walk forever. Kernel
    /// process reads are not one consistent snapshot, so a cycle is not impossible.
    @Test func aParentChainThatLoopsTerminates() {
        let looping: [pid_t: pid_t] = [100: 101, 101: 102, 102: 100]

        let owner = AudioActivity.owner(
            of: 100,
            among: [999],
            parent: { looping[$0] }
        )

        #expect(owner == nil)
    }

    @Test func aChainDeeperThanTheAllowanceIsGivenUpOn() {
        // A line of parents one longer than the walk will follow, ending at a real candidate.
        let depth = AudioActivity.maximumAncestorDepth + 2
        var parents: [pid_t: pid_t] = [:]
        for step in 0..<depth { parents[pid_t(100 + step)] = pid_t(100 + step + 1) }
        let root = pid_t(100 + depth)

        #expect(AudioActivity.owner(of: 100, among: [root], parent: { parents[$0] }) == nil)
        // Within the allowance the same shape resolves, so the bound is what is being tested and
        // not a broken walk.
        #expect(AudioActivity.owner(of: 100 + 2, among: [root], parent: { parents[$0] }) == root)
    }

    @Test func aProcessWithNoKnownParentIsNotAttributed() {
        #expect(AudioActivity.owner(of: 4242, among: [Machine.chrome], parent: { _ in nil }) == nil)
    }
}

/// The wording is tested because it is a claim about accuracy, not decoration. The two subjects are
/// not equally precise — a tab is named by its browser's tab strip, a window only as far as its
/// process — and the tooltip is where that difference is disclosed.
struct AudioActivityBadgeWordingTests {

    @Test func aWindowsBadgeClaimsOnlyTheApplication() {
        for (playing, recording) in [(true, false), (false, true), (true, true)] {
            let tooltip = AudioActivityBadge.tooltip(
                isPlaying: playing,
                isRecording: recording,
                subject: .application
            )
            #expect(tooltip.contains("This app"))
            // CoreAudio cannot narrow it to one window, so the tooltip must not imply it has.
            #expect(!tooltip.lowercased().contains("window"))
        }
    }

    @Test func aTabsBadgeClaimsTheTab() {
        for (playing, recording) in [(true, false), (false, true), (true, true)] {
            let tooltip = AudioActivityBadge.tooltip(
                isPlaying: playing,
                isRecording: recording,
                subject: .tab
            )
            #expect(tooltip.contains("This tab"))
        }
    }

    @Test func nothingIsSaidWhenNothingIsHappening() {
        for subject in [AudioActivityBadge.Subject.tab, .application] {
            #expect(
                AudioActivityBadge.tooltip(
                    isPlaying: false, isRecording: false, subject: subject
                ).isEmpty
            )
            #expect(
                AudioActivityBadge.accessibilityPhrases(
                    isPlaying: false, isRecording: false, subject: subject
                ).isEmpty
            )
        }
    }

    /// The microphone leads, in the tooltip and for VoiceOver both. "Something is listening to me" is
    /// the one of the two a user may need to act on.
    @Test func theMicrophoneIsAnnouncedFirst() {
        let phrases = AudioActivityBadge.accessibilityPhrases(
            isPlaying: true,
            isRecording: true,
            subject: .tab
        )
        #expect(phrases.count == 2)
        #expect(phrases.first?.contains("microphone") == true)
        #expect(phrases.last?.contains("audio") == true)
    }
}
