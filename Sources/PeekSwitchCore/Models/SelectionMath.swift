import Foundation

/// Selection index arithmetic for the strip (Requirement 4.3–4.6).
///
/// Split out from the view so the wrap-around rules are testable in isolation —
/// off-by-one and wrap bugs in a switcher are immediately felt by the user and
/// annoying to catch by hand.
enum SelectionMath {

    /// Move `current` by `delta` positions across `count` cards, wrapping at both
    /// ends. Returns `nil` when there is nothing to select.
    ///
    /// Uses a true modulo (not `%`, which keeps the sign of the dividend in Swift)
    /// so a large negative delta wraps correctly instead of producing a negative
    /// index.
    static func advance(current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else {
            // No selection yet: a forward step lands on the first card, a
            // backward step on the last.
            return delta >= 0 ? 0 : count - 1
        }
        let raw = current + delta
        let wrapped = ((raw % count) + count) % count
        return wrapped
    }

    /// Clamp an index into `0..<count`, or `nil` if the strip is empty. Used after
    /// the window list changes underneath a live selection.
    static func clamp(_ index: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return nil }
        return min(max(index, 0), count - 1)
    }

    /// The card selected when the overlay opens.
    ///
    /// Index 1 — the second card — not index 0. The frontmost window is pinned
    /// leftmost (Requirement 2.4), and it is the window the user is already
    /// looking at, so preselecting it would make a quick press-and-release a no-op.
    /// Preselecting the second card turns that same flick into "go back to the
    /// window I was just in", which is the single most common switch
    /// (Requirement 2.5). With only one window open there is nothing to go back
    /// to, so it falls through to index 0.
    static func initialSelection(count: Int) -> Int? {
        guard count > 0 else { return nil }
        return count > 1 ? 1 : 0
    }

    /// Collapse a continuous scroll delta into whole card steps (Requirement 4.2).
    ///
    /// A Magic Mouse or an MX Master free-spinning wheel emits a stream of small
    /// fractional deltas; a notched wheel emits one large one. Accumulating into a
    /// threshold gives both the same "one notch, one card" feel.
    struct ScrollAccumulator {
        /// Points of scroll travel that equal one card step. Tuned so a single
        /// notched click (typically ~10 points) advances exactly one card.
        static let stepThreshold: Double = 8

        private var accumulated: Double = 0

        /// Feed a raw scroll delta, get back how many whole cards to move.
        mutating func consume(delta: Double) -> Int {
            // Direction flip: drop the residue so reversing feels immediate
            // rather than having to first pay back the leftover travel.
            if accumulated != 0, (accumulated < 0) != (delta < 0), delta != 0 {
                accumulated = 0
            }
            accumulated += delta
            let steps = Int((abs(accumulated) / Self.stepThreshold).rounded(.down))
            guard steps > 0 else { return 0 }
            let signum = accumulated < 0 ? -1 : 1
            accumulated -= Double(signum * steps) * Self.stepThreshold
            return steps * signum
        }

        mutating func reset() { accumulated = 0 }
    }
}
