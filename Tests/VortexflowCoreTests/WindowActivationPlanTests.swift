import Testing
@testable import VortexflowCore

@Suite("Window activation plan")
struct WindowActivationPlanTests {

    @Test("a window already on this desktop is raised in place")
    func sameDisplayOnSpaceRaisesInPlace() {
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: true,
                windowDisplayNumber: 1,
                lookingAtDisplayNumber: 1
            ) == .raiseInPlace
        )
    }

    @Test("a window on another Space of this display activates first")
    func sameDisplayOffSpaceActivatesFirst() {
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: false,
                windowDisplayNumber: 2,
                lookingAtDisplayNumber: 2
            ) == .activateThenRaise
        )
    }

    @Test("a window on the other monitor is moved here")
    func otherDisplayMovesHere() {
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: true,
                windowDisplayNumber: 2,
                lookingAtDisplayNumber: 1
            ) == .moveThenRaise
        )
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: false,
                windowDisplayNumber: 1,
                lookingAtDisplayNumber: 2
            ) == .moveThenRaise
        )
    }

    @Test("a stale frame that sits on no display is moved here")
    func unknownWindowDisplayMovesHere() {
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: false,
                windowDisplayNumber: nil,
                lookingAtDisplayNumber: 1
            ) == .moveThenRaise
        )
    }

    @Test("without a looking-at display, off-space still activates first")
    func noLookingAtDisplayActivatesOffSpace() {
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: false,
                windowDisplayNumber: 2,
                lookingAtDisplayNumber: nil
            ) == .activateThenRaise
        )
        #expect(
            WindowActivationPlan.resolve(
                isOnActiveSpace: true,
                windowDisplayNumber: 2,
                lookingAtDisplayNumber: nil
            ) == .raiseInPlace
        )
    }
}
