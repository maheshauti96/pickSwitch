import CoreGraphics
import Foundation

/// Timing for the cards' entrance.
///
/// ## Why the total is capped
///
/// A staggered reveal is the one piece of polish that can make a switcher measurably worse.
/// The overlay exists to be read and dismissed inside a second, so a fixed per-card delay is
/// a trap: pleasant at four windows, and a card still sliding in half a second later at
/// twenty-five. `delay(forOffset:count:reduceMotion:)` therefore compresses the step so the
/// last card has arrived within `totalWindow` however many there are.
///
/// The animation is presentation only. Selection, hit-testing and activation all run off
/// `OverlayLayout`'s arithmetic, which knows nothing about this, so a click during the reveal
/// lands on the card whose seat was clicked whether or not it has finished fading in. That is
/// the right trade: the alternative is an overlay that ignores input while it looks pretty.
enum OverlayReveal {

    /// Preferred delay between one card and the next.
    static let step: Double = 0.028

    /// Every card must have started arriving within this, however long the list is.
    static let totalWindow: Double = 0.20

    /// How long one card takes to arrive.
    static let duration: Double = 0.22

    /// Cards start slightly small, so they read as arriving rather than merely fading.
    static let initialScale: CGFloat = 0.86

    /// The hub caption follows the wedges in rather than competing with them.
    static let hubDelay: Double = 0.08

    /// How long the hub takes to cross-fade from one window's title to the next.
    ///
    /// Deliberately quicker than a card's arrival, and quicker than a pointer can cross a wedge.
    /// The caption changes every time the selection moves, which on a ring is continuous — sweeping
    /// around it fires one of these per wedge. At the length of a normal transition they would queue
    /// up and the title would smear into an unreadable blur, which is worse than the hard cut it
    /// replaces. Short enough to soften the swap, short enough to keep up.
    static let captionChange: Double = 0.12

    /// When the card at `offset` in the visible run should start.
    ///
    /// - Parameters:
    ///   - offset: position within the visible run, not the index of the entry.
    ///   - count: how many cards are on screen.
    ///   - reduceMotion: Requirement 15.1 — everything arrives at once instead.
    static func delay(forOffset offset: Int, count: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion, count > 1, offset > 0 else { return 0 }
        let perCard = min(step, totalWindow / Double(count - 1))
        return Double(min(offset, count - 1)) * perCard
    }
}
