import Foundation

/// How pressing the trigger button behaves.
///
/// Hold-and-release is the fastest way to switch once you know where you are going,
/// but it is useless for the other real use case: opening the switcher to *look* at
/// what is open, read the window titles, and then decide. That needs the strip to
/// stay on screen.
///
/// `automatic` gives both from one button by distinguishing a tap from a hold, which
/// is how the physical gesture already reads to a user: a deliberate hold means "I am
/// steering", a quick tap means "show me".
enum ActivationMode: Int, CaseIterable, Codable, Sendable {

    /// Tap to leave the strip open, hold to switch on release. Default.
    case automatic = 0
    /// Always hold: releasing the button switches to the selected window.
    case hold = 1
    /// Always stay open: press to open, press again (or click) to switch.
    case toggle = 2

    /// A press shorter than this counts as a tap in `automatic` mode.
    ///
    /// 250 ms is comfortably longer than a deliberate click (typically 80–150 ms) and
    /// comfortably shorter than the moment someone spends holding a button while
    /// looking for a target.
    static let tapThreshold: TimeInterval = 0.25

    var displayName: String {
        switch self {
        case .automatic: return "Automatic (tap to keep open, hold to switch)"
        case .hold: return "Hold and release"
        case .toggle: return "Click to open, click to switch"
        }
    }

    var shortName: String {
        switch self {
        case .automatic: return "Automatic"
        case .hold: return "Hold"
        case .toggle: return "Toggle"
        }
    }

    var explanation: String {
        switch self {
        case .automatic:
            return "A quick tap opens the switcher and leaves it up so you can look around and click. Holding the button lets you scroll to a window and switch the moment you let go."
        case .hold:
            return "The switcher is only visible while you hold the button. Releasing switches to the selected window."
        case .toggle:
            return "Press once to open the switcher and it stays up. Press again, or click a window, to switch. Escape or a click outside closes it."
        }
    }

    /// Whether a release of the trigger should commit the selection, given how long
    /// the button was held.
    ///
    /// Pure and total so the tap-versus-hold decision is testable without a mouse.
    func commitsOnRelease(heldFor duration: TimeInterval) -> Bool {
        switch self {
        case .hold:
            return true
        case .toggle:
            return false
        case .automatic:
            return duration >= Self.tapThreshold
        }
    }
}
