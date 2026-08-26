import CoreGraphics

/// Visual-only metrics for the radial hub's ring and coupling.
///
/// None of these lengths change `RadialLayout.hubFrame` or a wedge's seat. The overlay hit-tests
/// those, and a glow that moved them would make the brightest thing on screen unclickable — or
/// steal the inner edge of a wedge. Drawing may overspill the hub; clicking may not.
enum HubChrome {

    /// How far the halo's centre-line sits *inside* the hub radius.
    ///
    /// Small: the mock's glow lives on the rim of a void, not as a tube printed on a
    /// plate. Too little and it vanishes in the seam; too much and it becomes a donut
    /// on the caption.
    static let ringInset: CGFloat = 7

    /// Unused as a visible stroke. Kept so existing tests that pin a hairline
    /// still have a value; the mock ring is the glow layer only.
    static let ringBandThickness: CGFloat = 1.2

    /// The crisp core of the ring, drawn in front of the wedges.
    ///
    /// Measured off the reference: the bright circle is 19px across at half maximum on a 172px ring
    /// radius, which is 0.110 of that radius, or about 9.5pt at this hub. Wide values here do not
    /// read as a brighter ring, they read as a torus — a 30pt band under `plusLighter` saturates
    /// into a 28pt slab of white and swallows the void it is meant to light. Breadth belongs to
    /// `halo*` below, which sits behind the cards.
    ///
    /// Narrow, and narrower than the 19px the reference's rim measures at half maximum, because that
    /// 19px is not one stroke. The reference's cross-section is a *sum*: a sharp crest that has
    /// already fallen to 0.57 five pixels out, sitting on a broad shoulder that holds 0.23 for
    /// another twenty. This constant is only the crest. The shoulder is `HubRingHalo`.
    ///
    /// Getting that wrong in both directions is instructive. At 6pt under a 3pt blur the crest was
    /// wide enough that the blur ate its peak — luminance 190 against the reference's 217. Widening
    /// it to 8pt recovered four of those and bought a flat top instead: the profile held 0.97 of its
    /// peak at +5px and 0.87 at +10px where the reference is at 0.57 and 0.44, then fell off a cliff
    /// at +15px. A 16px stroke has 16px of full value in it however it is blurred, and a plateau with
    /// a cliff is the one shape light never makes.
    ///
    /// 5pt under a 1.4pt blur was the same mistake at a smaller scale, and it took the right
    /// measurement to see it. Half maximum is the wrong place to look for thickness: at 5pt the
    /// rendered rim measured 17.5px wide at half maximum against the reference's 18.0px, an
    /// apparently exact match. What an eye reads as the thickness of a line is the band that looks
    /// *fully lit*, and there the same render measured 7.5px wide at 0.90 of its peak where the
    /// reference measures 3.5px. Rendered in isolation the core stroke alone accounted for all of
    /// it — 7.5px at 0.90, 10.0px at 0.50 — because a 5pt stroke is 10 device pixels of constant
    /// value and a 1.4pt blur only rounds its corners. The rim was twice as thick as the reference's
    /// and the excess was all on the outward side (-2.0/+5.5 against the reference's -2.0/+1.5),
    /// which is also why the glow looked like it spread outward only: the well's inward bloom pulled
    /// the composite peak 4px inside the stroke's centreline, leaving the stroke's outer half
    /// standing outside the peak as a shelf.
    ///
    /// 3pt is 6 device pixels, and the blur below is what keeps it from aliasing rather than what
    /// spreads it. Both halves of the complaint move the same way: a narrower stroke under a lighter
    /// blur is *brighter* at its centre, because less of its own mass is thrown into the shoulders.
    static let ringGlowThickness: CGFloat = 2.2

    /// Blur on the core stroke only, which sets how far the *crisp* part of the rim spreads.
    ///
    /// Small enough that the crest keeps its brightness. A Gaussian of radius r over a stroke of
    /// half-width w retains roughly the kernel mass inside ±w, so a blur comparable to the stroke
    /// throws most of the peak into the shoulders — which is where the missing 25 luminance had
    /// been going. Breadth belongs to `haloSpread`, behind the cards, where it costs the crest
    /// nothing.
    ///
    /// Cut with `ringGlowThickness`, and for the same reason: this is anti-aliasing, not glow. At
    /// 1.4pt the blur was 2.8 device pixels either side of a stroke that only needed its corners
    /// taken off, and it widened the band that reads as fully lit without adding anything the
    /// shoulder was not already providing better. 0.7pt keeps the edge smooth at Retina scale and
    /// leaves the 0.90 band to be set by the stroke's own width.
    static let ringGlowBlur: CGFloat = 0.7

    /// How far the broad rear bloom reaches either side of the ring's centreline.
    ///
    /// In the reference the void is never black: the glow falls from about L=130 just outside the
    /// bright ring to L=20 at the first wedge's inner arc, roughly 26pt further out, and the cards
    /// are composited over that tail. A glow that dies before the cards is exactly what makes the
    /// gap read as dead space, so this must out-reach `RadialLayout.baseHubGap` plus `ringInset`.
    ///
    /// Spent as an explicit radial falloff rather than a blurred stroke. A stroked band reaches
    /// only its own outer edge — the blur does not survive the rasterisation bounds — so it paints
    /// a flat annulus with a hard cliff, which is measurably not what the reference does.
    static let haloSpread: CGFloat = 30

    /// Only to smooth gradient banding. The falloff shape is in the gradient, not in the blur.
    static let haloBlur: CGFloat = 8

    /// Fraction of hub diameter that stays a fully opaque disc under the caption.
    ///
    /// Hub typography is sized for a 124-point disc (source + three title lines +
    /// status). The caption is laid out inside this circle rather than on a rounded
    /// rect, so the middle stays a circle. Drawn as a *solid* fill: a gradient that
    /// fades to clear on the same shape in a non-opaque `NSPanel` lets the desktop
    /// read through the type.
    static let wellOpaqueFraction: CGFloat = 0.72

    /// Fraction of hub diameter where the well's soft falloff is gone.
    ///
    /// Must end before the ring, or the plate and the halo share an edge and the
    /// hub reads as an outlined disc — the thing the mock does not draw.
    static let wellClearFraction: CGFloat = 0.88

    /// How far past `hubRadius` the outer glow still paints.
    ///
    /// Derived from the rear halo, which is the outermost thing the hub draws. This is a
    /// compositing and hit-testing extent, not layout clearance: the halo is intentionally
    /// allowed to continue beneath first-turn wedges, as it does in the mocks, and wedges are
    /// rendered and hit-tested before hub chrome.
    static var haloReach: CGFloat {
        max(0, haloSpread - ringInset)
    }

    // MARK: - Backdrop icon

    /// Share of the well's opaque core the hovered window's icon spans as a watermark.
    ///
    /// Bounded by the core rather than by the hub: past `wellOpaqueFraction` the well is only a
    /// blurred falloff, and past `wellClearFraction` the panel is transparent, so an icon drawn
    /// out there would hang in the void with the desktop showing through it.
    static let backdropIconFraction: CGFloat = 0.88

    /// Blur as a fraction of the icon's own side.
    ///
    /// Softened, not erased, and the difference is what moved.
    ///
    /// At 0.09 the icon was a cloud of colour with no silhouette left, because at that time the only
    /// thing standing between it and the caption was its own opacity: the shape had to go, or the
    /// title became work to read. That was the right trade for a watermark painted on top of a
    /// finished plate.
    ///
    /// It is the wrong trade now. The watermark sits under `wellScrimOpacity`, which is what protects
    /// the caption, so blur no longer has to do a contrast job it was bad at — and "which application
    /// is this" is a question a silhouette answers and a colour cloud does not. 0.035 keeps every edge
    /// soft enough that nothing in here reads as a second piece of UI while leaving the shape legible.
    static let backdropIconBlurFraction: CGFloat = 0.055

    /// How strongly the watermark is painted, per scheme — *before* the scrim takes its share.
    ///
    /// These stopped being a contrast budget when the watermark moved underneath `wellScrimOpacity`,
    /// and that is the whole reason they can be this large. What reaches the eye is
    /// `(1 - wellScrimOpacity)` of the value here: at 0.80 in Dark Mode, 0.85 painted resolves to
    /// about 0.17 effective, so this is a little over three times the light the old 0.05 delivered
    /// while the caption sits on a surface the scrim has already bounded.
    ///
    /// The history is worth keeping because it explains why the old numbers looked arbitrary. While
    /// the icon was painted *on top of* an opaque plate its opacity was the only thing between it and
    /// 9pt type, so it was solved as a contrast budget against a uniformly white icon in Dark Mode and
    /// a uniformly black one in Light — and the answer kept coming out at a value that made the
    /// feature invisible. It went 0.12, then 0.10, then 0.05, chased down each time the hub interior
    /// was measured against the references, because a blurred icon averages close to its own mean
    /// luminance and at 0.10 over a fill of 14 it resolved to 36: the watermark *was* the hub
    /// interior. Every one of those steps traded the feature away to fix a symptom of where it was
    /// drawn rather than of how strong it was.
    ///
    /// The floor is no longer arithmetic either. `HubTintTests` requires the hub centre's
    /// red-minus-green to move by more than 0.03 between a red icon and a green one; that used to
    /// bind at about 0.039 and now has an order of magnitude of room.
    static let backdropIconOpacityDark: Double = 0.68
    static let backdropIconOpacityLight: Double = 0.80

    /// How heavily the well's tint is laid over its frosted substrate, `0...1`.
    ///
    /// This is the contrast floor for the caption, and every digit of it is solved rather than
    /// chosen. The well transmits some of the wallpaper on purpose now, so the type is no longer
    /// sitting on a known colour — what it is sitting on instead has to be a known *range*.
    ///
    /// The binding constraint is the secondary line, not the primary one, which is not the intuition.
    /// A translucent white line composites *brighter* as the surface behind it brightens, so it loses
    /// contrast about twice as fast as opaque white does — the primary title is nowhere near binding.
    ///
    /// Which made this a two-sided decision rather than a single number. Against `secondaryText`'s
    /// 0.58 the dark ceiling is luminance 66 and these had to be 0.80 and 0.82, leaving 20% and 18%
    /// transmission: enough to tint the middle and not enough for it to read as glass, which is
    /// most of the way to shipping the change in name only. `OverlayPalette.hubSecondaryText` exists
    /// to move that ceiling to about 100, and this is what spends it — 34% and 32% of the wallpaper,
    /// which is a lens.
    ///
    /// Deliberately pessimistic on the one quantity that cannot be measured offscreen: the bound
    /// assumes the material passes the wallpaper through untouched. A real `hudWindow` tints toward
    /// the appearance, so the rendered range is narrower than the bound and inside it either way.
    static let wellScrimOpacityDark: Double = 0.66
    static let wellScrimOpacityLight: Double = 0.68

    /// Where the watermark begins fading, as a fraction of its own radius.
    ///
    /// It has to reach zero before the core's edge. A hard circular cut would draw exactly the
    /// outlined disc the hub spends `wellClearFraction` avoiding.
    ///
    /// Pushed out from 0.52 alongside the opacity above. At 0.52 the vignette was eating the outer
    /// half of the icon's radius — which is three quarters of its area, and for most application
    /// icons that is where the shape is. That was tolerable while the watermark was a colour cloud
    /// and is not now that it is meant to be recognised.
    static let backdropIconFadeStart: Double = 0.40

    /// How far the watermark's vignette reaches, as a fraction of the icon's own half-side.
    ///
    /// Below 1 on purpose. A macOS application icon does not fill its bitmap — it carries roughly a
    /// sixth of it as transparent padding — so a vignette that ends at the bitmap's edge is still
    /// about 30% opaque where the artwork's straight sides actually are. That was harmless while the
    /// watermark was drawn at 0.05 and is not now: it drew a rounded rectangle across the caption of
    /// a circular hub. 0.80 puts the vignette's zero inside the squircle, so what fades out is the
    /// artwork rather than the bitmap.
    static let backdropIconMaskReach: CGFloat = 0.80

    /// Shape of the replacement inward bloom painted over the opaque caption well. The actual
    /// ring blur is hidden by that well, so these values deliberately mirror its broad falloff.
    ///
    /// `innerGlowStartFraction` sits just inside the opaque core's edge so the flat fill and the
    /// bloom overlap instead of butting up against each other. The reference climbs smoothly from
    /// luminance 12 deep in the middle to 129 at the rim; a bloom that starts at the core boundary
    /// draws a plateau and then a step, which reads as a second, inner circle.
    static let innerGlowStartFraction: CGFloat = 0.58
    static let innerGlowShoulderFraction: CGFloat = 0.86

    /// Where the inward bloom crests, and how much of that crest survives at the rim itself.
    ///
    /// Effectively monotone now: the bloom climbs to the rim and stops there. It used to crest 8pt
    /// inside and fall back to 0.30 at the centreline, which was the correct answer to a problem
    /// that no longer exists and the cause of one that did.
    ///
    /// The problem it solved: while the core stroke composited additively, the centreline already
    /// carried the rear halo, the selection lobe and the stroke, and a bloom cresting there too took
    /// green and blue past 255 all the way round — a flat white rim with only red still carrying
    /// information. The core blends normally now, so nothing is racing anything to 255.
    ///
    /// The problem it caused: a second maximum 8pt inside the stroke, blurred across 9 device pixels,
    /// pulled the *composite* peak 4px inward of the stroke's own centreline. Everything measured
    /// from that peak then looked lopsided — the rendered rim held 0.98 of its peak at +4px and
    /// 0.89 at +6px where the reference is at 0.58 and 0.51, not because there was extra light
    /// outward but because the peak had moved inward and the stroke's outer half was being read as a
    /// shelf beside it. Two crests 8pt apart is also just a wider bright band than one crest: 7.5px
    /// at 0.90 against the reference's 3.5px.
    ///
    /// The reference settles the shape directly. Sweeping inward from its rim it decays smoothly and
    /// monotonically — 0.885, 0.781, 0.684, 0.608 of peak at 2, 4, 6 and 8px — with no interior
    /// maximum anywhere. So the bloom crests at the rim and only decays going in.
    static let innerGlowCrestFraction: CGFloat = 0.99
    static let innerGlowCrestFalloff: Double = 0.92

    /// Blur on the inward bloom, as a share of `haloBlur`.
    ///
    /// Cut from 0.60 when the bloom stopped being four stops and became a measured curve. At 0.60
    /// this was 9.6 device pixels of Gaussian over a gradient whose steepest and most important
    /// section — the 8px just inside the rim — is narrower than the kernel, so the blur was
    /// flattening the very part of the shape the curve exists to draw. 0.35 is enough to keep the
    /// gradient from banding and small enough to leave the curve its slope.
    static let innerGlowBlurScale: CGFloat = 0.35

    /// How far the coupling tongue reaches *into* the selected wedge, from that wedge's inner arc.
    ///
    /// Shortened once the hub seam came in to its measured 8pt. The tongue's job is to bridge that
    /// seam, and at 26pt it was reaching most of the way across the selected card instead — a
    /// bright capsule lying on top of the icon, which in the references is a small soft nub sitting
    /// in the gap. Bloom is now a little over the seam it has to cross, and no more.
    static let couplingBloom: CGFloat = 13

    /// How far the coupling reaches back onto the well, so it meets the inset ring.
    static let couplingInset: CGFloat = 11

    /// Thickness of the coupling capsule before blur.
    static let couplingThickness: CGFloat = 16

    static let couplingBlur: CGFloat = 11

    /// Inner-arc glass highlight on an unselected wedge.
    static let innerArcWidth: CGFloat = 3.2

    /// Inner-arc highlight on the selected wedge, which is the half of the coupling that
    /// the wedge itself draws.
    static let selectedInnerArcWidth: CGFloat = 5.0

    /// Seconds for one breath of the ring. Slow enough not to compete with aiming.
    static let pulsePeriod: Double = 1.8

    /// Seconds for the traveling sheen to walk once around the ring.
    static let sheenPeriod: Double = 7.0
}
