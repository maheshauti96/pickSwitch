import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// The "the window is going *there*" animation.
///
/// The decision of whether to animate, how long for, and in which direction is pure geometry,
/// so it is tested against synthetic arrangements rather than by watching the screen.
@Suite("Window transition")
struct WindowTransitionTests {

    /// The development machine's arrangement, in AppKit coordinates: an external display at the
    /// origin carrying the menu bar, with the laptop to its left. Worth using as the fixture
    /// because it is asymmetric — a bug that assumes displays start at x = 0 survives a tidier
    /// layout.
    private static let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private static let laptop = CGRect(x: -1512, y: 62, width: 1512, height: 982)
    private static let displays = [external, laptop]

    private func plan(
        card: CGRect,
        target: CGRect,
        reduceMotion: Bool = false
    ) -> WindowTransition? {
        WindowTransition.plan(
            cardFrame: card,
            targetFrame: target,
            displayFrames: Self.displays,
            reduceMotion: reduceMotion
        )
    }

    // MARK: - Whether to animate

    @Test("A window on the same display animates in place")
    func sameDisplayAnimatesInPlace() {
        let card = CGRect(x: 800, y: 500, width: 208, height: 152)
        let target = CGRect(x: 200, y: 100, width: 1400, height: 900)

        guard let transition = plan(card: card, target: target) else {
            Issue.record("a same-display switch should animate")
            return
        }
        #expect(!transition.crossesDisplay)
        #expect(transition.duration == WindowTransition.sameDisplayDuration)
        #expect(transition.start == card)
        #expect(transition.end == target)
    }

    /// The case the feature exists for: the user cannot see the destination, so the animation
    /// has to travel there and take long enough to be followed.
    @Test("A window on another display animates across, and more slowly")
    func crossDisplayAnimatesAcross() {
        // Card on the external display, window on the laptop to its left.
        let card = CGRect(x: 900, y: 500, width: 208, height: 152)
        let target = CGRect(x: -1400, y: 120, width: 1300, height: 850)

        guard let transition = plan(card: card, target: target) else {
            Issue.record("a cross-display switch should animate")
            return
        }
        #expect(transition.crossesDisplay)
        #expect(transition.duration == WindowTransition.crossDisplayDuration)
        // Long enough to follow across the gap.
        #expect(transition.duration > WindowTransition.sameDisplayDuration)
    }

    /// Requirement 15.1. The whole effect is decorative motion, which is precisely what the
    /// setting asks to be rid of.
    @Test("Reduce Motion suppresses the animation entirely")
    func reduceMotionSuppressesAnimation() {
        let card = CGRect(x: 900, y: 500, width: 208, height: 152)
        let target = CGRect(x: -1400, y: 120, width: 1300, height: 850)

        #expect(plan(card: card, target: target, reduceMotion: true) == nil)
        // And it is not merely shortened.
        #expect(plan(card: card, target: target) != nil)
    }

    @Test("A window too small to see is not animated into")
    func tinyTargetIsNotAnimated() {
        let card = CGRect(x: 900, y: 500, width: 208, height: 152)
        #expect(plan(card: card, target: CGRect(x: 100, y: 100, width: 20, height: 20)) == nil)
        #expect(plan(card: card, target: .zero) == nil)
    }

    @Test("A card with no size is not animated")
    func emptyCardIsNotAnimated() {
        let target = CGRect(x: 200, y: 100, width: 1400, height: 900)
        #expect(plan(card: .zero, target: target) == nil)
    }

    /// Nothing to explain when the card already covers the window.
    @Test("A card already over the window is not animated")
    func coincidentFramesAreNotAnimated() {
        let frame = CGRect(x: 300, y: 300, width: 800, height: 600)
        #expect(plan(card: frame, target: frame) == nil)
    }

    // MARK: - Activation timing

    /// The bug this guards: the window was raised before the ghost started, so the user saw the
    /// window arrive and *then* an animation explaining where it went.
    @Test("The window is raised partway through the animation, not before it")
    func windowIsRaisedPartwayThrough() {
        let card = CGRect(x: 900, y: 500, width: 208, height: 152)
        let target = CGRect(x: 200, y: 100, width: 1400, height: 900)

        guard let transition = plan(card: card, target: target) else {
            Issue.record("expected an animation")
            return
        }
        #expect(transition.activationDelay > 0)
        // Slightly early, so the real window is already there as the ghost fades onto it.
        #expect(transition.activationDelay < transition.duration)
        #expect(transition.activationDelay > transition.duration / 2)
    }

    /// A longer journey earns a longer hold, or the cross-display animation would still be
    /// mid-flight when the window appeared.
    @Test("Crossing displays holds the window back for longer")
    func crossingDisplaysHoldsLonger() {
        let card = CGRect(x: 900, y: 500, width: 208, height: 152)

        let sameDisplay = plan(card: card, target: CGRect(x: 200, y: 100, width: 1400, height: 900))
        let crossDisplay = plan(card: card, target: CGRect(x: -1400, y: 120, width: 1300, height: 850))

        guard let sameDisplay, let crossDisplay else {
            Issue.record("expected both to animate")
            return
        }
        #expect(crossDisplay.activationDelay > sameDisplay.activationDelay)
        // Still short enough not to feel broken.
        #expect(crossDisplay.activationDelay < 0.5)
    }

    // MARK: - Direction

    /// The direction is what an accessibility announcement can say out loud, since a moving
    /// picture tells VoiceOver nothing.
    @Test("Direction follows the dominant axis of travel")
    func directionFollowsDominantAxis() {
        let card = CGRect(x: 900, y: 500, width: 200, height: 150)

        // Onto the laptop, which sits to the left.
        #expect(plan(card: card, target: CGRect(x: -1400, y: 120, width: 1300, height: 850))?
            .direction == .left)
        // Further right on the same display.
        #expect(plan(card: card, target: CGRect(x: 1500, y: 480, width: 400, height: 300))?
            .direction == .right)
        // AppKit's y grows upward, so a larger y is up the screen.
        #expect(plan(card: card, target: CGRect(x: 880, y: 900, width: 300, height: 160))?
            .direction == .up)
        #expect(plan(card: card, target: CGRect(x: 880, y: 20, width: 300, height: 160))?
            .direction == .down)
    }

    /// A window in roughly the same place should not claim to have moved somewhere.
    @Test("A barely-moved window reports no direction")
    func barelyMovedWindowHasNoDirection() {
        let card = CGRect(x: 500, y: 500, width: 208, height: 152)
        let target = CGRect(x: 496, y: 494, width: 220, height: 170)
        #expect(plan(card: card, target: target)?.direction == .inPlace)
    }

    // MARK: - Coordinate conversion

    /// `WindowEntry.frame` is Quartz (top-left origin, y down); panels are placed in AppKit
    /// (bottom-left origin, y up). Getting this backwards would fly the ghost to a mirrored
    /// position, which on a stacked arrangement lands it on the wrong display entirely.
    @Test("Quartz frames convert to AppKit frames")
    func quartzConvertsToAppKit() {
        let primaryHeight: CGFloat = 1080

        // A window filling the main display: identical in both systems.
        let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(ScreenGeometry.appKitFrame(fromQuartz: full, primaryHeight: primaryHeight) == full)

        // The laptop's real Quartz frame from the development machine.
        let laptopQuartz = CGRect(x: -1512, y: 36, width: 1512, height: 982)
        let converted = ScreenGeometry.appKitFrame(
            fromQuartz: laptopQuartz,
            primaryHeight: primaryHeight
        )
        #expect(converted == CGRect(x: -1512, y: 62, width: 1512, height: 982))
    }

    @Test("The conversion is its own inverse")
    func conversionRoundTrips() {
        let primaryHeight: CGFloat = 1080
        for frame in [
            CGRect(x: 0, y: 0, width: 800, height: 600),
            CGRect(x: -1512, y: 36, width: 1512, height: 982),
            CGRect(x: 400, y: 720, width: 1200, height: 300),
        ] {
            let there = ScreenGeometry.appKitFrame(fromQuartz: frame, primaryHeight: primaryHeight)
            let back = ScreenGeometry.quartzFrame(fromAppKit: there, primaryHeight: primaryHeight)
            #expect(back == frame)
        }
    }

    /// A window straddling two displays belongs to whichever holds most of it, matching how
    /// macOS itself decides — so nudging a window across a boundary should not flip the
    /// animation between "in place" and "across displays" until it has actually moved over.
    @Test("A straddling window is judged by its larger share")
    func straddlingWindowJudgedByLargerShare() {
        let cardOnExternal = CGRect(x: 900, y: 500, width: 208, height: 152)

        // Mostly on the external display, where the card is.
        let mostlyExternal = CGRect(x: -200, y: 300, width: 800, height: 500)
        #expect(plan(card: cardOnExternal, target: mostlyExternal)?.crossesDisplay == false)

        // Mostly on the laptop.
        let mostlyLaptop = CGRect(x: -700, y: 300, width: 800, height: 500)
        #expect(plan(card: cardOnExternal, target: mostlyLaptop)?.crossesDisplay == true)
    }

    /// A window parked off every display should still animate rather than being dropped; it is
    /// simply not attributable to a screen.
    @Test("A window on no display still animates")
    func offscreenWindowStillAnimates() {
        let card = CGRect(x: 900, y: 500, width: 208, height: 152)
        let nowhere = CGRect(x: 9000, y: 9000, width: 600, height: 400)
        #expect(plan(card: card, target: nowhere) != nil)
    }
}
