import Foundation
import Testing
@testable import PeekSwitchCore

@Suite("Angle math")
struct AngleMathTests {

    @Test("Normalising wraps both directions into a turn")
    func normalisedWraps() {
        #expect(abs(AngleMath.normalised(0)) < 0.0001)
        #expect(abs(AngleMath.normalised(2 * .pi)) < 0.0001)
        #expect(abs(AngleMath.normalised(-.pi / 2) - (3 * .pi / 2)) < 0.0001)
        #expect(abs(AngleMath.normalised(5 * .pi / 2) - (.pi / 2)) < 0.0001)
    }

    @Test("The shortest delta never takes the long way around")
    func shortestDeltaIsTheShortArc() {
        let delta = AngleMath.shortestDelta(from: 0.1, to: 2 * .pi - 0.1)
        #expect(delta < 0, "should go backwards across the branch cut")
        #expect(abs(delta) < .pi)
        #expect(abs(abs(delta) - 0.2) < 0.0001)
    }

    @Test("Unwrapping a target across the branch cut stays near the current angle")
    func unwrapTakesTheShortArc() {
        let current = 6.1
        let target = 0.1
        let unwrapped = AngleMath.unwrap(target, relativeTo: current)
        #expect(unwrapped > current, "0.1 is just ahead of 6.1 the short way")
        #expect(abs(unwrapped - current) < .pi)
        #expect(abs(AngleMath.shortestDelta(from: current, to: unwrapped)) < .pi)
    }

    @Test("Unwrapping an identical angle is a no-op")
    func unwrapOfSelfIsIdentity() {
        for angle in [-.pi / 2, 0.0, 1.2, 3.0, 6.2] {
            #expect(abs(AngleMath.unwrap(angle, relativeTo: angle) - angle) < 0.0001)
        }
    }

    /// The ring's first and last seats sit either side of the top. Interpolating their raw
    /// mid-angles would send the hotspot the long way around; unwrapping must not.
    @Test("Crossing the top of the ring stays a short hop")
    func crossingTheTopIsAShortHop() {
        let first = RadialLayout.startAngle + RadialLayout.sweep / 2
        let last = RadialLayout.startAngle + 7 * RadialLayout.sweep + RadialLayout.sweep / 2
        let hop = AngleMath.unwrap(first, relativeTo: last)
        #expect(abs(hop - last) < .pi / 2, "first seat should be a short step past the last")
    }
}
