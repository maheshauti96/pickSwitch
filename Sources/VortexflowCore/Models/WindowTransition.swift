import CoreGraphics
import Foundation

/// The "the window is going *there*" animation shown when a switch is committed.
///
/// ## What is actually animated
///
/// Not the window. VortexFlow cannot animate another application's window — `AXRaise` raises
/// it immediately and offers no hook — so this describes a ghost: the card's thumbnail, flown
/// and scaled from where the card was to where the window actually is. The real activation
/// happens at once underneath, so the switch is no slower than before; the ghost is purely an
/// explanation of what just happened.
///
/// ## Why the cross-display case needs its own timing
///
/// On one display the card is usually near the window, so a short animation reads fine. Across
/// displays the ghost may travel two thousand points, and at the same duration that is a blur
/// — which defeats the entire purpose, since the point is for the user to *see* which screen
/// the window went to. So travel distance sets the duration, within bounds.
struct WindowTransition: Equatable {

    /// Where the ghost starts: the card the user clicked, in AppKit screen coordinates.
    let start: CGRect
    /// Where it ends: the target window's frame, in AppKit screen coordinates.
    let end: CGRect
    let duration: TimeInterval
    /// True when the window is on a different display from the card, which is the case the
    /// animation exists for.
    let crossesDisplay: Bool

    /// Same display: quick, because the distance is short and the user already knows where
    /// they are looking.
    static let sameDisplayDuration: TimeInterval = 0.20
    /// Different display: slow enough to follow across the gap.
    static let crossDisplayDuration: TimeInterval = 0.42
    /// A window smaller than this in either axis is not worth animating into; the ghost would
    /// be a speck.
    static let minimumTargetSize: CGFloat = 40

    /// How far through the animation the real window should appear.
    ///
    /// Not at the end. The ghost fades as it lands, so bringing the window forward slightly
    /// early means it is already there as the ghost dissolves onto it — the ghost reads as
    /// *becoming* the window. Waiting for the full duration instead leaves a visible gap where
    /// the animation has finished and nothing has happened yet.
    static let activationDelayFraction: TimeInterval = 0.72

    /// How long to hold the real switch back so the animation is seen first.
    ///
    /// This deliberately makes switching slower — roughly 150 ms on one display, 300 ms across
    /// two. Requirement 7.1 wanted activation to start immediately so the switch read as
    /// instant, and that is the right default when there is nothing to show; but once an
    /// animation is being drawn, activating first makes the window appear *before* the
    /// animation explaining where it went, which is worse than the delay.
    var activationDelay: TimeInterval { duration * Self.activationDelayFraction }

    /// Decide whether and how to animate.
    ///
    /// - Parameters:
    ///   - cardFrame: the clicked card, in AppKit screen coordinates.
    ///   - targetFrame: the window's frame, in AppKit screen coordinates.
    ///   - displayFrames: every display, in AppKit screen coordinates, to work out whether the
    ///     two frames are on the same screen.
    ///   - reduceMotion: Requirement 15.1. When set, there is no animation at all — the whole
    ///     effect is decorative motion, which is exactly what the setting asks to remove.
    /// - Returns: `nil` when no animation should be shown.
    static func plan(
        cardFrame: CGRect,
        targetFrame: CGRect,
        displayFrames: [CGRect],
        reduceMotion: Bool
    ) -> WindowTransition? {
        guard !reduceMotion else { return nil }
        guard targetFrame.width >= minimumTargetSize, targetFrame.height >= minimumTargetSize else {
            return nil
        }
        guard cardFrame.width > 0, cardFrame.height > 0 else { return nil }

        // Nothing to explain when the card is already sitting on top of the window.
        guard !cardFrame.equalTo(targetFrame) else { return nil }

        let cardDisplay = display(containing: cardFrame, in: displayFrames)
        let targetDisplay = display(containing: targetFrame, in: displayFrames)
        let crosses = cardDisplay != targetDisplay

        return WindowTransition(
            start: cardFrame,
            end: targetFrame,
            duration: crosses ? crossDisplayDuration : sameDisplayDuration,
            crossesDisplay: crosses
        )
    }

    /// Which way the ghost travels, for anything that wants to describe the motion — the
    /// accessibility announcement, primarily, since a moving picture says nothing to
    /// VoiceOver.
    enum Direction: String {
        case left, right, up, down, inPlace
    }

    var direction: Direction {
        let dx = end.midX - start.midX
        let dy = end.midY - start.midY

        // Movement below this is the window being in roughly the same place, so calling it
        // "left" or "up" would be noise.
        let threshold: CGFloat = 24
        guard abs(dx) > threshold || abs(dy) > threshold else { return .inPlace }

        if abs(dx) >= abs(dy) {
            return dx < 0 ? .left : .right
        }
        // AppKit's y grows upward.
        return dy > 0 ? .up : .down
    }

    /// The display a frame belongs to: the one holding most of it, matching how macOS itself
    /// decides. `nil` when it overlaps none, which happens for windows parked off-screen.
    private static func display(containing frame: CGRect, in displayFrames: [CGRect]) -> Int? {
        var best: Int?
        var bestArea: CGFloat = 0

        for (index, display) in displayFrames.enumerated() {
            let overlap = display.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = index
            }
        }
        return best
    }
}

/// Converting between the two coordinate systems this app straddles.
///
/// `WindowEntry.frame` is Quartz — origin at the top-left of the main display, y downward,
/// which is what both Accessibility and `CGWindowList` report. Panels are placed in AppKit
/// coordinates, with the origin at the *bottom*-left and y upward. Both systems share the same
/// point on the main display, so the conversion is a flip about that display's height.
enum ScreenGeometry {

    /// - Parameter primaryHeight: height of the display whose origin is (0, 0) — the one
    ///   carrying the menu bar.
    static func appKitFrame(fromQuartz frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    static func quartzFrame(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
