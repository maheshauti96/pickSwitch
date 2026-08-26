import Foundation

/// Which applications are on the speakers or the microphone at this moment.
///
/// ## Why this is per application and not per tab
///
/// The obvious want is to mark the *tab* that is making noise, the way Chrome's own tab strip does.
/// macOS will not say. The only thing that reports audio activity to another process is CoreAudio's
/// process object list, and its unit is a process: `kAudioProcessPropertyIsRunningOutput` for a pid,
/// nothing finer. Chrome's scripting interface has no audio property either — `sdef` on Chrome and
/// Safari mentions neither `audible` nor `muted` anywhere — and the `audible` flag that does exist is
/// `chrome.tabs`, readable only from inside an extension.
///
/// So a browser playing audio marks *its window*, and every window of that browser, because as far as
/// the system is concerned the browser is one noisy process. That is a real limit and is stated in the
/// tooltip rather than papered over: the badge says this application is playing, not this tab is.
struct AudioActivity: Equatable, Sendable {

    /// Processes rendering audio to an output device.
    var playing: Set<pid_t>

    /// Processes capturing from an input device.
    var recording: Set<pid_t>

    static let silent = AudioActivity(playing: [], recording: [])

    init(playing: Set<pid_t> = [], recording: Set<pid_t> = []) {
        self.playing = playing
        self.recording = recording
    }

    var isSilent: Bool { playing.isEmpty && recording.isEmpty }

    func isPlaying(_ pid: pid_t) -> Bool { playing.contains(pid) }
    func isRecording(_ pid: pid_t) -> Bool { recording.contains(pid) }
}

// MARK: - Attributing activity to the application that owns it

extension AudioActivity {

    /// How many parent links the search for an owning application will follow.
    ///
    /// Chrome's audio arrives one level down, from a helper whose parent is the browser. The
    /// allowance is larger than that because the shape is not guaranteed — a browser is free to
    /// nest its service processes further, and a version that did would silently lose the badge.
    /// It is bounded at all so that a parent chain which fails to terminate cannot spin: pids form
    /// a tree in practice, but this walks kernel state read one process at a time, and those reads
    /// are not a single consistent snapshot.
    static let maximumAncestorDepth = 8

    /// Move the audio activity of the processes that opened the device onto the applications the
    /// user can actually see.
    ///
    /// The indirection is the whole job. A browser does not play audio itself: the pid CoreAudio
    /// names is a helper process, and the pid on a window is the browser. Measured on Chrome, Slack
    /// and Claude, the active process was a helper whose parent was the application — so an
    /// unattributed reading badges nothing at all, which is how this would fail if it were skipped.
    ///
    /// - Parameters:
    ///   - candidates: the pids that own something on screen. The walk stops at the first ancestor
    ///     in this set, which is what keeps the result from creeping up to `launchd`: activity is
    ///     only ever attributed to a process the overlay is already showing.
    ///   - parent: the parent of a pid, or `nil` where there is none to be had.
    static func attributed(
        playing: some Sequence<pid_t>,
        recording: some Sequence<pid_t>,
        to candidates: Set<pid_t>,
        parent: (pid_t) -> pid_t?
    ) -> AudioActivity {
        guard !candidates.isEmpty else { return .silent }
        return AudioActivity(
            playing: owners(of: playing, among: candidates, parent: parent),
            recording: owners(of: recording, among: candidates, parent: parent)
        )
    }

    private static func owners(
        of active: some Sequence<pid_t>,
        among candidates: Set<pid_t>,
        parent: (pid_t) -> pid_t?
    ) -> Set<pid_t> {
        var resolved: Set<pid_t> = []
        for pid in active {
            if let owner = owner(of: pid, among: candidates, parent: parent) {
                resolved.insert(owner)
            }
        }
        return resolved
    }

    /// The nearest ancestor of `pid` — itself included — that owns something on screen.
    ///
    /// `nil` for anything that does not lead to one, which is the common case and not a failure:
    /// most of what holds an audio device open is a daemon with no window. Returning `nil` there is
    /// what keeps `coreaudiod` and friends from being attributed to anything.
    static func owner(
        of pid: pid_t,
        among candidates: Set<pid_t>,
        parent: (pid_t) -> pid_t?
    ) -> pid_t? {
        var current = pid
        var seen: Set<pid_t> = []

        for _ in 0...maximumAncestorDepth {
            if candidates.contains(current) { return current }
            // Stop at `launchd`, pid 1: it is the ancestor of everything, so nothing useful is
            // above it, and its own parent is reported as pid 0 — the kernel, which is not a
            // process to go asking about.
            guard current > 1, seen.insert(current).inserted else { return nil }
            guard let next = parent(current), next != current else { return nil }
            current = next
        }
        return nil
    }
}
