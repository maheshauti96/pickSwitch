import Foundation

/// What a change of desktop should do to an overlay that is currently on screen.
///
/// A pure decision rather than three branches inside a notification closure, for the reason
/// `ConfirmationTarget.resolve` was extracted: the closure needs a whole controller and a real Space
/// switch to reach, so the rule it encodes could only be checked by hand — and it shipped wrong
/// twice, once in each direction.
///
/// ## Why this is not simply "dismiss"
///
/// The overlay belongs to the desktop it opened on: the panel joins every Space, so left alone it
/// follows the user to the next desktop still listing the previous one's windows and still placed
/// where their cursor used to be. Worse, it stays *visible*, and a visible overlay turns the next
/// press of the shortcut into "close this" rather than "open here" — which reads as the switcher not
/// working on that desktop at all.
///
/// Dismissing fixes that and, on its own, causes the same complaint by the opposite route. The
/// notification arrives when a Space switch *lands*, while the trigger is a global tap that fires the
/// instant it is pressed. Switch desktop, reach straight for the switcher, and the two arrive in the
/// opposite order to the one they were performed in — measured at 3 ms — so a request the user had
/// just made is discarded by a transition that predates it.
///
/// The age of the presentation is what separates the two cases, and it is the only signal available:
/// there is no public way to ask which Space a window is on, and the notification carries nothing
/// about the transition it is reporting.
enum SpaceChangeResponse: Equatable {

    /// Nothing is on screen, so there is nothing to do but re-learn the desktop.
    case ignore

    /// The desktop changed under an overlay the user had been looking at. It is stale: take it down
    /// so the next press opens a fresh one here.
    case dismiss

    /// The change predates the overlay, so the user asked for the switcher on *this* desktop and the
    /// answer is to show it here rather than to throw the request away.
    case reopen

    /// - Parameters:
    ///   - presentedAt: when the overlay became visible.
    ///   - lastReopenAt: when a desktop change last caused a reopen. Reopening is bounded to once
    ///     per grace window, because a reopen resets `presentedAt` — without the bound a burst of
    ///     notifications could keep re-answering itself.
    ///   - grace: how soon after presenting a change is taken to have predated the overlay.
    static func resolve(
        isVisible: Bool,
        presentedAt: TimeInterval,
        lastReopenAt: TimeInterval,
        now: TimeInterval,
        grace: TimeInterval
    ) -> SpaceChangeResponse {
        guard isVisible else { return .ignore }
        guard now - presentedAt < grace else { return .dismiss }
        guard now - lastReopenAt > grace else { return .dismiss }
        return .reopen
    }
}
