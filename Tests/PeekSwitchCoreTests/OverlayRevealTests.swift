import Testing
@testable import PeekSwitchCore

/// The cards' staggered entrance.
///
/// Worth testing as arithmetic rather than leaving to the eye, because the failure mode is not
/// "it looks wrong" but "the switcher got slower", and that only shows up with a lot of windows
/// open — which is exactly when nobody wants to wait.
@Suite("Overlay reveal")
struct OverlayRevealTests {

    @Test("The first card arrives immediately")
    func firstCardHasNoDelay() {
        #expect(OverlayReveal.delay(forOffset: 0, count: 8, reduceMotion: false) == 0)
        // A single card is not a sequence, so it has nothing to be staggered against.
        #expect(OverlayReveal.delay(forOffset: 0, count: 1, reduceMotion: false) == 0)
    }

    @Test("Cards arrive in order")
    func cardsArriveInOrder() {
        var previous = -1.0
        for offset in 0..<8 {
            let delay = OverlayReveal.delay(forOffset: offset, count: 8, reduceMotion: false)
            #expect(delay > previous)
            previous = delay
        }
    }

    /// The whole point of the cap. A fixed 28ms step is pleasant at four windows and a card
    /// still arriving 700ms later at twenty-five, which would make the switcher feel slower
    /// the more it has to show.
    @Test("The last card arrives within the budget however many there are", arguments: [2, 5, 9, 16, 25, 60])
    func lastCardStaysWithinBudget(count: Int) {
        let last = OverlayReveal.delay(forOffset: count - 1, count: count, reduceMotion: false)
        #expect(last <= OverlayReveal.totalWindow + 0.0001, "\(count) cards took \(last)s")
        #expect(last > 0)

        // Every card is on screen by the time the budget plus one card's animation is up.
        #expect(last + OverlayReveal.duration <= OverlayReveal.totalWindow + OverlayReveal.duration)
    }

    /// Short lists get the full per-card step; only long ones are compressed.
    @Test("Small counts keep the preferred step")
    func smallCountsUseThePreferredStep() {
        // Eight cards at 28ms is 196ms, just inside the 200ms budget.
        #expect(isCloseDouble(OverlayReveal.delay(forOffset: 1, count: 8, reduceMotion: false), OverlayReveal.step))

        // Twenty-five cannot be, so the step shrinks.
        let compressed = OverlayReveal.delay(forOffset: 1, count: 25, reduceMotion: false)
        #expect(compressed < OverlayReveal.step)
        #expect(compressed > 0)
    }

    /// Requirement 15.1: everything arrives at once instead of sequencing.
    @Test("Reduce Motion removes the stagger entirely")
    func reduceMotionHasNoStagger() {
        for offset in 0..<25 {
            #expect(OverlayReveal.delay(forOffset: offset, count: 25, reduceMotion: true) == 0)
        }
    }

    /// An offset past the end is a caller bug, not a reason to schedule an animation a minute
    /// out. It clamps.
    @Test("An out-of-range offset clamps to the last card")
    func offsetBeyondTheEndClamps() {
        let last = OverlayReveal.delay(forOffset: 7, count: 8, reduceMotion: false)
        #expect(OverlayReveal.delay(forOffset: 99, count: 8, reduceMotion: false) == last)
    }

    /// The hub follows the wedges in rather than arriving with them, and still lands inside
    /// the same budget.
    @Test("The hub caption trails the wedges")
    func hubTrailsTheWedges() {
        #expect(OverlayReveal.hubDelay > 0)
        #expect(OverlayReveal.hubDelay <= OverlayReveal.totalWindow)
    }

    /// Cards grow into place from slightly small. Zero would be a card that appears from a
    /// point, which reads as a glitch; anything near 1 is not worth animating.
    @Test("Cards start small but not from nothing")
    func initialScaleIsSubtle() {
        #expect(OverlayReveal.initialScale > 0.5)
        #expect(OverlayReveal.initialScale < 1)
    }

    private func isCloseDouble(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
