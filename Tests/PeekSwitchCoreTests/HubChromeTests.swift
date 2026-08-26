import CoreGraphics
import SwiftUI
import Testing
@testable import PeekSwitchCore

@Suite("Hub chrome")
struct HubChromeTests {

    /// A tongue that reached across a wedge would paint the icon and steal the look of
    /// selection from the tile. Bloom is a fraction of ring thickness, not a spoke.
    @Test("Coupling bloom stays inside one ring")
    func couplingBloomIsLocal() {
        #expect(HubChrome.couplingBloom < RadialLayout.baseRingThickness / 2)
        #expect(HubChrome.couplingInset < RadialLayout.baseHubRadius / 4)
        #expect(HubChrome.couplingThickness < RadialLayout.baseRingThickness / 4)
    }

    /// The rear halo may underpaint a wedge's inner edge, but it must stay well short of the
    /// content box at the wedge's mid-radius.
    @Test("The ring halo does not reach a wedge's icon")
    func haloDoesNotReachTheIcon() {
        let midRadius = RadialLayout.baseFirstRingRadius + RadialLayout.baseRingThickness / 2
        let haloOuter = RadialLayout.baseHubRadius + HubChrome.haloReach
        #expect(haloOuter < midRadius)
    }

    /// The reference void is 28px wide against a 172px ring radius. Pin that ratio, because it is
    /// the quantity a person compares against the mock — and the one that has been wrong in both
    /// directions: 0.55 of the ring radius detached the cards, 0.15 welded them on, and 0.31 —
    /// from reading a second-turn card as the first — pushed them out again.
    @Test("The scale-1 seam matches the mock's measured void")
    func baseGapMatchesTheMockSeam() {
        let ringCentre = RadialLayout.baseHubRadius - HubChrome.ringInset
        let ringToWedge = RadialLayout.baseFirstRingRadius - ringCentre

        #expect(RadialLayout.baseHubGap == 8)
        #expect(ringToWedge == 15)
        #expect(abs(ringToWedge / ringCentre - 28.0 / 172.0) < 0.02)
        // The halo keeps painting across the seam and under the wedges, so its extent is not the
        // layout measurement. It must still stop short of the wedge's own content box.
        #expect(HubChrome.haloReach > RadialLayout.baseHubGap * 0.5)
    }

    @Test("The well restores the half of the glow hidden inside the opaque caption surface")
    func inwardGlowMirrorsTheBroadRingFalloff() {
        #expect(HubChrome.innerGlowStartFraction > HubChrome.wellOpaqueFraction * 0.75)
        #expect(HubChrome.innerGlowStartFraction < HubChrome.innerGlowShoulderFraction)
        #expect(HubChrome.innerGlowShoulderFraction < HubChrome.innerGlowCrestFraction)
        // Small, and it used to be required to be large. The bloom is a measured curve now rather
        // than four stops, and its steepest and most important section is the 8px just inside the
        // rim — narrower than a 9.6px kernel, so at the old 0.60 the blur was flattening the shape
        // the curve exists to draw. It is anti-banding, not spread.
        #expect(HubChrome.innerGlowBlurScale > 0.2)
        #expect(HubChrome.innerGlowBlurScale < 0.5)
    }

    /// The complaint this answers was that the rim's glow spread outward but not inward. It did:
    /// the outward falloff crested 8px outside the centreline and the inward bloom crested 8px
    /// inside it, from two separately hand-written tables that had drifted apart.
    ///
    /// Both now read `HubHalo.decay`, so equal distances either side of the rim carry equal light by
    /// construction. This checks the construction actually holds through the two different
    /// parameterisations — the outward gradient measures distance against a radius that runs past
    /// the wedges, the inward one against a radius that ends on the rim.
    @Test("The glow carries the same light inward as outward")
    func glowIsSymmetricAboutTheRim() {
        let ringRadius: CGFloat = 86.82
        let bloom = HubHalo.inwardBloom(ring: .white, crest: 1, ringRadius: ringRadius)

        func inwardLevel(atSpreadOffset offset: Double) -> Double {
            let location = 1 - offset * Double(HubChrome.haloSpread / ringRadius)
            let stops = bloom.stops.sorted { $0.location < $1.location }
            func alpha(_ stop: Gradient.Stop) -> Double {
                Double(NSColor(stop.color).alphaComponent)
            }
            guard let first = stops.first, location > Double(first.location) else {
                return alpha(stops[0])
            }
            for (near, far) in zip(stops, stops.dropFirst())
            where location <= Double(far.location) {
                let span = Double(far.location - near.location)
                let t = span <= 0 ? 0 : (location - Double(near.location)) / span
                return alpha(near) + t * (alpha(far) - alpha(near))
            }
            return alpha(stops[stops.count - 1])
        }

        // Over the range that is visible on both sides. Further in than this the caption surface
        // covers the bloom and `innerGlowStartFraction` has taken it to zero, which is a different
        // requirement — `wellFadesBeforeTheRing` holds that one.
        for offset in [0.05, 0.10, 0.15, 0.20, 0.25, 0.30] {
            let outward = HubHalo.level(atSpreadOffset: offset)
            let inward = inwardLevel(atSpreadOffset: offset)
            let report = "at \(offset) of a spread: inward \(inward), outward \(outward)"
            #expect(abs(inward - outward) < 0.06, "glow is lopsided \(report)")
        }

        // And it is a crest on the centreline, not a pair of edges beside it.
        #expect(HubHalo.level(atSpreadOffset: 0) == 1)
        for offset in [0.05, 0.15, 0.30, 0.60] {
            #expect(HubHalo.level(atSpreadOffset: offset) < 1)
            #expect(
                HubHalo.level(atSpreadOffset: offset)
                    == HubHalo.level(atSpreadOffset: -offset)
            )
        }
    }

    /// The inward bloom must crest *inside* the rim and fall back before it, or it spends the
    /// additive headroom the ring's own core needs and the rim clips to white all the way round.
    @Test("The inward bloom leaves the rim its headroom")
    func inwardGlowCrestsInsideTheRim() {
        #expect(HubChrome.innerGlowCrestFraction < 1)
        #expect(HubChrome.innerGlowCrestFalloff < 1)
        #expect(HubChrome.innerGlowCrestFalloff > 0)
    }

    /// The ring lives in the void, not on the wedge seam. Inset by more than the band.
    @Test("The ring sits inside the hub, not on the wedge seam")
    func ringIsInsetOntoTheWell() {
        #expect(HubChrome.ringInset > HubChrome.ringBandThickness / 2)
        #expect(HubChrome.ringInset < RadialLayout.baseHubRadius / 4)
        let centreline = RadialLayout.baseHubRadius - HubChrome.ringInset
        #expect(centreline - HubChrome.ringBandThickness / 2 > 0)
    }

    /// The well must finish fading before the ring, or the plate and the halo share an
    /// edge and the hub reads as an outlined disc.
    @Test("The well is gone before the ring")
    func wellFadesBeforeTheRing() {
        #expect(HubChrome.wellOpaqueFraction < HubChrome.wellClearFraction)
        #expect(HubChrome.wellClearFraction < 1)
        let ringFraction = (RadialLayout.baseHubRadius - HubChrome.ringInset)
            / RadialLayout.baseHubRadius
        #expect(HubChrome.wellClearFraction < ringFraction)
        // Hub typography is a 124-point disc (source + three title lines + status)
        // inside a 192-point hub. The opaque core has to cover that, including the
        // status line at the bottom.
        #expect(HubChrome.wellOpaqueFraction >= 124 / (2 * RadialLayout.baseHubRadius))
    }

    /// The mock is a halo of light, not a filled torus. A band thicker than a few points
    /// is what made the running overlay look like a cyan donut on a plate.
    ///
    /// This used to require the core to be *more* than four times `ringBandThickness`, which had it
    /// backwards: it was guarding a lower bound on a constant whose whole problem was being too
    /// large. What an eye reads as the thickness of a line is the band that looks fully lit, and by
    /// that measure a 5pt stroke under a 1.4pt blur rendered 7.5px wide at 0.90 of its peak where
    /// the reference's entire rim is 3.5px. Both assertions below are the properties that keep that
    /// band narrow.
    @Test("The core stroke is a crest, not the whole rim")
    func ringCoreIsAHairline() {
        #expect(HubChrome.ringBandThickness < 4)
        // Breadth belongs to the shoulder behind the cards. The reference's rim measures 0.105 of
        // its ring radius at half maximum and only about a fifth of that at full value, so the
        // crest is a small fraction of the spread rather than a multiple of anything.
        #expect(HubChrome.ringGlowThickness < HubChrome.haloSpread / 10)
        // The blur rounds the stroke's corners; it must not spread it. Once the blur approaches the
        // stroke's own half-width it throws the peak into the shoulders, which costs brightness and
        // widens the fully-lit band at the same time — the two halves of the same mistake.
        #expect(HubChrome.ringGlowBlur < HubChrome.ringGlowThickness / 2)
    }

    @Test("Halo reach is the broad bloom, not the crisp core")
    func haloReachMatchesTheGlow() {
        let expected = max(0, HubChrome.haloSpread - HubChrome.ringInset)
        #expect(HubChrome.haloReach == expected)
        #expect(HubChrome.haloReach < RadialLayout.baseHubRadius)
    }

    /// The bloom has to out-reach the seam, or the void in front of the cards goes black — which
    /// is exactly how it rendered when the glow was a blurred stroke clipped to its own band.
    @Test("The bloom reaches past the hub seam to the first wedge")
    func haloCrossesTheSeam() {
        #expect(HubChrome.haloReach > RadialLayout.baseHubGap)
        // Breadth belongs to the bloom; the core stays a narrow bright line on top of it.
        #expect(HubChrome.haloSpread > HubChrome.ringGlowThickness * 3)
    }

    @Test("The inner-arc highlight is a hairline, the selected one is stronger")
    func selectedInnerArcIsStronger() {
        #expect(HubChrome.innerArcWidth > 0)
        #expect(HubChrome.selectedInnerArcWidth > HubChrome.innerArcWidth)
    }

    @Test("Pulse and sheen periods are slow enough to aim against")
    func motionIsSlow() {
        #expect(HubChrome.pulsePeriod >= 1.2)
        #expect(HubChrome.sheenPeriod >= 4)
        #expect(HubChrome.sheenPeriod > HubChrome.pulsePeriod)
    }

    @Test("Paused energy is a mid breath, not zero")
    func pausedEnergyIsARestingGlow() {
        let now = Date()
        #expect(HubRing.energy(at: now, paused: true) == 0.55)
        #expect(HubRing.sheen(at: now, paused: true) == 0)
        #expect(HubRing.energy(at: now, paused: false) >= 0)
        #expect(HubRing.energy(at: now, paused: false) <= 1)
    }
}

@Suite("Wedge inner arc")
struct WedgeInnerArcTests {

    @Test("The inner arc is a real path, not an empty stroke")
    func innerArcHasLength() {
        let layout = RadialLayout(
            winding: .spiral,
            cardCount: 8,
            selectedIndex: 1,
            availableContentWidth: 1400,
            availableContentHeight: 860
        )
        let seat = layout.seat(at: 0)
        let shape = WedgeInnerArc(seat: seat, centre: layout.centre, cornerRadius: 13)
        let path = shape.path(in: CGRect(origin: .zero, size: layout.panelSize))
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width > 0)
        #expect(path.boundingRect.height > 0)
    }
}

@Suite("Hub well scrim")
struct HubWellScrimTests {

    /// The caption has to sit entirely inside the scrim's *flat* region, and this is the invariant the
    /// contrast bound quietly rests on.
    ///
    /// `OverlayPaletteTests.captionSurvivesAnyWallpaperThroughTheWell` proves the caption clears 4.5:1
    /// over a well transmitting the worst wallpaper there is — but it proves it for the scrim at full
    /// strength. The scrim feathers to nothing between `wellOpaqueFraction` and `wellClearFraction`
    /// so the hub has no outlined edge, and any type that strayed into that feather would be sitting
    /// on a surface weaker than the one that was measured. Nothing in the type or the chrome refers to
    /// the other, so the two could drift apart with no visible sign and no failing test: the caption
    /// would still render, and the bound would still be proved about a region the text had left.
    @Test("The caption fits inside the scrim's flat core at every hub size")
    func captionFitsTheFlatScrim() {
        // The smallest hub the layout will ever produce, which is the tightest case for this.
        for radius in [RadialLayout.minimumHubRadius, RadialLayout.baseHubRadius] {
            let flatRadius = radius * HubChrome.wellOpaqueFraction
            #expect(
                flatRadius >= HubTypography.captionDiameter / 2,
                """
                caption radius \(HubTypography.captionDiameter / 2) spills past the scrim's flat \
                core at \(flatRadius) on a \(radius)pt hub, so its outer lines sit on a weaker \
                surface than the contrast bound was measured against
                """
            )
        }
    }

    /// The feather exists. Without it the well is a disc with a hard edge, which is the outlined plate
    /// the middle of the overlay is built to avoid — and it is what `FrostedDisc` shipped for one
    /// build when its mask was never applied.
    @Test("The well feathers out before it reaches the ring")
    func wellFeathersBeforeTheRing() {
        #expect(HubChrome.wellClearFraction > HubChrome.wellOpaqueFraction)
        // And dies inside the ring's own centreline, so the scrim can never touch the rim.
        let clearRadius = RadialLayout.baseHubRadius * HubChrome.wellClearFraction
        #expect(clearRadius < RadialLayout.baseHubRadius - HubChrome.ringInset)
    }
}
