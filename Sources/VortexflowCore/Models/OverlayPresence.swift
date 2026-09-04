import CoreGraphics
import Foundation

/// Whether the overlay is actually in front of the user.
///
/// `OverlayState.isVisible` is the flag `TriggerResponse` used to trust. A Space
/// change, a display reconfiguration, or a panel that never composited can leave
/// that flag true while nothing is on screen — and the next shortcut then closes
/// an overlay the user cannot see. The panel's own visibility, frame, and whether
/// the cards were revealed are the check that cannot lie.
enum OverlayPresence: Equatable, Sendable {

    /// The switcher is on screen and large enough to be the thing the user is looking at.
    static func isOnScreen(
        stateVisible: Bool,
        panelVisible: Bool,
        frame: CGRect,
        isRevealed: Bool
    ) -> Bool {
        stateVisible
            && panelVisible
            && isRevealed
            && frame.width > 1
            && frame.height > 1
    }
}

/// Whether a trigger that wants to open should be dropped as a duplicate.
///
/// The 120 ms window exists because HID and CGEvent can both report the same
/// physical mouse button. A keyboard shortcut is one event; suppressing it is
/// how a tap after a leftover dismiss looked like a dead key.
enum TriggerOpenGate: Equatable, Sendable {

    static func shouldIgnoreDuplicate(
        source: TriggerSource,
        recentlyDismissed: Bool
    ) -> Bool {
        source == .button && recentlyDismissed
    }
}
