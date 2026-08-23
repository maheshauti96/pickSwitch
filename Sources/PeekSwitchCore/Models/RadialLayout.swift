import CoreGraphics
import Foundation

/// Pure geometry for the two round arrangements: wedge-shaped seats around a hollow hub.
///
/// ## The two windings
///
/// Both wind outward from the top, eight seats to a turn, and differ only in where the radius
/// changes — which turns out to be the whole difference in how organised they look.
///
/// - `circular` snaps the radius per *turn*, so a turn is a true annulus. Neighbours share
///   both arcs, every gap is the same width, seats in the same slot of different turns line up
///   radially, and a turn's icons all land on one circle.
/// - `spiral` advances the radius a little with every *seat*. Mathematically the truer spiral,
///   and it has a definite motion to it, but no two neighbours share an arc: the ring reads as
///   a staircase and the icons trace a curve rather than a circle.
///
/// Neither is better, which is why both are offered rather than one being chosen.
///
/// ## Why nothing is paged
///
/// Unlike the grid and list, these seat *every* window. A round arrangement paged onto a second
/// screenful is the worst of both: you lose the "everything at a glance" that justifies the
/// shape, and you still have to page. So when the count outgrows the space the whole
/// arrangement is scaled down instead — see `scale`. Paging survives only as a floor for
/// pathological counts, where shrinking further would leave the icons unreadable.
///
/// ## Why angular hit-testing
///
/// A wedge is not a rectangle, and the point of aiming a pointer at a ring is that a flick in
/// roughly the right direction lands on the right thing. `seatOffset(atContentPoint:)` resolves
/// a point by angle and radius, so the whole wedge is live right into its corners — which a
/// bounding-box test could not do, since the boxes of adjacent wedges overlap heavily.
///
/// Everything here is a value type with no AppKit dependency, so all of it is directly
/// unit-testable.
struct RadialLayout: Equatable, Sendable {

    /// Where the radius changes as seats are added.
    enum Winding: Equatable, CaseIterable, Sendable {
        /// Per turn: concentric rings.
        case circular
        /// Per seat: a continuous outward curve.
        case spiral
    }

    // MARK: - Base metrics
    //
    // All at scale 1. Everything an eye can see is multiplied by `scale`, so the arrangement
    // shrinks as a whole rather than getting proportionally squashed.

    /// Radius of the hollow middle.
    ///
    /// Big enough to caption the selected window inside it, which the arrangement needs:
    /// wedges are too narrow for a window title, so three windows of one application are three
    /// identical icons until something spells out which is which.
    static let baseHubRadius: CGFloat = 96

    /// Radial depth of a seat — an icon plus a line of text, plus breathing room.
    static let baseRingThickness: CGFloat = 120

    /// Clearance between one turn and the next.
    static let baseTurnGap: CGFloat = 9

    /// Clearance between a seat's contents and the wedge that draws them.
    static let baseContentMargin: CGFloat = 4

    /// Height a seat's contents want: an icon with a name under it.
    static let basePreferredContentHeight: CGFloat = 72

    /// Seats in a full turn. Eight gives each one 45°.
    ///
    /// Set by what has to fit inside a wedge rather than by how many windows one turn should
    /// hold. `contentSize` derives the largest upright box that fits a wedge at any angle on
    /// the ring, and at twelve seats to a turn that box is 45 × 47 — too small for an
    /// application icon with a name under it. Eight yields 80 × 72, which holds both, and it
    /// makes each seat a 45° target, which is an easier flick besides.
    static let seatsPerTurn = 8

    /// Space between the outermost wedge and the panel edge. Chrome rather than content, so it
    /// does not scale.
    static let padding: CGFloat = 18

    /// Angular gap between neighbouring wedges, so they read as separate cards rather than as
    /// one striped disc. Roughly 1.4°.
    static let wedgeGap: Double = 0.024

    /// Angle of the first seat. Straight up: the top of a ring is the one position a user can
    /// find without looking, and the list is ordered by recency, so the most recent window
    /// belongs there.
    static let startAngle: Double = -.pi / 2

    /// How far the arrangement will shrink before it starts paging instead.
    ///
    /// Below this an icon is under 25pt and its label is gone, at which point another turn of
    /// unreadable wedges is worth less than a second screenful of legible ones. With the
    /// history depth capped at 25 windows this floor is not reached on any real display; it
    /// exists for a search that matches every tab in a browser.
    static let minimumScale: CGFloat = 0.5

    // MARK: - Inputs

    let winding: Winding
    let cardCount: Int
    let selectedIndex: Int?
    /// Width the arrangement may occupy, already excluding insets.
    let availableContentWidth: CGFloat
    /// Height the arrangement may occupy, already excluding insets.
    let availableContentHeight: CGFloat

    // MARK: - Angles

    /// Angular width of one seat, gaps included.
    static var sweep: Double { 2 * .pi / Double(seatsPerTurn) }

    /// Which turn a seat belongs to.
    static func turn(ofSeat offset: Int) -> Int {
        max(0, offset) / seatsPerTurn
    }

    /// How many turns `seats` seats need.
    static func turns(forSeats seats: Int) -> Int {
        max(1, (max(0, seats) + seatsPerTurn - 1) / seatsPerTurn)
    }

    // MARK: - Unscaled radii

    /// How much further out each successive seat sits, in the spiral winding. One full turn of
    /// these adds exactly one ring thickness plus its gap, which is what makes the turns nest.
    static var baseRadialStep: CGFloat {
        (baseRingThickness + baseTurnGap) / CGFloat(seatsPerTurn)
    }

    /// Inner radius of a seat before scaling. The one place the two windings differ.
    static func baseInnerRadius(atSeat offset: Int, winding: Winding) -> CGFloat {
        let offset = max(0, offset)
        switch winding {
        case .circular:
            return baseHubRadius + CGFloat(turn(ofSeat: offset)) * (baseRingThickness + baseTurnGap)
        case .spiral:
            return baseHubRadius + CGFloat(offset) * baseRadialStep
        }
    }

    /// Outermost radius reached by `seats` seats, before scaling.
    ///
    /// The circular winding measures whole turns even when the last one is only part full: its
    /// radius is snapped per turn, so an unfilled slot frees no radius, and pretending
    /// otherwise would leave a ring of empty space around the arrangement.
    static func baseOuterRadius(forSeats seats: Int, winding: Winding) -> CGFloat {
        guard seats > 0 else { return baseHubRadius + baseRingThickness }
        switch winding {
        case .circular:
            let turns = turns(forSeats: seats)
            return baseHubRadius + CGFloat(turns) * (baseRingThickness + baseTurnGap) - baseTurnGap
        case .spiral:
            return baseInnerRadius(atSeat: seats - 1, winding: winding) + baseRingThickness
        }
    }

    // MARK: - Fitting

    /// Radius the arrangement has to fit inside.
    private var radiusLimit: CGFloat {
        max(1, min(availableContentWidth, availableContentHeight) / 2 - Self.padding)
    }

    /// The scale `seats` seats would need in order to fit, uncapped by `minimumScale`.
    private func requiredScale(forSeats seats: Int) -> CGFloat {
        let needed = Self.baseOuterRadius(forSeats: seats, winding: winding)
        guard needed > 0 else { return 1 }
        return min(1, radiusLimit / needed)
    }

    /// How many windows are seated.
    ///
    /// Every one of them, in every case that matters: the arrangement shrinks to make room
    /// rather than paging. Seats are only given up once shrinking has bottomed out at
    /// `minimumScale`, and then `visibleRange` pages through the remainder.
    var seats: Int {
        guard cardCount > 0 else { return 0 }
        var fitted = cardCount
        while fitted > Self.seatsPerTurn, requiredScale(forSeats: fitted) < Self.minimumScale {
            fitted -= 1
        }
        return fitted
    }

    /// How much the whole arrangement is shrunk so its seats fit the display.
    ///
    /// One factor applied to every length, so the proportions the design was drawn at survive
    /// at any size. Never above 1: a handful of windows gets the arrangement at its intended
    /// size rather than a bloated version of it.
    var scale: CGFloat {
        max(Self.minimumScale, requiredScale(forSeats: seats))
    }

    // MARK: - Scaled metrics

    var hubRadius: CGFloat { Self.baseHubRadius * scale }
    var ringThickness: CGFloat { Self.baseRingThickness * scale }
    var turnGap: CGFloat { Self.baseTurnGap * scale }
    var turns: Int { Self.turns(forSeats: seats) }

    func innerRadius(atSeat offset: Int) -> CGFloat {
        Self.baseInnerRadius(atSeat: offset, winding: winding) * scale
    }

    func outerRadius(atSeat offset: Int) -> CGFloat {
        innerRadius(atSeat: offset) + ringThickness
    }

    /// Radius of the outermost seated wedge.
    var outerRadius: CGFloat {
        Self.baseOuterRadius(forSeats: seats, winding: winding) * scale
    }

    /// Square, because the arrangement is only ever as wide as it is tall.
    var panelSize: CGSize {
        let side = (outerRadius + Self.padding) * 2
        return CGSize(width: side, height: side)
    }

    var centre: CGPoint {
        CGPoint(x: panelSize.width / 2, y: panelSize.height / 2)
    }

    /// The hollow middle, as the square that bounds it.
    ///
    /// A rectangle is enough for what this is used for. Hit-testing resolves wedges before it
    /// considers the hub, and the corners of this square fall inside the innermost wedges, so
    /// those points are claimed by a wedge before the hub ever sees them.
    var hubFrame: CGRect {
        CGRect(
            x: centre.x - hubRadius,
            y: centre.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        )
    }

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
    /// are. The circle fits when it clears the two bounding rays and stays within the annulus,
    /// and the tighter of those two bounds is this.
    ///
    /// Measured at the innermost seat, which is the tightest: the rays converge towards the
    /// hub, so a box that fits there fits everywhere further out.
    var contentRadius: CGFloat {
        Self.contentRadius(
            hubRadius: hubRadius,
            ringThickness: ringThickness,
            margin: Self.baseContentMargin * scale
        )
    }

    /// The upright box a seat's contents are drawn in. The same for every seat.
    var contentSize: CGSize {
        Self.contentSize(
            hubRadius: hubRadius,
            ringThickness: ringThickness,
            margin: Self.baseContentMargin * scale,
            preferredHeight: Self.basePreferredContentHeight * scale
        )
    }

    /// The content box at scale 1.
    ///
    /// `OverlayCardMetrics.spiral` is built from this so the card metrics and the geometry
    /// cannot drift apart; the view scales those metrics by `scale` at draw time.
    static var baseContentSize: CGSize {
        contentSize(
            hubRadius: baseHubRadius,
            ringThickness: baseRingThickness,
            margin: baseContentMargin,
            preferredHeight: basePreferredContentHeight
        )
    }

    static func contentRadius(
        hubRadius: CGFloat,
        ringThickness: CGFloat,
        margin: CGFloat
    ) -> CGFloat {
        let innerMidRadius = hubRadius + ringThickness / 2
        let ray = innerMidRadius * CGFloat(sin((sweep - wedgeGap) / 2))
        return max(1, min(ringThickness / 2, ray) - margin)
    }

    static func contentSize(
        hubRadius: CGFloat,
        ringThickness: CGFloat,
        margin: CGFloat,
        preferredHeight: CGFloat
    ) -> CGSize {
        let diagonal = contentRadius(
            hubRadius: hubRadius,
            ringThickness: ringThickness,
            margin: margin
        ) * 2
        // Height first, since the icon and its label are what set it; width takes whatever the
        // diagonal has left.
        let height = min(preferredHeight, diagonal * 0.72)
        let width = (diagonal * diagonal - height * height).squareRoot()
        return CGSize(width: width, height: height)
    }

    // MARK: - Seats

    /// One wedge, in panel-content coordinates with a top-left origin.
    struct Seat: Equatable, Sendable {
        /// Position in the visible run, not the index of the entry it shows.
        let offset: Int
        /// Clockwise from `startAngle`. Angles grow clockwise because the y axis points down in
        /// this coordinate space.
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        /// Where the icon and label go: an upright rectangle centred in the wedge. The wedge is
        /// the shape and the hit area; this is the box its contents live in.
        let contentFrame: CGRect

        var midAngle: Double { (startAngle + endAngle) / 2 }
        var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }
    }

    func seat(at offset: Int) -> Seat {
        let slot = offset % Self.seatsPerTurn
        let start = Self.startAngle + Double(slot) * Self.sweep + Self.wedgeGap / 2
        let end = Self.startAngle + Double(slot + 1) * Self.sweep - Self.wedgeGap / 2
        let inner = innerRadius(atSeat: offset)
        let outer = outerRadius(atSeat: offset)

        let midAngle = (start + end) / 2
        let midRadius = (inner + outer) / 2
        let origin = centre
        let position = CGPoint(
            x: origin.x + midRadius * CGFloat(cos(midAngle)),
            y: origin.y + midRadius * CGFloat(sin(midAngle))
        )

        let size = contentSize

        return Seat(
            offset: offset,
            startAngle: start,
            endAngle: end,
            innerRadius: inner,
            outerRadius: outer,
            contentFrame: CGRect(
                x: position.x - size.width / 2,
                y: position.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        )
    }

    var visibleSeats: [Seat] {
        (0..<seats).map(seat(at:))
    }

    // MARK: - Hit testing

    /// Which seat a point falls in, by angle and radius.
    ///
    /// - Parameter point: panel-content coordinates, top-left origin, with any search chrome
    ///   already subtracted.
    /// - Returns: the seat's position in the visible run, or `nil` for the hub, the gaps between
    ///   wedges, and anything outside the outermost turn.
    func seatOffset(atContentPoint point: CGPoint) -> Int? {
        guard seats > 0 else { return nil }

        let origin = centre
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let radius = (dx * dx + dy * dy).squareRoot()

        // Cheap rejection of the hub and of everything past the last turn, which is most of the
        // panel's area.
        guard radius >= hubRadius, radius <= outerRadius else { return nil }

        let angle = atan2(Double(dy), Double(dx))

        // Outer turns are searched first. Where two turns share a slot the outer one is drawn
        // on top, so it has to win the point as well.
        for seat in visibleSeats.reversed() {
            guard radius >= seat.innerRadius, radius <= seat.outerRadius else { continue }
            if Self.angle(angle, isWithin: seat.startAngle, and: seat.endAngle) {
                return seat.offset
            }
        }
        return nil
    }

    /// Whether `angle` lies in the arc from `start` clockwise to `end`, independent of how many
    /// turns of 2π either value carries.
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
