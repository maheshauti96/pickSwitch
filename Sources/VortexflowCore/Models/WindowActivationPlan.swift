import Foundation

/// How a card click should bring a window forward.
///
/// The overlay is on the display the pointer is on. A raise that leaves the window
/// on the other monitor — or on a Space that display is not showing — is what
/// "I clicked Claude and it did not show up" is. The plan is decided from display
/// and Space flags so the policy can be tested without Accessibility.
enum WindowActivationPlan: Equatable, Sendable {

    /// The window is already on this desktop. Raise it, then activate, so the app's
    /// other window does not flash first.
    case raiseInPlace
    /// The window is on another Space of this display. Activate first: raising an
    /// off-Space window while its app is in the background does not switch desktops.
    case activateThenRaise
    /// The window is on a different display than the one the user is looking at.
    /// Move it here, then raise. With "Displays have separate Spaces" a raise cannot
    /// switch the other monitor, so this is the only way the card click is visible.
    case moveThenRaise

    /// - Parameters:
    ///   - isOnActiveSpace: whether Accessibility saw the window on this desktop.
    ///   - windowDisplayNumber: the screen that currently holds most of the window,
    ///     or `nil` when the frame sits on no display (stale after a drag).
    ///   - lookingAtDisplayNumber: the screen the overlay / pointer is on.
    static func resolve(
        isOnActiveSpace: Bool,
        windowDisplayNumber: Int?,
        lookingAtDisplayNumber: Int?
    ) -> WindowActivationPlan {
        if let looking = lookingAtDisplayNumber, windowDisplayNumber != looking {
            return .moveThenRaise
        }
        if !isOnActiveSpace {
            return .activateThenRaise
        }
        return .raiseInPlace
    }
}
