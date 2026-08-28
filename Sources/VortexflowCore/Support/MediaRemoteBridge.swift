import AppKit
import CoreFoundation
import Darwin
import Foundation

/// Play / pause / next for whatever is making noise — Chrome's YouTube Music tab included.
///
/// Private `MRMediaRemoteSendCommand` is the obvious call, and it is the wrong one here.
/// On current macOS it is restricted, and Chrome's Media Session ignores `kMRPause`
/// even when the call lands. The hardware media keys are what Chrome actually listens
/// to (the same path Control Center and the F8/F9/F10 keys use), so that is what we
/// post. `NX_KEYTYPE_PLAY` is already a toggle, which is why pause then play works
/// without a separate play command.
enum MediaRemoteBridge {

    enum Command: Equatable {
        case togglePlayPause
        case next
        case previous

        /// `NX_KEYTYPE_*` from `<hidsystem/ev_keymap.h>`.
        fileprivate var hidKey: Int32 {
            switch self {
            case .togglePlayPause: return 16
            case .next: return 17
            case .previous: return 18
            }
        }
    }

    @discardableResult
    static func send(_ command: Command) -> Bool {
        postHIDMediaKey(command.hidKey)
    }

    /// Down then up, matching a real key press. A down without an up leaves the
    /// system thinking the media key is still held.
    private static func postHIDMediaKey(_ key: Int32) -> Bool {
        func post(down: Bool) -> Bool {
            let keyFlags = down ? 0xA00 : 0xB00
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyFlags)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (Int(key) << 16) | keyFlags,
                data2: -1
            ), let cgEvent = event.cgEvent else {
                return false
            }
            cgEvent.post(tap: .cgSessionEventTap)
            return true
        }
        let down = post(down: true)
        let up = post(down: false)
        return down && up
    }
}
