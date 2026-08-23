import CoreGraphics
import SwiftUI

/// One seat of the spiral: an annular sector with rounded corners.
///
/// ## Why the geometry is absolute
///
/// The path is built from a centre point, two angles and two radii given in the panel's own
/// coordinate space, and `rect` is ignored. Every other shape in SwiftUI is drawn relative to
/// the rectangle it is handed, so this needs saying.
///
/// The reason is that a wedge's bounding box is not a useful thing to lay out against. Boxes
/// of neighbouring wedges overlap heavily, a wedge is nowhere near centred in its own box,
/// and `OverlayLayout` hit-tests clicks against angles rather than boxes. Handing each wedge
/// the whole panel and letting it paint its own sector at absolute coordinates means what is
/// drawn and what is clicked are computed from one description of the ring, which is the
/// property that keeps the two from drifting apart.
struct WedgeShape: Shape {

    let centre: CGPoint
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    /// Corner rounding, clamped to whatever the wedge can actually accommodate.
    var cornerRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let thickness = outerRadius - innerRadius
        guard thickness > 0, endAngle > startAngle, innerRadius > 0 else { return path }

        // A corner cannot eat more than half the wedge in either direction, and the inner
        // arc is the shorter of the two, so it sets the angular limit.
        let innerArc = innerRadius * CGFloat(endAngle - startAngle)
        let corner = max(0, min(cornerRadius, min(thickness / 2, innerArc / 2)))

        // How much angle each corner consumes differs between the two arcs: the same
        // straight-line inset spans a wider angle close to the centre than far from it.
        let innerInset = corner / innerRadius
        let outerInset = corner / outerRadius

        let innerStart = startAngle + Double(innerInset)
        let innerEnd = endAngle - Double(innerInset)
        let outerStart = startAngle + Double(outerInset)
        let outerEnd = endAngle - Double(outerInset)

        // Degenerate at very small radii or very narrow sweeps: fall back to hard corners
        // rather than drawing an inside-out arc.
        guard innerStart < innerEnd, outerStart < outerEnd else {
            return sharpPath()
        }

        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(
                x: centre.x + radius * CGFloat(cos(angle)),
                y: centre.y + radius * CGFloat(sin(angle))
            )
        }

        // Round the corners with quadratic curves through the true corner as the control
        // point. An arc-to-arc fillet would be more exact, but at 9pt on a 108pt-deep wedge
        // the difference is invisible and this cannot produce the tangent failures that
        // `addArc(tangent1End:)` does at shallow sweeps.
        path.move(to: point(innerRadius + corner, startAngle))
        path.addQuadCurve(
            to: point(innerRadius, innerStart),
            control: point(innerRadius, startAngle)
        )
        path.addArc(
            center: centre,
            radius: innerRadius,
            startAngle: .radians(innerStart),
            endAngle: .radians(innerEnd),
            clockwise: false
        )
        path.addQuadCurve(
            to: point(innerRadius + corner, endAngle),
            control: point(innerRadius, endAngle)
        )

        path.addLine(to: point(outerRadius - corner, endAngle))
        path.addQuadCurve(
            to: point(outerRadius, outerEnd),
            control: point(outerRadius, endAngle)
        )
        path.addArc(
            center: centre,
            radius: outerRadius,
            startAngle: .radians(outerEnd),
            endAngle: .radians(outerStart),
            clockwise: true
        )
        path.addQuadCurve(
            to: point(outerRadius - corner, startAngle),
            control: point(outerRadius, startAngle)
        )

        path.closeSubpath()
        return path
    }

    private func sharpPath() -> Path {
        var path = Path()
        path.addArc(
            center: centre,
            radius: innerRadius,
            startAngle: .radians(startAngle),
            endAngle: .radians(endAngle),
            clockwise: false
        )
        path.addArc(
            center: centre,
            radius: outerRadius,
            startAngle: .radians(endAngle),
            endAngle: .radians(startAngle),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

extension WedgeShape {

    /// Builds the shape for a seat, so callers do not restate its five fields.
    init(seat: RadialLayout.Seat, centre: CGPoint, cornerRadius: CGFloat = 9) {
        self.init(
            centre: centre,
            startAngle: seat.startAngle,
            endAngle: seat.endAngle,
            innerRadius: seat.innerRadius,
            outerRadius: seat.outerRadius,
            cornerRadius: cornerRadius
        )
    }
}
