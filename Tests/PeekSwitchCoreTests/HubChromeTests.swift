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
        // One, near enough. This is the ratio between the blur on the inward half of the rim and
        // the blur on the outward half, and the requirement is that they match: a rim whose two
        // sides are softened by different amounts is asymmetric however carefully their levels are
        // matched, and the asymmetry lands on the crest where it shows most. It went 0.60, then
        // 0.35, each time chasing a kernel that was wide compared with the gradient under it —
        // `haloBlur` came down to 3pt instead, so neither side needs much and both can have the same.
        #expect(abs(HubChrome.innerGlowBlurScale - 1) < 0.2)
    }

    /// The complaint this answers was that the rim's glow spread outward but not inward. It did:
    /// the outward falloff crested 8px outside the centreline and the inward bloom crested 8px
    /// inside it, from two separately hand-written tables that had drifted apart.
    ///
    /// Both are now sampled from `HubHalo.level` at a shared `crest`, so the requirement is stronger
    /// than "the two are close": at any radius inside the rim, whatever share of the rear halo the
    /// well is still letting through, plus whatever `inwardBloom` restores of the share it is hiding,
    /// has to come to exactly the curve. That identity is the whole reason the inward side stopped
    /// being brighter than the outward one — it used to be the halo *plus* an independent bloom
    /// wherever the well had not yet taken over.
    ///
    /// The occlusion ramp is written out here rather than borrowed from the implementation, so this
    /// asserts the intended relationship rather than restating the code.
    @Test("The glow carries the same light inward as outward")
    func glowIsSymmetricAboutTheRim() {
        let ringRadius: CGFloat = 86.82
        let outer = ringRadius + HubChrome.ringInset + HubChrome.haloReach
        let ringStop = Double(ringRadius / outer)
        // As `HubWell` computes them: the frosted disc and scrim span `wellClearFraction` of the hub
        // and go solid at `wellOpaqueFraction`, both measured here against the ring's radius.
        let hubRadius = ringRadius + HubChrome.ringInset
        let wellEdge = Double(hubRadius * HubChrome.wellClearFraction / ringRadius)
        let wellSolid = Double(hubRadius * HubChrome.wellOpaqueFraction / ringRadius)

        func hidden(at location: Double) -> Double {
            if location <= wellSolid { return 1 }
            if location >= wellEdge { return 0 }
            return (wellEdge - location) / (wellEdge - wellSolid)
        }

        for scheme in [ColorScheme.dark, .light] {
            let scaleLength = HubHalo.scaleLength(for: scheme)
            let crest = HubHalo.crest(for: scheme)
            let outward = HubHalo.outwardGlow(
                ring: .white,
                ringStop: ringStop,
                peak: crest,
                scaleLength: scaleLength
            )
            let gain = HubHalo.inwardGain(for: scheme)
            let inward = HubHalo.inwardBloom(
                ring: .white,
                crest: crest,
                scaleLength: scaleLength,
                inwardGain: gain,
                wellSolid: wellSolid,
                wellEdge: wellEdge
            )

            for multiple in [0.0, 0.25, 0.5, 1.0, 1.6, 2.5] {
                let distance = multiple * scaleLength
                let curve = crest
                    * HubHalo.level(atDistanceFraction: distance, scaleLength: scaleLength)

                // Outward: the halo is the only thing painting, so it carries the curve alone.
                let out = Self.alpha(of: outward, at: ringStop * (1 + distance))

                // Inward: the share of the halo the well still lets through, with the bloom
                // composited over it. Normal blending, so `base + a(1 - base)` and not `base + a` —
                // treating the bloom's opacity as a contribution is what under-delivered the
                // convergence by more than half when this was first built.
                let location = 1 - distance
                let base = Self.alpha(of: outward, at: ringStop * location)
                    * (1 - hidden(at: location))
                let painted = Self.alpha(of: inward, at: location)
                let into = base + painted * (1 - base)

                // The convergence the references measure, tapered out by two scale lengths — past
                // that it is not measurable on the reference's outward side, which runs under its
                // own cards.
                let want = curve * (1 + (gain - 1) * max(0, 1 - multiple / 2))

                let report = "\(scheme) at \(multiple) scale lengths: outward \(out), "
                    + "inward \(into), curve \(curve), wanted \(want)"
                #expect(abs(out - curve) < 0.02, "outward glow left the curve — \(report)")
                #expect(abs(into - want) < 0.03, "inward glow left the curve — \(report)")
                // And the inward side is the brighter one, which is the direction both references
                // run and the reason the gain exists at all.
                #expect(into >= out - 0.01, "inward glow is the dimmer side — \(report)")
            }
        }
    }

    /// A glow with an edge is a layer; a glow that fades is light. The exponential has to still be
    /// falling where it is cut off, and be faint enough there that the cut cannot be seen.
    @Test("The glow fades rather than stopping")
    func glowHasNoVisibleEdge() {
        for scheme in [ColorScheme.dark, .light] {
            let scaleLength = HubHalo.scaleLength(for: scheme)
            // The furthest the rear bloom is allowed to paint, as a fraction of the ring's radius.
            let reach = Double(HubChrome.haloSpread / (RadialLayout.baseHubRadius - HubChrome.ringInset))
            let atTheEdge = HubHalo.level(atDistanceFraction: reach, scaleLength: scaleLength)
            #expect(
                atTheEdge < 0.06,
                "\(scheme) glow is still at \(atTheEdge) of its crest where it is cut off"
            )
            // And it is monotone, which a piecewise table is not obliged to be.
            var previous = 1.0
            for step in 1...40 {
                let value = HubHalo.level(
                    atDistanceFraction: Double(step) * 0.02,
                    scaleLength: scaleLength
                )
                #expect(value < previous, "\(scheme) glow rises again at step \(step)")
                previous = value
            }
        }
    }

    /// Interpolated alpha of a gradient's stops at a location, which is what the renderer does
    /// between them.
    private static func alpha(of gradient: Gradient, at location: Double) -> Double {
        let stops = gradient.stops.sorted { $0.location < $1.location }
        func value(_ stop: Gradient.Stop) -> Double {
            Double(NSColor(stop.color).alphaComponent)
        }
        guard let first = stops.first, let last = stops.last else { return 0 }
        if location <= Double(first.location) { return value(first) }
        for (near, far) in zip(stops, stops.dropFirst()) where location <= Double(far.location) {
            let span = Double(far.location - near.location)
            let t = span <= 0 ? 0 : (location - Double(near.location)) / span
            return value(near) + t * (value(far) - value(near))
        }
        return value(last)
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
