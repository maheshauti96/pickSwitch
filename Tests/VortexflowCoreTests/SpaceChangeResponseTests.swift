import Foundation
import Testing
@testable import VortexflowCore

/// What a desktop change does to an overlay that is up, which has now been wrong in both directions.
///
/// Reported as "the switcher isn't opening on a new desktop; it works on the main one but fails on
/// others". Two separate causes produce that same sentence, and fixing either one alone leaves it:
/// an overlay left visible on the old desktop turns the next press into "close this", and dismissing
/// on every change throws away a request the user made while the transition was still landing.
struct SpaceChangeResponseTests {

    private static let grace: TimeInterval = 1.0

    private func resolve(
        isVisible: Bool = true,
        age: TimeInterval,
        sinceLastReopen: TimeInterval = 1_000
    ) -> SpaceChangeResponse {
        let now: TimeInterval = 10_000
        return SpaceChangeResponse.resolve(
            isVisible: isVisible,
            presentedAt: now - age,
            lastReopenAt: now - sinceLastReopen,
            now: now,
            grace: Self.grace
        )
    }

    @Test func nothingOnScreenNeedsNothingDone() {
        #expect(resolve(isVisible: false, age: 0) == .ignore)
        // Even a long-stale timestamp: with no overlay up there is nothing to dismiss or reopen.
        #expect(resolve(isVisible: false, age: 5_000) == .ignore)
    }

    /// The measured race, to the millisecond it was observed at: the overlay presented and the
    /// notification landed 3 ms later, describing a switch that had begun before the user pressed.
    @Test func aChangeLandingJustAfterPresentingReopens() {
        #expect(resolve(age: 0.003) == .reopen)
    }

    /// A Space switch animates for a few hundred milliseconds, so the notification can trail the
    /// trigger by that much and still describe something that happened first.
    @Test func aChangeWithinTheGraceWindowReopens() {
        for age in [0.0, 0.05, 0.3, 0.9] {
            #expect(resolve(age: age) == .reopen, "age \(age) should reopen")
        }
    }

    /// An overlay the user has been looking at for a while really did go stale under them, and that
    /// is the case the dismissal was introduced for.
    @Test func aChangeUnderASettledOverlayDismisses() {
        for age in [1.01, 2.0, 30.0] {
            #expect(resolve(age: age) == .dismiss, "age \(age) should dismiss")
        }
    }

    /// The bound that stops the fix from feeding itself. Reopening resets the presentation clock, so
    /// without this a stream of notifications would keep finding a freshly-presented overlay and keep
    /// reopening it.
    @Test func reopeningIsBoundedToOncePerGraceWindow() {
        #expect(resolve(age: 0.003, sinceLastReopen: 0.004) == .dismiss)
        #expect(resolve(age: 0.003, sinceLastReopen: 0.5) == .dismiss)
        // Past the window it is available again.
        #expect(resolve(age: 0.003, sinceLastReopen: 1.5) == .reopen)
    }

    /// The boundary itself, stated rather than left to rounding: at exactly the grace period the
    /// overlay counts as settled, so the older behaviour applies.
    @Test func theBoundaryFallsOnTheDismissSide() {
        #expect(resolve(age: Self.grace) == .dismiss)
        #expect(resolve(age: Self.grace - 0.001) == .reopen)
    }
}
