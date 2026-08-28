import CoreAudio
import Darwin
import Foundation

/// Asks CoreAudio which processes are using the speakers or the microphone.
///
/// ## Why CoreAudio rather than anything friendlier
///
/// There is no AppKit or `NSRunningApplication` reading for this. CoreAudio's
/// `kAudioHardwarePropertyProcessObjectList` is the one public interface that will name *other*
/// processes using an audio device, and it needs no entitlement and prompts for nothing — which
/// matters, because a switcher that provoked a microphone consent dialog on the way up would be
/// worse than one that shows no badge.
///
/// ## Cost
///
/// Measured on this machine over 20 samples of the whole query, against 36–37 process objects: min
/// 6.11 ms, median 7.17 ms, max 9.30 ms — and an earlier run of the same shape produced a 56.78 ms
/// outlier. The median would sit comfortably inside the 150 ms presentation budget of Requirement
/// 14.1; the outlier is a third of it, spent on a badge. So this is called from the work queue after
/// the panel is already on screen, which is the same treatment private-window detection gets, and
/// for the same reason.
enum AudioActivityService {

    /// What is playing and recording right now, attributed to the given processes.
    ///
    /// - Parameter candidates: pids that own something the overlay is showing. Activity that does
    ///   not lead back to one of them is dropped, so the daemons that permanently hold the input
    ///   device open cannot badge anything.
    static func current(attributedTo candidates: Set<pid_t>) -> AudioActivity {
        guard !candidates.isEmpty else { return .silent }

        var playing: [pid_t] = []
        var recording: [pid_t] = []

        for object in processObjects() {
            guard let pid = processID(of: object), pid > 0 else { continue }
            if isTrue(kAudioProcessPropertyIsRunningOutput, of: object) { playing.append(pid) }
            if isTrue(kAudioProcessPropertyIsRunningInput, of: object) { recording.append(pid) }
        }

        return AudioActivity.attributed(
            playing: playing,
            recording: recording,
            to: candidates,
            parent: parentProcess(of:)
        )
    }

    // MARK: - CoreAudio

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0
        else { return [] }

        var objects = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr
        else { return [] }
        return objects
    }

    /// Read one fixed-size property into storage the caller already owns.
    ///
    /// `inout` rather than a generic returning `Value?`, and that is not a style preference. The
    /// returning version compiles, runs, and reports silence forever: `Value?` of a type with no
    /// spare bit patterns — `Int32`, `UInt32` — carries a separate tag byte, so handing CoreAudio a
    /// pointer rebound to `Value` fills the payload and leaves the tag saying `nil`. Passing already
    /// initialised storage has no tag to get out of step.
    private static func read<Value>(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID,
        into value: inout Value
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    /// The process behind an audio object, or `nil` if it has gone.
    ///
    /// Optional rather than defaulted: a process object can be torn down between being listed and
    /// being read, and that has to be skipped rather than treated as pid 0.
    private static func processID(of object: AudioObjectID) -> pid_t? {
        var pid: pid_t = -1
        guard read(kAudioProcessPropertyPID, of: object, into: &pid) else { return nil }
        return pid
    }

    /// CoreAudio reports these flags as `UInt32`, not as a C boolean.
    private static func isTrue(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID
    ) -> Bool {
        var flag: UInt32 = 0
        guard read(selector, of: object, into: &flag) else { return false }
        return flag != 0
    }

    // MARK: - Process ancestry

    /// The parent of a process, read from the kernel's process table.
    ///
    /// `sysctl` rather than `NSRunningApplication`, which has no notion of a parent, and rather than
    /// spawning `ps`, which would put a process launch on the path of drawing a badge.
    private static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
              // A process that exited between listing and lookup comes back as a zero-filled
              // record rather than an error, and its "parent" would be pid 0.
              size > 0
        else { return nil }

        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }
}
