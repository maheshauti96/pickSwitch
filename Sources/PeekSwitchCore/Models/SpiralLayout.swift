import CoreGraphics
import Foundation

/// Pure geometry for the spiral arrangement: wedge-shaped seats winding outward around a
/// hollow hub.
///
/// ## Why a spiral rather than a ring
///
/// The ring this replaces put every window at one radius and spent the whole middle of the
/// panel on a preview of the window that was already highlighted — the largest area on
/// screen showing the thing the user had by definition already found. It also capped out at
/// eight seats, so a ninth window was paged out of sight.
///
/// A spiral fixes both. Seats have a *fixed* angular width and the radius grows a little
/// with each one, so the arc lengthens as windows are added instead of the seats spreading
/// apart, and after a full turn it simply continues outward rather than running out of
/// room. Three windows read as three wedges at the top, not as three lonely cards at 120°
/// to each other, and twenty-plus windows all stay on screen.
///
/// ## Why angular hit-testing
///
/// A wedge is not a rectangle, and the point of aiming a pointer at a ring is that a flick
/// in roughly the right direction lands on the right thing. `seatOffset(atContentPoint:)`
/// resolves a point by angle and radius, so the entire wedge is live all the way to its
/// corners with no dead gaps between neighbours — which a bounding-box test could not do,
/// since the boxes of adjacent wedges overlap heavily.
///
/// Everything here is a value type with no AppKit dependency, so all of it is directly
/// unit-testable.
struct SpiralLayout: Equatable, Sendable {

    // MARK: - Fixed metrics

    /// Radius of the hollow middle.
    ///
    /// Big enough to caption the selected window inside it, which the arrangement needs:
    /// wedges are too narrow for a window title, so three windows of one application are
    /// three identical icons until something spells out which is which.
    static let hubRadius: CGFloat = 94

    /// Radial depth of a seat — an icon plus a line of text, plus breathing room.
    static let ringThickness: CGFloat = 108

    /// Clearance between one turn of the spiral and the next.
    static let turnGap: CGFloat = 9

    /// Seats in a full turn. Eight gives each one 45°.
    ///
    /// Set by what has to fit inside a wedge rather than by how many windows one turn should
    /// hold. `contentSize` derives the largest upright box that fits a wedge at any angle on
    /// the ring, and at twelve seats to a turn that box is 45 × 47 — too small for an
    /// application icon with a name under it. Eight yields 75 × 66, which holds both, and it
    /// makes each seat a 45° target, which is an easier flick besides.
    static let seatsPerTurn = 8

    /// Two full turns. Past this the outermost wedges are further from the pointer than
    /// crossing the screen to the window itself would be.
    static let maxSeats = 16

    /// Below three the arc stops reading as an arc, so it never reduces further even on an
    /// implausibly small display.
    static let minimumSeats = 3

    /// Space between the outermost wedge and the panel edge.
    static let padding: CGFloat = 18

    /// Angular gap between neighbouring wedges, so they read as separate cards rather than
    /// as one striped disc. Roughly 1.4°.
    static let wedgeGap: Double = 0.024

    /// Angle of the first seat. Straight up: the top of a ring is the one position a user
    /// can find without looking, and the list is ordered by recency, so the most recent
    /// window belongs there.
    static let startAngle: Double = -.pi / 2

    /// Clearance between a seat's contents and the wedge that draws them.
    static let contentMargin: CGFloat = 4

    /// Height a seat's contents want: an icon with a name under it.
    static let preferredContentHeight: CGFloat = 66

    // MARK: - Content box

    /// The largest half-diagonal a seat's contents may have.
    ///
    /// A wedge is not a rectangle, and its contents are drawn upright rather than rotated to
    /// follow the ring — rotated 11pt labels are not worth reading. An upright box therefore
    /// meets the wedge at a different angle at every seat: at the top of the ring its width
    /// runs along the arc, and at three o'clock that same width runs *radially*, across the
    /// wedge's depth instead.
    ///
    /// Sizing against the box's circumscribed circle sidesteps the orientation entirely. If
    /// that circle fits the wedge then so does the box, at any angle, so one size serves every
    /// seat — which also keeps the icons uniform, and a ring is quick to scan only while they
    /// are. The circle fits when it clears the two bounding rays and stays within the
    /// annulus, and the tighter of those two bounds is this.
    static var contentRadius: CGFloat {
        let innerMidRadius = innerRadius(atSeat: 0) + ringThickness / 2
        let ray = innerMidRadius * CGFloat(sin((sweep - wedgeGap) / 2))
        return min(ringThickness / 2, ray) - contentMargin
    }

    /// The upright box a seat's contents are drawn in. The same for every seat.
    static var contentSize: CGSize {
        let diagonal = contentRadius * 2
        // Height first, since the icon and its label are what set it; width takes whatever
        // the diagonal has left.
        let height = min(preferredContentHeight, diagonal * 0.72)
        let width = (diagonal * diagonal - height * height).squareRoot()
        return CGSize(width: width, height: height)
    }

    // MARK: - Inputs

    let cardCount: Int
    let selectedIndex: Int?
    /// Width the spiral may occupy, already excluding insets.
    let availableContentWidth: CGFloat
    /// Height the spiral may occupy, already excluding insets.
    let availableContentHeight: CGFloat

    // MARK: - Derived scalars

    /// Angular width of one seat, gaps included.
    static var sweep: Double { 2 * .pi / Double(seatsPerTurn) }

    /// How much further out each successive seat sits. One full turn of these adds exactly
    /// one ring thickness plus its gap, which is what makes the turns nest without
    /// overlapping.
    static var radialStep: CGFloat { (ringThickness + turnGap) / CGFloat(seatsPerTurn) }

    static func innerRadius(atSeat offset: Int) -> CGFloat {
        hubRadius + CGFloat(max(0, offset)) * radialStep
    }

    static func outerRadius(atSeat offset: Int) -> CGFloat {
        innerRadius(atSeat: offset) + ringThickness
    }

    /// How many windows the spiral shows at once.
    ///
    /// Bounded by `maxSeats` and then by the display: each extra seat pushes the outermost
    /// radius out by `radialStep`, so a small screen simply winds fewer turns and
    /// `visibleRange` pages through the rest — the same bargain the grid and list make.
    ///
    /// The `minimumSeats` floor can overflow a genuinely tiny display. That is deliberate
    /// and matches the ring it replaces: a clipped arc is still usable, whereas two seats
    /// is not an arc at all.
    var seats: Int {
        let desired = min(cardCount, Self.maxSeats)
        guard desired > Self.minimumSeats else { return max(0, desired) }

        let limit = min(availableContentWidth, availableContentHeight) / 2 - Self.padding
        var fitted = desired
        while fitted > Self.minimumSeats, Self.outerRadius(atSeat: fitted - 1) > limit {
            fitted -= 1
        }
        return fitted
    }

    /// Radius of the outermost visible wedge.
    var outerRadius: CGFloat {
        Self.outerRadius(atSeat: max(0, seats - 1))
    }

    /// Square, because the spiral is only ever as wide as it is tall.
    var panelSize: CGSize {
        let side = (outerRadius + Self.padding) * 2
        return CGSize(width: side, height: side)
    }

    var centre: CGPoint {
        CGPoint(x: panelSize.width / 2, y: panelSize.height / 2)
    }

    /// The hollow middle, as the square that bounds it.
    ///
    /// A rectangle is enough for what this is used for. Hit-testing resolves wedges before
    /// it considers the hub, and the corners of this square fall inside the innermost
    /// wedges, so those points are claimed by a wedge before the hub ever sees them.
    var hubFrame: CGRect {
        CGRect(
            x: centre.x - Self.hubRadius,
            y: centre.y - Self.hubRadius,
            width: Self.hubRadius * 2,
            height: Self.hubRadius * 2
        )
    }

    // MARK: - Seats

    /// One wedge, in panel-content coordinates with a top-left origin.
    struct Seat: Equatable, Sendable {
        /// Position in the visible run, not the index of the entry it shows.
        let offset: Int
        /// Clockwise from `startAngle`. Angles grow clockwise because the y axis points
        /// down in this coordinate space.
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        /// Where the icon and label go: an upright rectangle centred in the wedge. The
        /// wedge is the shape and the hit area; this is the box its contents live in.
        let contentFrame: CGRect

        var midAngle: Double { (startAngle + endAngle) / 2 }
        var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }
    }

    func seat(at offset: Int) -> Seat {
        let slot = offset % Self.seatsPerTurn
        let start = Self.startAngle + Double(slot) * Self.sweep + Self.wedgeGap / 2
        let end = Self.startAngle + Double(slot + 1) * Self.sweep - Self.wedgeGap / 2
        let inner = Self.innerRadius(atSeat: offset)
        let outer = Self.outerRadius(atSeat: offset)

        let midAngle = (start + end) / 2
        let midRadius = (inner + outer) / 2
        let origin = centre
        let position = CGPoint(
            x: origin.x + midRadius * CGFloat(cos(midAngle)),
            y: origin.y + midRadius * CGFloat(sin(midAngle))
        )

        let size = Self.contentSize
        let width = size.width
        let height = size.height

        return Seat(
            offset: offset,
            startAngle: start,
            endAngle: end,
            innerRadius: inner,
            outerRadius: outer,
            contentFrame: CGRect(
                x: position.x - width / 2,
                y: position.y - height / 2,
                width: width,
                height: height
            )
        )
    }

    var visibleSeats: [Seat] {
        (0..<seats).map(seat(at:))
    }

    // MARK: - Hit testing

    /// Which seat a point falls in, by angle and radius.
    ///
    /// - Parameter point: panel-content coordinates, top-left origin, with any search
    ///   chrome already subtracted.
    /// - Returns: the seat's position in the visible run, or `nil` for the hub, the gaps
    ///   between wedges, and anything outside the outermost turn.
    func seatOffset(atContentPoint point: CGPoint) -> Int? {
        guard seats > 0 else { return nil }

        let origin = centre
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let radius = (dx * dx + dy * dy).squareRoot()

        // Cheap rejection of the hub and of everything past the last turn, which is most
        // of the panel's area.
        guard radius >= Self.hubRadius, radius <= outerRadius else { return nil }

        let angle = atan2(Double(dy), Double(dx))

        // Outer turns are searched first. Where two turns share a slot the outer one is
        // drawn on top, so it has to win the point as well.
        for seat in visibleSeats.reversed() {
            guard radius >= seat.innerRadius, radius <= seat.outerRadius else { continue }
            if Self.angle(angle, isWithin: seat.startAngle, and: seat.endAngle) {
                return seat.offset
            }
        }
        return nil
    }

    /// Whether `angle` lies in the arc from `start` clockwise to `end`, independent of how
    /// many turns of 2π either value carries.
    static func angle(_ angle: Double, isWithin start: Double, and end: Double) -> Bool {
        let sweep = end - start
        guard sweep > 0 else { return false }
        return normalised(angle - start) <= sweep
    }

    /// Reduces an angle to `[0, 2π)`.
    private static func normalised(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: turn)
        return remainder < 0 ? remainder + turn : remainder
    }
}
