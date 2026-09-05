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
    var increaseContrast: Bool = false

    @Environment(\.overlayPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.overlayReduceTransparencyOverride) private var transparencyOverride

    var body: some View {
        let opaque = increaseContrast || (transparencyOverride ?? systemReduceTransparency)
        let clearSide = frame.width * HubChrome.wellClearFraction
        let solidFraction = HubChrome.wellOpaqueFraction / HubChrome.wellClearFraction
        let scrim = palette.hubWellFill.opacity(
            opaque ? 1 : (colorScheme == .dark ? HubChrome.wellScrimOpacityDark : HubChrome.wellScrimOpacityLight)
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
        // step. `HubHalo.inwardBloom` is that shape, mirrored from the outward falloff so the rim
        // reads as one glow rather than as a line with different weather on each side.
        //
        // This is the value at the rim, where the mirror makes it comparable to `HubRingHalo`'s
        // `even`. Dark went up: the rendered inward side ran 15-25 luminance short of the reference
        // over the first 8px inside the rim while matching it further in, so what was missing was
        // concentrated exactly where a mirrored crest puts it.
        //
        // Light went down, and the difference between the two is the well's own annulus. The scrim
        // stops 8.5px short of the rim, so in that band the core stroke's inward edge and the rear
        // halo are both visible underneath this layer rather than hidden by it. Solving for the
        // reference's lift over its interior — 20, 15 and 10 luminance at 4, 8 and 12px in — as
        // though this layer supplied all of it gave 0.80, which rendered at about twice the
        // reference the whole way in and left a 10.5px band at 0.90 of peak where the reference has
        // 4.4px. 0.38 is the same solve with the underneath accounted for.
        //
        // The caption is unaffected, which is the point of buying the shape here rather than by
        // raising the level everywhere: at the radii the longest title line actually reaches, the
        // new curve is within a hundredth of the one it replaces. `HubTintTests` measures that from
        // the render rather than trusting this note.
        let bloom = HubHalo.crest(for: colorScheme)

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
            if !opaque {
                FrostedDisc(material: .hudWindow, solidFraction: solidFraction)
                    .frame(width: clearSide, height: clearSide)
                    .opacity(colorScheme == .dark ? 0.36 : 0.70)
            }

            // Between the blur and the scrim: the substrate shows through it, and the scrim caps it.
            if let backdropIcon, !opaque {
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
                        gradient: HubHalo.inwardBloom(
                            ring: ambience,
                            crest: bloom,
                            scaleLength: HubHalo.scaleLength(for: colorScheme),
                            inwardGain: HubHalo.inwardGain(for: colorScheme),
                            // The well's own occlusion, in the bloom's units: the frosted disc and
                            // the scrim are `clearSide` across and go solid at `solidFraction` of
                            // that, while this gradient measures radius against the ring.
                            wellSolid: Double(clearSide * solidFraction / ringSide),
                            wellEdge: Double(clearSide / ringSide)
                        ),
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
                .opacity(opaque ? 0 : 1)
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
    var isVisible: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HubMotionView(animated: HubMotion.shouldAnimate(
            isVisible: isVisible, isRevealed: isRevealed, reduceMotion: reduceMotion
        )) { motion in halo(energy: motion.energy) }
    }

    private func halo(energy: Double) -> some View {
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
        // Raised again, and this time it is the *shape* in `HubHalo.falloff` that made the level
        // affordable. While that gradient crested 8px outside the rim, every increase here widened
        // the bright band before it filled the shoulder — which is the "torus" the earlier cut to
        // 0.22 was reacting to. With the crest on the centreline the level sets how far the glow
        // reaches and the curve sets how quickly it gets there, so they stopped fighting.
        //
        // Both numbers are the reference's own decay divided by this layer's colour. Dark: 126 of
        // 241 at +4px is 0.52, and 0.55 is that with the crest's 0.95 shape factor taken out. Light
        // is the same solve against a much smaller range — the light reference lifts its canvas by
        // about 10 luminance at +8px and 6 at +16px, and over a 232 canvas with a 253 rim there are
        // only 21 luminance available, so it needs most of them. That is why the light value went up
        // nearly three times: at 0.20 the rendered glow was gone 8px out, and the light reference's
        // is still going at +20.
        let even = HubHalo.crest(for: colorScheme) * (0.72 + 0.28 * energy)

        let scaleLength = HubHalo.scaleLength(for: colorScheme)

        return ZStack {
            Circle()
                .fill(
                    HubHalo.falloff(
                        ring: ambience,
                        hubRadius: hubRadius,
                        outer: outer,
                        peak: even,
                        scaleLength: scaleLength
                    )
                )
                .frame(width: side, height: side)
                .blendMode(additive ? .plusLighter : .normal)

            // Same radial shape, a little brighter toward the selection.
            //
            // A little, where it used to be 0.55 of the even layer on top of the even layer — the
            // glow was 1.55 times brighter at the selection than opposite it. The references put
            // their dimmest bearing at 0.92 and 0.99 of the brightest, so a lobe that strong is not
            // something they do, and it is the second thing that makes the glow read as applied
            // rather than emitted: a bright patch that moves with the pointer is a highlight, and a
            // highlight sitting on a ring looks like a layer on the ring. The selection is already
            // marked twice over — by `HubCoupling`'s tongue and by `HubHalo.gradient`'s own angular
            // peak on the core stroke.
            Circle()
                .fill(
                    HubHalo.falloff(
                        ring: ambience,
                        hubRadius: hubRadius,
                        outer: outer,
                        peak: even * 0.20,
                        scaleLength: scaleLength
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
        .scaleEffect(0.992 + 0.016 * energy)
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

/// A breathing, gently rippling optical rim around a fixed caption/hit target.
struct HubRing: View {
    let frame: CGRect
    let ambience: Color
    let angle: Double
    let isRevealed: Bool
    let reduceMotion: Bool
    var isVisible: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HubMotionView(animated: HubMotion.shouldAnimate(
            isVisible: isVisible, isRevealed: isRevealed, reduceMotion: reduceMotion
        )) { motion in
            ring(motion: motion)
        }
        .allowsHitTesting(false)
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(isRevealed ? 1 : 0.88)
        .animation(ringReveal, value: isRevealed)
        .position(x: frame.midX, y: frame.midY)
    }

    private func ring(motion: HubMotion.Sample) -> some View {
        let ringSide = max(1, frame.width - HubChrome.ringInset * 2)
        let glow = HubChrome.ringGlowThickness * CGFloat(0.90 + 0.25 * motion.energy)
        let pad = HubChrome.haloSpread
        let even = colorScheme == .dark ? 0.76 + 0.22 * motion.energy : 0.84 + 0.15 * motion.energy
        let peak = min(1, even + 0.08)
        let contour = LiquidHubContour(motion: motion)

        return ZStack {
            // The moving contour carries its own soft shoulder; the wider, quiet
            // atmospheric field remains in HubRingHalo behind the cards.
            contour
                .stroke(ambience.opacity(0.18 + 0.22 * motion.energy), lineWidth: 10)
                .frame(width: ringSide, height: ringSide)
                .padding(pad)
                .blur(radius: 7)
                .opacity(colorScheme == .light ? 0.45 : 1)
                .blendMode(colorScheme == .light ? .plusLighter : .normal)
            contour
                .stroke(HubHalo.gradient(ring: ambience, even: even, peak: peak, angle: angle), lineWidth: glow)
                .frame(width: ringSide, height: ringSide)
                .padding(pad)
                .blur(radius: HubChrome.ringGlowBlur)
            // A narrow achromatic crest reads as emitted light on a bright
            // desktop; tint belongs in the shoulder, not in a dull outline.
            contour
                .stroke(.white.opacity(colorScheme == .light ? 0.94 : 0), lineWidth: glow * 0.38)
                .frame(width: ringSide, height: ringSide)
                .padding(pad)
                .blur(radius: 0.45)
            // Rotate the light, not a second copy of the contour. Both strokes
            // must describe exactly the same liquid boundary.
            contour
                .stroke(sheenGradient(phase: motion.phase), lineWidth: glow * 0.72)
                .frame(width: ringSide, height: ringSide)
                .padding(pad)
                .blur(radius: 0.45)
                .blendMode(colorScheme == .dark ? .screen : .normal)
        }
    }

    private func sheenGradient(phase: Double) -> AngularGradient {
        AngularGradient(gradient: Gradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: 0.40),
            .init(color: .white.opacity(0.42), location: 0.50),
            .init(color: .white.opacity(0), location: 0.60),
            .init(color: .white.opacity(0), location: 1),
        ]), center: .center, angle: .radians(phase))
    }

    private var ringReveal: Animation? {
        reduceMotion ? nil : .easeOut(duration: OverlayReveal.ringDuration)
    }

    static func energy(at date: Date, paused: Bool) -> Double {
        HubMotion.sample(at: date.timeIntervalSinceReferenceDate, animated: !paused).energy
    }

    static func sheen(at date: Date, paused: Bool) -> Double {
        HubMotion.sample(at: date.timeIntervalSinceReferenceDate, animated: !paused).phase
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
    var isVisible: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HubMotionView(animated: HubMotion.shouldAnimate(
            isVisible: isVisible, isRevealed: isRevealed, reduceMotion: reduceMotion
        )) { motion in tongue(energy: motion.energy) }
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

    /// How far the glow falls away from the rim, as a fraction of its crest, at a distance from the
    /// centreline measured in fractions of the ring's own radius.
    ///
    /// One function, used in both directions, and that is most of what makes the rim read as a lit
    /// line rather than as a bright circle with a second circle painted around it.
    ///
    /// It is an exponential because that is what the reference *is*. Sweeping inward from the dark
    /// reference's rim — the clean side, with no cards over it — and asking at each distance what
    /// scale length would produce the level measured there, the answer comes back constant: 16.4px
    /// at 2px in, 16.1 at 4, 15.8 at 6, 16.1 at 8, 16.8 at 12, 16.9 at 16, 17.3 at 20, 18.7 at 30,
    /// 18.9 at 40, 18.5 at 50, 16.9 at 60. That is a level falling from 0.885 to 0.029 of peak — two
    /// decades — described to within 0.03 by a single number, on a 172px ring.
    ///
    /// What that buys over the ten-stop table it replaces is not tidiness. A piecewise table has a
    /// slope discontinuity at every stop and, worse, an end: the old one was pinned to zero at a
    /// definite radius, so the glow *stopped* rather than faded. Both are things light does not do,
    /// and both are what "another layer added onto the circle" describes. An exponential has no
    /// kinks and no edge, and it is scale-free — every part of it looks like the same glow seen from
    /// nearer or further, which is why real scattering looks the way it does.
    ///
    /// It is symmetric by construction, depending only on `abs(distance)`. Getting that wrong twice
    /// is what prompted the rewrite: the outward falloff crested 26px out, then 8px out, on the
    /// reasoning that the core stroke owned the centreline, while `HubWell`'s inward bloom crested
    /// 8px *in*, from a separately maintained table. Two crests either side of a line is three
    /// bright rings, and it measured that way. `HubChromeTests` compares the two directions at equal
    /// distances.
    static func level(atDistanceFraction distance: Double, scaleLength: Double) -> Double {
        exp(-abs(distance) / max(scaleLength, 0.0001))
    }

    /// Scale length for the exponential above, per scheme, as a fraction of the ring's radius.
    ///
    /// Least-squares fits to the references over the first 50px inward, which is where each has
    /// signal. Dark lands on 0.108 with every individual sample inside 0.092...0.110, so it is taken
    /// as read. Light fits 0.065 and drifts upward near the rim, for a reason worth stating rather
    /// than averaging away: its entire glow spans 23 luminance against Dark Mode's 210, so past
    /// about 30px in the samples sit within two levels of the interior and the fit is reading
    /// quantisation. 0.075 is that fit weighted toward the near-field samples, which are the ones
    /// carrying information — and it is tighter than Dark Mode's, which is also what the near field
    /// says: the light reference is at 0.63 of peak 8px in where the dark one is at 0.61 but falls
    /// to 0.20 by 20px where the dark one holds 0.31.
    static func scaleLength(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.105 : 0.075
    }

    /// Where to put stops: multiples of the scale length rather than of any radius, so the curve is
    /// sampled where it is steep whatever the hub's size or the scheme.
    ///
    /// Out to five scale lengths, by which point the glow is at 0.007 of its crest. Linear
    /// interpolation between neighbours never leaves the curve by more than 0.004, which is a
    /// quarter of a luminance level on the dark rim.
    static let stopMultiples: [Double] = [
        0, 0.12, 0.25, 0.4, 0.55, 0.75, 1.0, 1.3, 1.6, 2.0, 2.5, 3.0, 3.6, 4.3, 5.0,
    ]

    /// The broad glow either side of the ring's centreline, behind the wedges.
    ///
    /// Locations are fractions of `outer`; a signed distance `d` in fractions of the ring's own
    /// radius sits at `ringStop * (1 + d)`. Stops that fall outside `0...1` are dropped rather than
    /// clamped: clamping stacks several of them on the boundary, which is a step.
    static func falloff(
        ring: Color,
        hubRadius: CGFloat,
        outer: CGFloat,
        peak: Double,
        scaleLength: Double
    ) -> RadialGradient {
        let centreline = max(0, hubRadius - HubChrome.ringInset)
        return RadialGradient(
            gradient: outwardGlow(
                ring: ring,
                ringStop: Double(centreline / outer),
                peak: peak,
                scaleLength: scaleLength
            ),
            center: .center,
            startRadius: 0,
            endRadius: outer
        )
    }

    /// `falloff`'s stops, separately so they can be read back. A `RadialGradient` cannot be
    /// introspected, and the one property worth testing here is that these agree with
    /// `inwardBloom`'s at equal distances from the rim.
    static func outwardGlow(
        ring: Color,
        ringStop: Double,
        peak: Double,
        scaleLength: Double
    ) -> Gradient {
        // Inward first, then outward, so the locations ascend. The two halves meet on the centreline
        // at the same value, which is what makes the rim a crest rather than a pair of edges.
        let signed = stopMultiples.reversed().map { -$0 }.dropLast() + stopMultiples

        let stops = signed.compactMap { multiple -> Gradient.Stop? in
            let distance = multiple * scaleLength
            let location = ringStop * (1 + distance)
            guard location > 0, location < 1 else { return nil }
            return Gradient.Stop(
                color: ring.opacity(
                    peak * level(atDistanceFraction: distance, scaleLength: scaleLength)
                ),
                location: CGFloat(location)
            )
        }

        return Gradient(stops:
            [Gradient.Stop(color: ring.opacity(0), location: 0)]
            + stops
            + [Gradient.Stop(color: ring.opacity(0), location: 1)]
        )
    }

    /// The inward half of the same glow, painted by `HubWell` — not as a second glow, but as
    /// whatever share of the *first* one the caption surface is hiding.
    ///
    /// That reframing is the point, and it is what finally made the two sides match. `HubRingHalo`
    /// paints a full circle, so its inward half is drawn too; the well only hides the part of it
    /// under the frosted disc and the scrim. Treating this as an independent glow therefore
    /// double-counted wherever the well had *not* yet taken over — in the annulus between the
    /// scrim's edge and the rim the halo, the core stroke and this layer were all visible at once,
    /// which measured as 0.91 of peak 2px inside the rim against 0.75 two px outside it. The rim was
    /// still lopsided after its levels had been matched, because one side had one more layer on it.
    ///
    /// So this is weighted by the well's own occlusion: nothing at the rim, where the halo is
    /// unobstructed and needs no help, rising to the full curve where the frosted disc is opaque and
    /// the halo is gone. Weighted with the same ramp `FrostedDisc.mask` uses, since that mask is what
    /// decides how much of the halo survives. Add the visible halo to the restored share and the
    /// result is the curve itself — so with a shared `crest` the inward profile is not merely tuned
    /// to the outward one, it is arithmetically the same.
    ///
    /// - Parameters:
    ///   - wellSolid: where the well becomes fully opaque, as a fraction of the ring's radius.
    ///   - wellEdge: where the well has faded to nothing, in the same units.
    static func inwardBloom(
        ring: Color,
        crest: Double,
        scaleLength: Double,
        inwardGain: Double,
        wellSolid: Double,
        wellEdge: Double
    ) -> Gradient {
        /// How much of the rear halo the well is hiding at this radius.
        func hidden(at location: Double) -> Double {
            guard wellEdge > wellSolid else { return location <= wellSolid ? 1 : 0 }
            if location <= wellSolid { return 1 }
            if location >= wellEdge { return 0 }
            return (wellEdge - location) / (wellEdge - wellSolid)
        }

        // How much brighter the inward side is than the outward one at this distance.
        //
        // A measurement I had first mistaken for a bug. Having made the two sides arithmetically
        // identical, the rendered rim came out symmetric to within 10% — and measurably *wrong*:
        // 122.6 luminance 4px inside the rim where the reference reads 163.6, against 130.0 outside
        // where it reads 125.9. The reference is not symmetric. It runs 1.06, 1.34, 1.34, 1.33, 1.38,
        // 1.48 and 1.57 times brighter inward at 2, 4, 6, 8, 12, 16 and 20px.
        //
        // Which is what a ring of light does rather than something to correct. Every point on the
        // circle throws light both ways; inside the circle those contributions converge and outside
        // they diverge, so a luminous annulus is brighter within itself than beside itself at equal
        // distance, before any of it lands on a surface.
        //
        // Tapered to nothing by two scale lengths because that is where the evidence runs out. The
        // ratios above are measured over the first 20px, which is a little under two scale lengths;
        // past that the reference's outward side runs under its own cards and the rising ratio is at
        // least as likely to be the outward side being covered as the inward side being brighter.
        // Extrapolating a gain into the region the caption occupies would be spending the caption's
        // contrast on a guess.
        func gain(atDistance distance: Double) -> Double {
            let taper = max(0, 1 - distance / (2 * scaleLength))
            return 1 + (inwardGain - 1) * taper
        }

        // The alpha that *composites* onto the level wanted here, which is not the same as the level
        // itself and was the last thing wrong with this layer.
        //
        // This blends normally rather than additively — deliberately, because in the annulus outside
        // the scrim it lands on bare wallpaper and adding light there is what used to clip the rim to
        // white. Normal blending does not add, though, so treating its opacity as a contribution
        // under-delivered by more than half: asking for 35% more light than the halo already provided
        // painted 0.19 alpha and produced 140.2 luminance where 175 was wanted, because most of what
        // it painted merely replaced light that was already there.
        //
        // Solving it instead is exact. With everything as a fraction of this layer's own colour, the
        // halo already showing through the well is `base`, the level wanted is `target`, and normal
        // compositing gives `base + a(1 - base)`, so `a` follows.
        func alpha(at location: Double) -> Double {
            let distance = 1 - location
            let curve = crest * level(atDistanceFraction: distance, scaleLength: scaleLength)
            let base = curve * (1 - hidden(at: location))
            let target = curve * gain(atDistance: distance)
            guard base < 0.999 else { return 0 }
            return min(1, max(0, (target - base) / (1 - base)))
        }

        // The curve's own sample points, plus the two ends of the occlusion ramp — the ramp has
        // corners the curve does not, and a stop has to land on each or the interpolation cuts them.
        let curveLocations = stopMultiples.map { 1 - $0 * scaleLength }
        let locations = (curveLocations + [wellEdge, wellSolid])
            .filter { $0 > Double(HubChrome.innerGlowStartFraction) && $0 <= 1 }
            .sorted()

        let stops = locations.map { location in
            Gradient.Stop(
                color: ring.opacity(alpha(at: location)),
                location: CGFloat(location)
            )
        }

        return Gradient(stops:
            [
                Gradient.Stop(color: ring.opacity(0), location: 0),
                Gradient.Stop(
                    color: ring.opacity(0),
                    location: HubChrome.innerGlowStartFraction
                ),
            ] + stops
        )
    }

    /// How strongly the glow is painted at the rim, per scheme.
    ///
    /// One value for both halves, which is only meaningful because `inwardBloom` is now the halo's
    /// stand-in rather than a second glow. It used to be two — 0.30/0.20 for the rear halo and
    /// 0.45/0.24 for the inward bloom — and they were adjusted independently, which is how the two
    /// sides of one line ended up with different weather on them.
    ///
    /// Solved against the references' absolute luminance rather than chosen. In Dark Mode the
    /// reference reads 125.9 four pixels outside its rim; the core stroke is finished by then, so
    /// that number is the glow alone, and dividing by `hubRing`'s own luminance and by the curve's
    /// value at 4px gives this. Light is the same solve over a range twenty times smaller: its
    /// reference lifts a 230 canvas to 244 four pixels out.
    static func crest(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.63 : 0.80
    }

    /// How much brighter the glow is inside the ring than outside it, at equal distance.
    ///
    /// Measured from the references over the first 20px, where neither side is contaminated: the
    /// dark image runs 1.34, 1.34, 1.33, 1.38, 1.48 times brighter inward at 4, 6, 8, 12 and 16px,
    /// and the light one 1.22, 1.17, 1.15, 1.04. Both are flat enough over that range to be one
    /// number, and it is a number rather than a shape because the cause is geometric: light from
    /// every point on a luminous circle converges inside it and diverges outside.
    static func inwardGain(for scheme: ColorScheme) -> Double {
        scheme == .dark ? 1.35 : 1.10
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

    /// Angular shape of the rim's own brightness: a little hotter toward the selection, and
    /// otherwise a line of even light.
    ///
    /// `far` is what the side opposite the pointer keeps, and 0.70 was too little. Sweeping every
    /// bearing's own peak, the references' rims are close to uniform — the dimmest bearing is 0.92
    /// of the brightest in the dark image and 0.99 in the light one — while ours measured 0.74, with
    /// the dim side at luminance 190 against a median of 230. A rim that is a quarter darker for a
    /// third of its length does not read as a brighter rim with a hotspot; it reads as a dim rim,
    /// because the eye judges a closed line by its weakest arc. That is most of what "not bright
    /// enough" was pointing at, and it costs nothing to fix: the selection still gets its lift from
    /// `peak` here and from `HubRingHalo`'s lobe behind the cards.
    static func gradient(ring: Color, even: Double, peak: Double, angle: Double = 0) -> AngularGradient {
        let far = even * 0.90
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
            angle: .radians(angle)
        )
    }
}
