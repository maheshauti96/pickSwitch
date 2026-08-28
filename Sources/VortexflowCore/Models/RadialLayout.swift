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
/// ## Why the ring is capped rather than shrunk indefinitely
///
/// These used to seat *every* window, on the argument that a round arrangement paged onto a
/// second screenful is the worst of both worlds. The argument was right about paging and wrong
/// about the alternative, which is not "the same arrangement, smaller" — it is a different and
/// worse arrangement.
///
/// Measured on a 1512x950 display, holding the references' proportions: at 15 windows a card is
/// 1.26x the hub's radius deep, which is what the references show and what makes a wedge read as
/// a card. At 25 it is 0.95x — shallower than the hub is wide — and the content box has lost 40%
/// of its area, taking the icon and its label with it. Nothing about that is the same
/// arrangement scaled down; the cards stop being cards, and the icon is the only thing that
/// identifies a window at ring distance.
///
/// So the ring now seats as many windows as hold `minimumDepthRatio` and pages the rest. This is
/// a real loss — "everything at a glance" is the reason to choose a ring — and it is why the
/// floor is a named, tested constant rather than a count: it says exactly what is being traded
/// and at what point. `OverlayLayout.hiddenCount` is what is left over, and the hub says so,
/// because a ring that silently omits a third of the windows is worse than one that admits it.
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
    ///
    /// Not larger than that. The reference hub measures about 92pt (a 172px ring radius at 2×,
    /// plus the inset), and the wedges there are deeper than the hub's radius rather than equal
    /// to it. Enlarging this instead flattens that proportion: the caption disc wins radius that
    /// the cards need, and the icons shrink to pay for it.
    static let baseHubRadius: CGFloat = 96

    /// Physical seam between the caption well and the first turn of wedges.
    ///
    /// Measured off the 1408px references, per angle rather than at one guessed bearing. The
    /// bright ring centreline sits at r=172px; sweeping all 360° and taking the nearest sustained
    /// card fill puts the innermost wedge's inner arc at r=196–200px. So the void is 28px — 0.16
    /// of the ring radius, and 15pt at this hub, which is a 8pt seam on top of the 7pt ring inset.
    ///
    /// A previous pass read that distance as 53px by sampling a bearing that happened to fall in a
    /// seam and landing on a *second-turn* card instead of the first. That doubled the seam to 20pt
    /// and pushed the cards visibly away from the hub, which is the opposite of what the references
    /// show. The reliable instrument is the per-angle minimum, because a spiral only places one
    /// seat at the innermost radius and every other bearing is further out by design.
    ///
    /// The failure mode on the other side is real too: reserving the halo's whole blur extent
    /// (0.55 of the ring radius) detaches the cards entirely. The glow keeps decaying across this
    /// seam and under the wedges, which is why its extent is not the measurement that matters.
    static let baseHubGap: CGFloat = 8

    /// Inner radius of the first turn — where wedges actually start.
    ///
    /// Every seat radius derives from this rather than from `baseHubRadius`, which now describes
    /// only the caption's disc and the halo drawn on its rim.
    static var baseFirstRingRadius: CGFloat { baseHubRadius + baseHubGap }

    /// Radial depth of a seat — an icon plus a line of text, plus breathing room.
    ///
    /// The reference wedges measure 219px against a 172px ring radius, so depth is about 1.27x
    /// the hub's radius. That ratio is what makes the cards read as cards; at parity they read
    /// as a thin band, and the icon is the thing that identifies a window at ring distance.
    static let baseRingThickness: CGFloat = 120

    /// Clearance between one turn and the next.
    ///
    /// Measured off the references: their inter-turn gap is 0.169 of a card's depth, where 9pt
    /// against a 120pt card was 0.075 — less than half — and that is what made two turns read as
    /// one dense band rather than as separate rings.
    ///
    /// Not raised all the way to the reference proportion. Every point here is a point of radius
    /// the wedge stack does not get, and because the hub is protected from scaling the cost lands
    /// entirely on card depth: at 0.169 the depth-to-ring ratio fell under its floor at 25 windows.
    /// 16pt reaches 0.133 while keeping that margin.
    static let baseTurnGap: CGFloat = 16

    /// Clearance between a seat's contents and the wedge that draws them.
    static let baseContentMargin: CGFloat = 4

    /// Height a seat's contents want: an icon with a name under it.
    ///
    /// Pushed close to what the wedge can geometrically hold — `contentSize` caps it at 72% of the
    /// inscribed diagonal, about 78pt — because the icon gets whatever the name does not, and the
    /// icon is the thing that identifies a window at ring distance. The few points this takes from
    /// the box's width cost the label nothing: it needs room for "Google", not for the whole name
    /// on one line.
    static let basePreferredContentHeight: CGFloat = 76

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
    static let wedgeGap: Double = 0.05

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
            return baseFirstRingRadius
                + CGFloat(turn(ofSeat: offset)) * (baseRingThickness + baseTurnGap)
        case .spiral:
            return baseFirstRingRadius + CGFloat(offset) * baseRadialStep
        }
    }

    /// Outermost radius reached by `seats` seats, before scaling.
    ///
    /// The circular winding measures whole turns even when the last one is only part full: its
    /// radius is snapped per turn, so an unfilled slot frees no radius, and pretending
    /// otherwise would leave a ring of empty space around the arrangement.
    static func baseOuterRadius(forSeats seats: Int, winding: Winding) -> CGFloat {
        guard seats > 0 else { return baseFirstRingRadius + baseRingThickness }
        switch winding {
        case .circular:
            let turns = turns(forSeats: seats)
            return baseFirstRingRadius
                + CGFloat(turns) * (baseRingThickness + baseTurnGap) - baseTurnGap
        case .spiral:
            return baseInnerRadius(atSeat: seats - 1, winding: winding) + baseRingThickness
        }
    }

    // MARK: - Fitting

    /// Radius the arrangement has to fit inside.
    private var radiusLimit: CGFloat {
        max(1, min(availableContentWidth, availableContentHeight) / 2 - Self.padding)
    }

    /// Fraction of the scale-1 hub that survives even when the card stack has to shrink.
    ///
    /// Card count changes how much radial room the wedges need; it does not make the selected
    /// window's caption shorter. Keeping 74% fixed leaves an 89–94pt hub throughout realistic
    /// 15–20-window layouts — the reference's ~92pt — while still letting unusually small
    /// displays compress it.
    private static let preservedHubFraction: CGFloat = 0.74

    /// Smallest hub the caption survives.
    ///
    /// Softening the hub is not enough on its own. On a 1440x875 display with 25 windows the
    /// softened radius reached 85.2pt, whose opaque core is 122.7pt — under the 124pt the caption
    /// is laid out for, so the type crossed onto the transparent part of the panel and the desktop
    /// read through it. Shrinking stops here; the wedge stack gives up the remaining radius, and
    /// pages if it must.
    static var minimumHubRadius: CGFloat {
        HubTypography.captionDiameter / (2 * HubChrome.wellOpaqueFraction)
    }

    private static func physicalHubRadius(atScale scale: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, scale))
        let scalable = 1 - preservedHubFraction
        let softened = baseHubRadius * (preservedHubFraction + scalable * clamped)
        return max(minimumHubRadius, softened)
    }

    /// Part of the arrangement outside the first inner arc. This is the only radial span the
    /// fitter scales linearly: ring depth, inter-turn gaps, and spiral advancement.
    private static func baseScalableSpan(forSeats seats: Int, winding: Winding) -> CGFloat {
        max(0, baseOuterRadius(forSeats: seats, winding: winding) - baseFirstRingRadius)
    }

    /// Outer radius while protecting the physical hub-to-wedge seam.
    private func protectedOuterRadius(forSeats seats: Int, scale: CGFloat) -> CGFloat {
        Self.physicalHubRadius(atScale: scale)
            + Self.baseHubGap
            + Self.baseScalableSpan(forSeats: seats, winding: winding) * scale
    }

    /// Largest scale at which `seats` fit while preserving the physical hub and direct seam.
    ///
    /// The previous `radiusLimit / baseOuterRadius` normalized changes near the centre away:
    /// every point added there reduced the global scale, so the live first ring barely moved.
    /// This monotonic solve scales only the wedge stack around the protected centre geometry.
    private func requiredScale(forSeats seats: Int) -> CGFloat {
        guard protectedOuterRadius(forSeats: seats, scale: 1) > radiusLimit else { return 1 }
        guard protectedOuterRadius(forSeats: seats, scale: 0) < radiusLimit else { return 0 }

        var lower: CGFloat = 0
        var upper: CGFloat = 1
        for _ in 0..<36 {
            let candidate = (lower + upper) / 2
            if protectedOuterRadius(forSeats: seats, scale: candidate) <= radiusLimit {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        return lower
    }

    /// Whether the wedge stack still fits at the legibility floor after the small hub seam has
    /// yielded. Paging is allowed only after this fails: preserving every window is more
    /// important than preserving all 8pt of separation on unusually small displays.
    private func fitsWithoutHubGapAtMinimumScale(_ seats: Int) -> Bool {
        let minimumOuter = Self.physicalHubRadius(atScale: Self.minimumScale)
            + Self.baseScalableSpan(forSeats: seats, winding: winding) * Self.minimumScale
        return minimumOuter <= radiusLimit
    }

    /// Shallowest card, as a multiple of the hub's ring radius, that still reads as a card.
    ///
    /// The references measure 1.267 — a 219px card against a 172px ring radius. That exact value
    /// is not the floor, because it would cost two more seats than it is worth: on a 1512x950
    /// display 1.267 seats 15 windows where 1.20 seats 17, and the difference between those two
    /// proportions is not visible side by side while two more windows on the ring plainly are.
    ///
    /// Below about 1.0 the card is shallower than the hub's radius and the arrangement inverts —
    /// the hollow middle becomes the largest thing on screen and the wedges read as a thin striped
    /// collar around it, which is the opposite of the references. 1.20 keeps a margin above that
    /// while staying close enough to 1.267 to hold the proportion a person compares.
    static let minimumDepthRatio: CGFloat = 1.20

    /// Whether seating `seats` leaves the cards deep enough to still be cards.
    ///
    /// Monotonic in the seat count, because fewer seats need less radius and so resolve to a
    /// larger scale, which is what lets `seats` find the cap by walking down.
    private func holdsCardProportion(_ seats: Int) -> Bool {
        let scale = max(Self.minimumScale, requiredScale(forSeats: seats))
        let ring = Self.physicalHubRadius(atScale: scale) - HubChrome.ringInset
        guard ring > 0 else { return false }
        return (Self.baseRingThickness * scale) / ring >= Self.minimumDepthRatio
    }

    /// How many windows are seated.
    ///
    /// Two independent reasons to seat fewer than were asked for, both of them about the
    /// arrangement ceasing to be itself rather than about arithmetic:
    ///
    /// - the wedge stack no longer fits even at the legibility floor, which is the tiny-display
    ///   case and was always here;
    /// - the cards would be shallower than `minimumDepthRatio`, which is the crowded-ring case.
    ///
    /// Never below one full turn. Eight wedges is the smallest thing that is still recognisably a
    /// ring, and paging down past it would trade the shape away to protect a proportion that only
    /// matters because of the shape.
    var seats: Int {
        guard cardCount > 0 else { return 0 }
        var fitted = cardCount
        while fitted > Self.seatsPerTurn,
              !fitsWithoutHubGapAtMinimumScale(fitted) || !holdsCardProportion(fitted) {
            fitted -= 1
        }
        return fitted
    }

    /// Scale of wedge depth, turn gaps, content, and radial advancement.
    ///
    /// The hub and its direct seam to the wedges are physical chrome, not card content, and
    /// therefore use their protected metrics below instead of being multiplied by this value.
    var scale: CGFloat {
        max(Self.minimumScale, requiredScale(forSeats: seats))
    }

    // MARK: - Resolved metrics

    /// Radius of the hollow caption well. Softened rather than linearly scaled so opening more
    /// windows cannot collapse the most information-dense part of the arrangement.
    var hubRadius: CGFloat { Self.physicalHubRadius(atScale: scale) }

    private var scalableSpan: CGFloat {
        Self.baseScalableSpan(forSeats: seats, winding: winding) * scale
    }

    /// Where the first turn begins. On realistic displays this is exactly 8pt beyond the
    /// physical hub; the rear halo is allowed to paint beneath the wedges rather than reserving
    /// its mathematical blur extent as empty layout space. If even the minimum-scale arrangement
    /// cannot fit an unusually tiny display, only this seam yields; hub and wedges do not overlap.
    var firstRingRadius: CGFloat {
        let protected = hubRadius + Self.baseHubGap
        let roomAfterWedges = radiusLimit - scalableSpan
        return max(hubRadius, min(protected, roomAfterWedges))
    }

    /// Actual physical seam from the hub edge to seat zero's inner arc.
    var hubGap: CGFloat {
        max(0, firstRingRadius - hubRadius)
    }

    /// Distance from the bright ring centreline to seat zero's inner arc.
    ///
    /// This is the perceived spacing measured in the reference images: ring inset plus hub seam,
    /// independent of the halo's soft painted extent underneath the wedges.
    var ringCentreToFirstRingGap: CGFloat {
        firstRingRadius - (hubRadius - HubChrome.ringInset)
    }

    var ringThickness: CGFloat { Self.baseRingThickness * scale }
    var turnGap: CGFloat { Self.baseTurnGap * scale }
    var turns: Int { Self.turns(forSeats: seats) }

    func innerRadius(atSeat offset: Int) -> CGFloat {
        let baseOffset = Self.baseInnerRadius(atSeat: offset, winding: winding)
            - Self.baseFirstRingRadius
        return firstRingRadius + baseOffset * scale
    }

    func outerRadius(atSeat offset: Int) -> CGFloat {
        innerRadius(atSeat: offset) + ringThickness
    }

    /// Radius of the outermost seated wedge.
    var outerRadius: CGFloat { firstRingRadius + scalableSpan }

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
            hubRadius: firstRingRadius,
            ringThickness: ringThickness,
            margin: Self.baseContentMargin * scale
        )
    }

    /// The upright box a seat's contents are drawn in. The same for every seat.
    var contentSize: CGSize {
        Self.contentSize(
            hubRadius: firstRingRadius,
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
            hubRadius: baseFirstRingRadius,
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
