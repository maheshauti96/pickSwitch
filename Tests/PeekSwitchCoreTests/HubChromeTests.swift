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
        #expect(HubChrome.innerGlowBlurScale > 0.5)
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
    @Test("The core stroke is a hairline, not a torus")
    func ringCoreIsAHairline() {
        #expect(HubChrome.ringBandThickness < 4)
        #expect(HubChrome.ringGlowThickness > HubChrome.ringBandThickness * 4)
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
