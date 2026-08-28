import Foundation

/// Shortest-arc arithmetic for the hub ring's hotspot.
///
/// Linear interpolation of a raw angle takes the long way around whenever the selection
/// crosses the branch cut — sweeping from the last seat of a turn onto the first would send
/// the glow the long way around the ring. Unwrapping against the currently displayed angle
/// makes a spring on that value travel the short arc, which is the motion the pointer just
/// made.
enum AngleMath {

    static let turn = 2 * Double.pi

    /// Reduces an angle to `[0, 2π)`.
    static func normalised(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: turn)
        return remainder < 0 ? remainder + turn : remainder
    }

    /// Shortest signed delta from `from` to `to`, in `(-π, π]`.
    static func shortestDelta(from: Double, to: Double) -> Double {
        var delta = normalised(to - from)
        if delta > .pi { delta -= turn }
        return delta
    }

    /// `target` expressed near `current`, so interpolating the two takes the short arc.
    static func unwrap(_ target: Double, relativeTo current: Double) -> Double {
        current + shortestDelta(from: current, to: target)
    }
}
