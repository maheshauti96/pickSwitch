import SwiftUI

/// Visual-only hub chrome: the well, the brand ring, and the coupling tongue.
///
/// Split by alpha, not by a single draw pass. Translucent glow that would wash a card
/// stays *behind* the wedges. The well's opaque core and the ring stay *in front*, so
/// a turn-0 wedge's inward shadow cannot land on the caption.
///
/// The well is a fade, not a plate: a fully opaque disc under the caption, gone
/// before the rim, so the hub is a void with a halo rather than an outlined disc.
/// The opaque disc is a separate view from the falloff — a single gradient that
/// includes `Color.clear` in a non-opaque `NSPanel` lets the desktop read through
/// every stop, which is the caption the screenshots captured. Hit-testing is
/// disabled here. Clicks use `radialHubFrame` plus `HubChrome.haloReach`.
struct HubWell: View {

    let frame: CGRect
    /// The hub's light, hued by the window under the pointer. Resolved once by `OverlayView` and
    /// passed in rather than read from the palette here, so the four hub layers cannot disagree
    /// and so the per-frame `TimelineView` bodies do no colour conversion.
    let ambience: Color
    /// The hovered window's application icon, drawn *inside* this view rather than over it.
    ///
    /// That placement is the whole reason it can now be seen. As a separate layer above the well the
    /// watermark was painted on top of a finished surface, so its opacity had to be a contrast budget
    /// against the caption directly — 0.05 in Dark Mode, which is nearly nothing, and the middle of
    /// the hub was a flat plate with a rumour of a logo in it. Underneath the scrim the scrim bounds
    /// it for free: whatever the icon does, the caption sits on a surface whose luminance is already
    /// pinned to a range, so the icon is free to be a real ghosted logo.
    let backdropIcon: NSImage?
    let isRevealed: Bool
    let reduceMotion: Bool

    @Environment(\.overlayPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let clearSide = frame.width * HubChrome.wellClearFraction
        let solidFraction = HubChrome.wellOpaqueFraction / HubChrome.wellClearFraction
        let scrim = palette.hubWellFill.opacity(
            colorScheme == .dark ? HubChrome.wellScrimOpacityDark : HubChrome.wellScrimOpacityLight
        )
        // Matches `HubRing`'s stroke circle, so the bloom peaks exactly where the rim sits.
        let ringSide = frame.width - HubChrome.ringInset * 2
        // The reference is lit across the rim on both sides — about 24pt each way at Retina scale —
        // but it decays to nothing well before the middle. The opaque well hides the ring's real
        // inward blur, so this replacement bloom restores that half.
        //
        // Kept low against a measurement rather than pushed to taste. Sweeping every bearing inside
        // the rim, the dark reference's interior sits at luminance 12–22 deep in the middle and
        // climbs smoothly to 129 just inside the rim; ours measured 27–47 flat, and a hub whose
        // middle is uniformly half-lit reads as a glowing disc with a bright edge instead of a
        // bright edge around a void. The void is the point: it is what makes the ring look like
        // light rather than like a painted torus.
        //
        // What matters as much as the level is the *shape*: a smooth climb, not a plateau then a
        // step. `innerGlowStartFraction` is where that climb begins, and it has to start inside
        // the well's opaque core or the core's flat fill and the bloom meet at a visible edge.
        // Solved rather than guessed: as a fraction of the ring's own peak the reference reads
        // 0.605 / 0.313 / 0.190 / 0.135 at 8, 20, 32 and 48px inside the rim. Subtracting the
        // well's own floor, hitting those needs about 1.6x what a first pass at 0.20 produced.
        // The caption's longest line reaches 0.805 of the hub radius, where this gradient is still
        // only a third of the way up, so the 9pt secondary line measures about 6.3:1 over it —
        // `HubTintTests` holds that from the render rather than trusting the arithmetic.
        let bloom = colorScheme == .dark ? 0.45 : 0.24

        ZStack {
            // A lens rather than a plate, and that is a correction rather than a preference.
            //
            // This used to be two opaque `hubWellFill` circles, with the note that no transparent
            // pixel here meant the desktop could never read through the type. True, and it bought
            // that guarantee by making the middle of the overlay a fixed near-black or near-white
            // disc — which over any real wallpaper reads as a hole punched in the composition.
            //
            // The references do not actually settle it in favour of the plate. Their interiors
            // measure luminance 0 in the dark image and 231 in the light one, against canvases of 0
            // and 233: in both cases the interior *is* its own backdrop. A fixed fill reproduces
            // that only when the wallpaper happens to be that value, so the flat plate was an overfit
            // to the two canvases the references were drawn on. A frosted disc reproduces it over
            // anything, which is the property the references were expressing.
            //
            // What the type needs is not opacity, it is a bounded luminance *range*, and that is
            // `wellScrimOpacity` below.
            FrostedDisc(material: .hudWindow, solidFraction: solidFraction)
                .frame(width: clearSide, height: clearSide)

            // Between the blur and the scrim: the substrate shows through it, and the scrim caps it.
            if let backdropIcon {
                HubBackdropIcon(frame: frame, icon: backdropIcon)
            }

            // The contrast floor, and the only reason the two layers above are allowed to be
            // wallpaper-dependent at all.
            //
            // Solved against the palette's own type rather than chosen. The binding constraint is
            // the *secondary* line, not the primary one, which is not obvious: it is white at 0.58
            // in Dark Mode, so it composites brighter as the surface behind it brightens and loses
            // contrast twice as fast as opaque white would. Sweeping it puts the dark ceiling at
            // about luminance 66 and the light floor at about 178, and the scrim opacities in
            // `HubChrome` are what hold those against a pure-white and a pure-black desktop
            // respectively — the worst cases available.
            //
            // Deliberately pessimistic about the one quantity that cannot be measured here: the
            // arithmetic assumes the material passes the wallpaper through untouched. A real
            // `hudWindow` tints toward the appearance, so the rendered range is narrower than the
            // bound and inside it either way.
            // One layer with a feathered edge, not a crisp disc plus a blurred one.
            //
            // The old opaque pair could overlap harmlessly because 1 over 1 is still 1. Two
            // *translucent* copies compound — 0.80 over 0.80 is 0.96 — which would spend the
            // transmission this whole change is for, in the middle, where it is most visible. And a
            // single blurred circle is worse than either: a 15pt blur on a 68pt disc starts thinning
            // 9pt inside the caption's own 62pt radius, so the ends of the longest title lines would
            // sit on a scrim that had already given up part of its bound.
            //
            // A radial gradient is flat across the whole caption and feathers only in the annulus
            // past it, which is what both requirements actually ask for.
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: scrim, location: 0),
                            .init(color: scrim, location: solidFraction),
                            .init(color: scrim.opacity(0), location: 1),
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: clearSide / 2
                    )
                )
                .frame(width: clearSide, height: clearSide)

            // Light spilling *inward* off the rim.
            //
            // This has to live here rather than in `HubRing`. The ring's strokes are centred on
            // the rim and blur both ways, but the well is opaque and is drawn *after* them, so
            // everything the ring threw inward was being covered — the middle read as a flat
            // hole with a cyan outline round it, lit only on the outside. In the mocks the rim
            // lights the inside of the void as much as the void around it.
            //
            // Painted over the opaque base, never instead of it, so the caption keeps its
            // surface. Kept well clear of full strength where the glyphs actually sit.
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            // Nothing until 0.70. The caption's longest line reaches about
                            // 0.805 of the hub radius, and the 9pt secondary line is white at
                            // 58% — putting that on lit cyan measures ~4.1:1, under the bar the
                            // palette holds. So the bloom lights the inner edge of the rim and
                            // leaves the type on the flat well.
                            .init(color: ambience.opacity(0), location: 0),
                            .init(
                                color: ambience.opacity(0),
                                location: HubChrome.innerGlowStartFraction
                            ),
                            .init(
                                color: ambience.opacity(bloom * 0.34),
                                location: HubChrome.innerGlowShoulderFraction
                            ),
                            // Crests inside the rim, not on it. See `innerGlowCrestFraction`:
                            // the centreline is already carrying three other additive layers.
                            .init(
                                color: ambience.opacity(bloom),
                                location: HubChrome.innerGlowCrestFraction
                            ),
                            .init(
                                color: ambience.opacity(bloom * HubChrome.innerGlowCrestFalloff),
                                location: 1
                            )
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: ringSide / 2
                    )
                )
                .frame(width: ringSide, height: ringSide)
                // Mirrors the rear halo's breadth, not the crisp core's, which is the whole
                // point of this layer.
                .blur(radius: HubChrome.haloBlur * HubChrome.innerGlowBlurScale)
                // Normal rather than additive, for the reason given on `HubRing`'s core stroke.
                // Most of this lands on the well's own opaque fill, where the distinction does not
                // matter — but the band between that fill and the rim is over bare desktop, and
                // added to a bright wallpaper it was the single largest contributor to the rim
                // clipping out to white.
                .blendMode(.normal)
        }
        .frame(width: frame.width, height: frame.height)
        // No clip: cutting the blur at `hubRadius` is the inner circular outline
        // in the side-by-side. The fade has to die on its own before the ring.
        .allowsHitTesting(false)
        .opacity(isRevealed ? 1 : 0)
        .animation(wellReveal, value: isRevealed)
        .position(x: frame.midX, y: frame.midY)
    }

    private var wellReveal: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: OverlayReveal.duration).delay(OverlayReveal.wellDelay)
    }
}

/// The window under the pointer, as a watermark inside the well.
///
/// A second, pre-attentive answer to "which window is this?" — the caption spells it out in
/// words, and words take a moment to read.
///
/// Drawn by `HubWell`, between its frosted substrate and its scrim, and that position is what
/// changed this view's whole character. It used to sit *above* a finished opaque plate, directly
/// beneath 9 and 10pt type with nothing between, so its opacity could only ever be a contrast
/// budget against the worst icon there is — a uniformly white one in Dark Mode, a uniformly black
/// one in Light. That budget bottomed out at 0.05, which is not a watermark, it is a rumour of one.
///
/// Under the scrim the scrim owns the contrast, so this can be drawn at a strength where the
/// application is actually recognisable. What reaches the eye is `1 - wellScrimOpacity` of whatever
/// is set here, so the numbers in `HubChrome` are large where they used to be tiny and the result is
/// fainter than either.
///
/// Its reveal and its cross-fade live here rather than on the parent: the pointer crossing the ring
/// changes this as often as it changes the title, and a hard cut on a shape this large is far more
/// distracting than one on a line of text. The well's own reveal covers the layer as a whole.
struct HubBackdropIcon: View {

    let frame: CGRect
    let icon: NSImage

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let core = frame.width * HubChrome.wellOpaqueFraction
        let side = core * HubChrome.backdropIconFraction
        let opacity = colorScheme == .dark
            ? HubChrome.backdropIconOpacityDark
            : HubChrome.backdropIconOpacityLight

        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
            .blur(radius: side * HubChrome.backdropIconBlurFraction)
            .opacity(opacity)
            // Radial rather than a clip. The mask reaches zero inside the core, so the blur has
            // somewhere to end and the watermark has no edge of its own.
            //
            // Its outer radius is `backdropIconMaskReach` of the icon's half-side rather than all of
            // it, and that fraction is the difference between a watermark and a rounded rectangle
            // sitting in a circular hub. A mask that reaches zero at the *bitmap's* edge does not
            // reach zero at the artwork's edge: a macOS application icon carries roughly a sixth of
            // its bitmap as transparent padding, so the squircle's own straight sides land at about
            // 0.82 of the half-side, where a 0.40-to-1.0 gradient is still 30% opaque. At the low
            // opacities this view used to draw at, 30% of an edge was invisible and the geometry
            // never mattered. At the strength it draws at now the render showed hard vertical and
            // horizontal edges through the caption.
            .mask(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: HubChrome.backdropIconFadeStart),
                        .init(color: .clear, location: 1),
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: side / 2 * HubChrome.backdropIconMaskReach
                )
                .frame(width: side, height: side)
            )
            .frame(width: frame.width, height: frame.height)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.18), value: icon)
    }
}

/// Outer bloom, behind the wedges. Peaked toward the selection — an even stroke here
/// is what drew the outlined circle the mock does not have. The band you actually
/// read is `HubRing`, in front of the wedges.
struct HubRingHalo: View {

    let frame: CGRect
    let ambience: Color
    let angle: Double
    let isRevealed: Bool
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let hubRadius = frame.width / 2
        let outer = hubRadius + HubChrome.haloReach
        let side = outer * 2
        let additive = colorScheme == .dark
        // The void has to read as lit atmosphere the whole way round, not as a lobe beside the
        // selection with bare desktop everywhere else.
        //
        // Trimmed to the reference's outward decay. Measured as a fraction of the ring's own peak,
        // the dark reference falls to 0.23 twenty pixels outside the rim and 0.07 by fifty; ours
        // held 0.32 and 0.11 — half again as much light in the band the cards sit against, which is
        // what thickened the rim into a torus rather than leaving it a line with a tail.
        //
        // Raised back to 0.30 in Dark Mode once the core stopped being wide. The reason it was cut
        // to 0.22 — that it "thickened the rim into a torus" — was true of a 16px flat-topped core
        // with this shoulder piled on top of it. With a 10px crest the shoulder is the only thing
        // between +10px and the first card, and at 0.22 the profile read 0.21 there against the
        // reference's 0.44: not a rim with a tail, a rim with a step down to a faint ring.
        let even = colorScheme == .dark ? 0.30 : 0.20

        ZStack {
            Circle()
                .fill(
                    HubHalo.falloff(
                        ring: ambience,
                        hubRadius: hubRadius,
                        outer: outer,
                        peak: even
                    )
                )
                .frame(width: side, height: side)
                .blendMode(additive ? .plusLighter : .normal)

            // Same radial shape, brighter toward the selection.
            Circle()
                .fill(
                    HubHalo.falloff(
                        ring: ambience,
                        hubRadius: hubRadius,
                        outer: outer,
                        peak: even * 0.55
                    )
                )
                .frame(width: side, height: side)
                .mask(
                    Circle()
                        .fill(HubHalo.lobe)
                        .frame(width: side, height: side)
                        .rotationEffect(.radians(angle))
                )
                .blendMode(additive ? .plusLighter : .normal)
        }
        .blur(radius: HubChrome.haloBlur)
        .allowsHitTesting(false)
        .opacity(isRevealed ? 1 : 0)
        .animation(haloReveal, value: isRevealed)
        .position(x: frame.midX, y: frame.midY)
    }

    private var haloReveal: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: OverlayReveal.ringDuration)
    }
}

/// Brand halo on the void's rim, brightest toward the selection, breathing while up.
///
/// Drawn in front of the wedges, inset from the seam. Not a stroked circle: brightness
/// lives on the selected side and the opposite side falls to nothing, which is why the
/// mock has no outlined disc. `TimelineView` is the motion: SwiftUI will not interpolate
/// an `AngularGradient` across a transaction, so a hotspot driven only by `startAngle`
/// snapped rather than swept.
struct HubRing: View {

    let frame: CGRect
    let ambience: Color
    let angle: Double
    let isRevealed: Bool
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let paused = reduceMotion || !isRevealed
        // Exactly one of these draws, which was not previously true.
        //
        // The resting ring used to be painted unconditionally with the animated one layered over
        // it, on the belief that `TimelineView` does not produce a frame inside `cacheDisplay`.
        // It does: rendering the same hub with and without motion measures luminance 238 against
        // 184, so whenever the overlay was actually animating the core stroke was being composited
        // twice. Additively, and on top of the rear halo, that put the green and blue channels at
        // 255 for 68 of 72 bearings — the rim was a clipped white circle, and no adjustment to any
        // of these constants could change it because the arithmetic had already overflowed.
        //
        // `HubTintTests.ringIsVisibleOnTheWell` renders with motion enabled and requires the rim to
        // be brighter than the well, so the animated branch cannot silently stop painting.
        ZStack {
            if paused {
                ring(energy: 0.55, sheen: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
                    ring(
                        energy: Self.energy(at: timeline.date, paused: false),
                        sheen: Self.sheen(at: timeline.date, paused: false)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(isRevealed ? 1 : 0.88)
        .animation(ringReveal, value: isRevealed)
        .position(x: frame.midX, y: frame.midY)
    }

    private func ring(energy: Double, sheen: Double) -> some View {
        let inset = HubChrome.ringInset
        let glow = HubChrome.ringGlowThickness * CGFloat(0.90 + 0.15 * energy)
        let ringSide = frame.width - inset * 2
        let pad = HubChrome.ringGlowBlur * 3
        let additive = colorScheme == .dark
        // A narrow loop of bright light, a little brighter toward the selection. The breadth of the
        // reference's glow lives in `HubRingHalo` behind the cards; widening *this* is what turns
        // the rim into a torus.
        //
        // Bright, and nearly even around the circle. Both of those are measurements. The dark
        // reference's rim peaks at luminance 213 and is uniform the whole way round, brightening
        // only slightly at the coupling; this stroke was carrying 0.27 and measured 144, with the
        // far side down at 0.13. A dim wide ring plus a strong rear halo is precisely how a crisp
        // line of light turns into a soft coloured haze — the peak has to be sharp for the bloom
        // around it to read as bloom.
        //
        // It also fixes the saturation on its own. The reference measures 0.20 at the peak and
        // 0.27–0.31 on its shoulders: not a less saturated colour, a peak bright enough to wash
        // toward white. Ours sat at a flat 0.32 across the whole band because nothing was bright
        // enough to wash.
        // Capped short of clipping. Additive compositing over the rear halo reaches white long
        // before opacity 1, and a white rim is a different thing from a bright mint one: the
        // reference peaks at luminance 213 *while still measuring 0.196 saturation*, where 0.60
        // here clipped to 249 at 0.109 and the hue drained out of the brightest pixel on screen.
        // Near-opaque, because this stroke now blends normally rather than adding: its opacity is
        // how much of the rim's own colour survives rather than how much light it contributes.
        // `hubRing` is already the reference's measured rim, (179,223,213), so a rim drawn at full
        // strength lands on that value exactly — and lands on it over a black desktop and a bright
        // one alike, which was the whole problem.
        // Dark is near-opaque because it changed from adding light to painting it, and the
        // opacity is now how much of the rim's own colour survives. Light is left where it was:
        // it always composited normally, so it never had the clipping problem, and raising it to
        // match turned a soft bloom into a painted stroke that covered the void it sits in —
        // `HubTintTests.wellRimIsNotAPlate` catches exactly that.
        // Light Mode was raised after measuring what it actually rendered rather than what it
        // composites to in the abstract. Its per-bearing rim peaked at luminance 224 over a bright
        // desktop and 200 over a dark one, against a well of 229 and a reference rim of 254: the
        // "rim" was *darker than the surface it sits on* for part of the way round, which is not a
        // rim at all. Most of that is the blur mixing a 0.80-opacity stroke with the void beside it,
        // and the correction is opacity rather than width because the width already matches.
        let even = colorScheme == .dark ? 0.94 + 0.05 * energy : 0.86 + 0.09 * energy
        let peak = min(1, colorScheme == .dark ? 0.98 + 0.02 * energy : 0.94 + 0.06 * energy)

        return ZStack {
            // Normal blending, in both schemes, and that is the one thing here that is not a
            // matter of degree.
            //
            // The core used to composite additively in Dark Mode, which is right over a dark
            // desktop and wrong over any other: additive light added to a bright wallpaper clips,
            // and a clipped rim has no hue left. Measured over a sunset desktop the ring resolved
            // to (255,255,255) at zero saturation — a white donut — where the same code over black
            // gave (186,236,206) against the reference's (179,223,213). The wallpaper was choosing
            // the colour of the overlay's one brand signal.
            //
            // Blending normally at near-full opacity makes the rim the colour it says it is
            // whatever is behind it. The breadth around it stays additive, in `HubRingHalo`: a
            // bloom washing out against a bright surface is what light does, and it is the core
            // that has to carry the identity.
            Circle()
                .stroke(HubHalo.gradient(ring: ambience, even: even, peak: peak), lineWidth: glow)
                .frame(width: ringSide, height: ringSide)
                .padding(pad)
                .blur(radius: HubChrome.ringGlowBlur)
                .rotationEffect(.radians(angle))

            Circle()
                .stroke(sheenGradient, lineWidth: glow * 0.35)
                .frame(width: ringSide, height: ringSide)
                .padding(pad)
                .blur(radius: HubChrome.ringGlowBlur * 0.7)
                .rotationEffect(.radians(sheen))
                .blendMode(additive ? .plusLighter : .screen)
        }
    }

    private var sheenGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: 0.44),
                // Quiet. This is white, and the rim is already close to its ceiling; at 0.28 the
                // travelling highlight tipped whatever it passed over into flat white. There is no
                // white anywhere in the references' rim — only a brighter patch of the same mint.
                .init(color: .white.opacity(0.15), location: 0.5),
                .init(color: .white.opacity(0), location: 0.56),
                .init(color: .white.opacity(0), location: 1),
            ]),
            center: .center,
            angle: .degrees(0)
        )
    }

    private var ringReveal: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: OverlayReveal.ringDuration)
    }

    static func energy(at date: Date, paused: Bool) -> Double {
        guard !paused else { return 0.55 }
        let turns = date.timeIntervalSinceReferenceDate / HubChrome.pulsePeriod
        return 0.5 + 0.5 * sin(turns * 2 * .pi)
    }

    static func sheen(at date: Date, paused: Bool) -> Double {
        guard !paused else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: HubChrome.sheenPeriod)
        return phase / HubChrome.sheenPeriod * 2 * .pi
    }
}

/// Tongue of light from the inset ring into the selected wedge's inner edge.
///
/// Local to that inner arc, not a ray from the hub through inner turns. The drawing
/// frame is padded by the blur: without that, SwiftUI clips the glow to the capsule
/// and the tongue vanishes — which is what the screenshots showed.
struct HubCoupling: View {

    let centre: CGPoint
    let ambience: Color
    let angle: Double
    let innerRadius: CGFloat
    let isRevealed: Bool
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let paused = reduceMotion || !isRevealed
        // Exactly one of these draws, for the reason given on `HubRing.body`: layering the animated
        // tongue over a resting one composited the coupling twice while the overlay was up.
        ZStack {
            if paused {
                tongue(energy: 0.55)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { timeline in
                    tongue(energy: HubRing.energy(at: timeline.date, paused: false))
                }
            }
        }
        .rotationEffect(.radians(angle))
        .position(
            x: centre.x + midR * CGFloat(cos(angle)),
            y: centre.y + midR * CGFloat(sin(angle))
        )
        .allowsHitTesting(false)
        .opacity(isRevealed ? 1 : 0)
        .animation(couplingReveal, value: isRevealed)
    }

    private var startR: CGFloat { innerRadius - HubChrome.couplingInset }
    private var endR: CGFloat { innerRadius + HubChrome.couplingBloom }
    private var length: CGFloat { max(1, endR - startR) }
    private var midR: CGFloat { (startR + endR) / 2 }

    private func tongue(energy: Double) -> some View {
        let pad = HubChrome.couplingBlur * 3
        let thickness = HubChrome.couplingThickness * CGFloat(0.85 + 0.25 * energy)
        let additive = colorScheme == .dark

        return ZStack {
            Capsule()
                .fill(ambience.opacity(0.38 + 0.16 * energy))
                .frame(width: length, height: thickness)
                .blur(radius: HubChrome.couplingBlur)
            // A hint of specular, not a core. At 0.35 this was a white pill visible on top of the
            // selected card's icon — the references have no white anywhere in the coupling, only a
            // brighter patch of the same light the rim is throwing.
            Capsule()
                .fill(Color.white.opacity(0.14 + 0.08 * energy))
                .frame(width: length * 0.46, height: thickness * 0.20)
                .blur(radius: 5)
        }
        .blendMode(additive ? .plusLighter : .normal)
        .padding(pad)
    }

    private var couplingReveal: Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: OverlayReveal.couplingDuration)
            .delay(OverlayReveal.couplingDelay)
    }
}

/// Full loop of mist, brighter at 0° (then rotated to the selection).
///
/// The mock's hub is a complete ring of light, not a lobe that vanishes opposite
/// the pointer. Flooring the far side on `even` keeps the loop closed without
/// becoming a hard UI stroke.
enum HubHalo {

    /// The broad glow either side of the ring's centreline, as an explicit radial falloff.
    ///
    /// Stops trace the reference's measured decay rather than a blur's Gaussian: a long shallow
    /// tail that is still faintly lit where the first wedge begins, so the cards are composited
    /// over haze instead of over black. The inward side mirrors it; the opaque caption well
    /// covers most of that half, and `HubWell` paints the visible remainder.
    static func falloff(
        ring: Color,
        hubRadius: CGFloat,
        outer: CGFloat,
        peak: Double
    ) -> RadialGradient {
        let centreline = max(0, hubRadius - HubChrome.ringInset)
        let ringStop = Double(centreline / outer)
        let spread = Double(HubChrome.haloSpread / outer)

        func at(_ offset: Double) -> Double {
            min(1, max(0, ringStop + offset * spread))
        }

        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: ring.opacity(0), location: 0),
                .init(color: ring.opacity(0), location: at(-1.0)),
                .init(color: ring.opacity(peak * 0.16), location: at(-0.65)),
                .init(color: ring.opacity(peak * 0.42), location: at(-0.30)),
                // Crests just outside the centreline, but only just, and that distance is the whole
                // shape of the rim's outward side.
                //
                // A previous pass put the crest at `at(0.22)` — 26px out at Retina scale — on the
                // grounds that the centreline had no additive headroom left. Profiled, that drew a
                // plateau and then a cliff: the rendered rim held 0.96 of its peak 5px out where the
                // reference is at 0.57, fell to 0.30 by 10px where the reference is at 0.44, and
                // then stayed flat at 0.28 out to 30px where the reference has decayed to 0.23. Two
                // separate crests, the core's and the halo's, with a trough between them. Light does
                // not do that.
                //
                // What it should crest at instead follows from the crest not being this layer's job.
                // `HubChrome.ringGlowThickness` draws a sharp core that has decayed by +10px; this
                // is the shoulder that takes over there and holds until the first card. So it crests
                // a little outside the rim — far enough not to add to the core's own peak, near
                // enough that the two decays join without a trough — and then traces the
                // reference's measured tail: 0.44 of the ring's peak at +10px, 0.34 at +15, 0.26 at
                // +20 and 0.23 flat out to +30.
                //
                // The headroom argument that put the crest at `at(0.22)` no longer applies: the core
                // stroke blends normally now, so nothing here is racing it to 255.
                .init(color: ring.opacity(peak * 0.66), location: at(0)),
                .init(color: ring.opacity(peak), location: at(0.14)),
                .init(color: ring.opacity(peak * 0.86), location: at(0.25)),
                .init(color: ring.opacity(peak * 0.62), location: at(0.45)),
                .init(color: ring.opacity(peak * 0.40), location: at(0.65)),
                .init(color: ring.opacity(peak * 0.18), location: at(0.85)),
                .init(color: ring.opacity(0), location: 1),
            ]),
            center: .center,
            startRadius: 0,
            endRadius: outer
        )
    }

    /// Angular mask for the selection-side brightening. Never reaches zero, so the loop stays
    /// closed rather than breaking opposite the pointer.
    static let lobe = AngularGradient(
        gradient: Gradient(stops: [
            .init(color: .white, location: 0),
            .init(color: .white.opacity(0.62), location: 0.12),
            .init(color: .white.opacity(0.22), location: 0.35),
            .init(color: .white.opacity(0.22), location: 0.65),
            .init(color: .white.opacity(0.62), location: 0.88),
            .init(color: .white, location: 1),
        ]),
        center: .center,
        angle: .degrees(0)
    )

    static func gradient(ring: Color, even: Double, peak: Double) -> AngularGradient {
        let far = even * 0.70
        return AngularGradient(
            gradient: Gradient(stops: [
                .init(color: ring.opacity(peak), location: 0),
                .init(color: ring.opacity(max(even, peak * 0.55)), location: 0.12),
                .init(color: ring.opacity(far), location: 0.35),
                .init(color: ring.opacity(far), location: 0.65),
                .init(color: ring.opacity(max(even, peak * 0.55)), location: 0.88),
                .init(color: ring.opacity(peak), location: 1),
            ]),
            center: .center,
            angle: .degrees(0)
        )
    }
}
