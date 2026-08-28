import CoreGraphics

/// Type sizes for the spiral's middle, and how far each line may shrink before it gives up and
/// truncates instead.
///
/// ## Why shrinking, and why not all the way
///
/// The hub is about 192 points across at full size, so its usable width is the inscribed square —
/// roughly 136 points. Window titles are not written to that budget: "prod-giga-enhance-logs
/// (Channel) - Quattr Inc. - 2 new items - Slack" is an ordinary title and it does not fit at 15
/// points, so it arrived with its end cut off. The end is often the part that distinguishes it from
/// its neighbours, which is the whole reason the hub spends most of its room on the title.
///
/// Letting the text shrink to fit recovers most of those. Letting it shrink *without limit* would
/// trade one failure for a worse one: a 200-character title would technically fit, at a size nobody
/// can read, and unreadable-but-complete is not an improvement on readable-but-clipped. So each line
/// may shrink only to its own floor and truncates below that.
///
/// The floors are the ones already in use elsewhere in the overlay — 10 points for a primary label,
/// 9 for a secondary one — rather than new numbers invented here.
///
/// ## Why this is a type
///
/// The interesting part is arithmetic: a minimum *scale factor* is what SwiftUI takes, but a floor is
/// what actually matters, and the conversion between them depends on the size being scaled. Getting
/// it wrong produces text below the floor at some arrangement sizes and not others — invisible in a
/// diff, invisible in a screenshot of the one size you happened to look at, and caught by a sweep.
struct HubTypography: Equatable {

    /// Smallest a primary label may be drawn.
    static let primaryFloor: CGFloat = 10
    /// Smallest a secondary label may be drawn.
    static let secondaryFloor: CGFloat = 9

    /// The disc the caption is laid out inside: a source line, three title lines and a status
    /// line, at their floors, in the tightest case.
    ///
    /// Lives here rather than in the layout because it is a property of the type. `RadialLayout`
    /// reads it to floor how far the hub may shrink — the caption is drawn on the well's opaque
    /// core, and a hub small enough to push the type past that core spills it onto a transparent
    /// panel, where the desktop reads straight through the glyphs.
    static let captionDiameter: CGFloat = 124

    let titleSize: CGFloat
    let titleLines: Int
    let sourceSize: CGFloat
    let statusSize: CGFloat

    /// Whether the arrangement is large enough to spend a line on detail it could do without.
    let isRoomy: Bool

    init(radialScale: CGFloat) {
        let scale = max(0, radialScale)
        titleSize = max(Self.primaryFloor, 15 * scale)
        sourceSize = max(Self.secondaryFloor, 11 * scale)
        statusSize = max(Self.secondaryFloor, 10 * scale)
        isRoomy = scale > 0.8
        // Three at every size. This used to drop to two on a scaled-down arrangement, back when the
        // font shrank without a stated limit and the line count was standing in for a legibility
        // rule: four lines of tiny type says less than two lines of readable type. Now that each
        // line has an explicit floor, the line count is not doing that job any more, and taking a
        // line away only threw information out — a small arrangement is where the title is already
        // most likely to be clipped. Checked against the tightest case: three title lines with a
        // source line above and a status line below still sit inside a 124-point disc.
        titleLines = 3
    }

    /// How far the title may shrink, as SwiftUI's `minimumScaleFactor`.
    var titleMinimumScale: Double { Self.minimumScale(for: titleSize, floor: Self.primaryFloor) }
    var sourceMinimumScale: Double { Self.minimumScale(for: sourceSize, floor: Self.secondaryFloor) }
    var statusMinimumScale: Double { Self.minimumScale(for: statusSize, floor: Self.secondaryFloor) }

    /// The fraction of `size` that lands exactly on `floor`, clamped to something usable.
    ///
    /// Derived from the floor rather than fixed, because the sizes above are already scaled: a
    /// constant 0.67 would be right at full size and would take a scaled-down arrangement — where
    /// the size has already been clamped *to* the floor — below it.
    private static func minimumScale(for size: CGFloat, floor: CGFloat) -> Double {
        guard size > 0 else { return 1 }
        return Double(min(1, floor / size))
    }
}
