import AppKit
import SwiftUI

/// Colours for the overlay, taken from the design's dark and light themes.
///
/// ## Why explicit colours rather than semantic ones
///
/// The cards used to be a 5–22% tint of `.primary` sitting on the panel's blurred
/// plate, and text used `.primary` against it. That works only while there *is* a
/// plate. With a transparent container the tint became a tint of the user's desktop,
/// so a card over dark wallpaper in Light Mode ended up dark with black text on it —
/// the app names disappeared entirely.
///
/// The design solves this the same way: cards carry their own fill and name their text colour
/// outright, so contrast is a property of the card rather than a lucky consequence of what happens
/// to be behind it.
///
/// Those fills are now fully opaque, and the last few percent mattered more than they sound. Only
/// the list draws a backdrop; the strip, grid and both round arrangements have none, so a card is
/// the only thing between its own caption and the desktop. At 92–96% a text-heavy window behind the
/// overlay — an editor, a long document — read straight through it, and the hollow middle of the
/// spiral was the worst of it: the most translucent surface in the app carrying the smallest type.
///
/// Requirement 3.10 still holds — the palette is chosen from the environment's colour
/// scheme, so the overlay follows the system appearance.
struct OverlayPalette {

    let cardFill: Color
    let selectedCardFill: Color
    /// The thumbnail well, a shade apart from the card so an empty preview still reads
    /// as a picture area rather than blank card.
    let thumbnailFill: Color
    let border: Color
    let strongBorder: Color
    let text: Color
    let secondaryText: Color

    /// `secondaryText` for the hub's caption only, weighted for a surface that is not a known colour.
    ///
    /// The hub is the one place in the overlay whose background is partly the user's wallpaper. Every
    /// other secondary line sits on a card fill this palette chose, so `secondaryText` can be tuned
    /// for hierarchy there; here it has to survive a range.
    ///
    /// And it is the line that sets that range, which is worth being explicit about because it is not
    /// the intuition: a *translucent* white line composites brighter as its own surface brightens, so
    /// it loses contrast about twice as fast as opaque white does. At `secondaryText`'s 0.58 in Dark
    /// Mode the well could only transmit 20% of the wallpaper before this line fell under 4.5:1 —
    /// enough to tint the middle, not enough for it to read as glass. The primary title, being
    /// opaque, was nowhere near binding.
    ///
    /// So the hub's secondary lines give up some of their opacity difference and the well buys
    /// transmission with it: 0.85 here takes the dark ceiling from luminance 66 to about 100, which is
    /// what `HubChrome.wellScrimOpacityDark` spends. The hierarchy is not lost with it, because in the
    /// hub it was never carried by opacity alone — the title is 15pt semibold against 11pt and 10pt
    /// medium, and those sizes are doing most of the work.
    let hubSecondaryText: Color
    /// Backing for captions that float with no plate behind them.
    let chipFill: Color
    /// Selection colour, for borders and glows.
    ///
    /// Deliberately fixed rather than `.accentColor`: the overlay panel is never key,
    /// and SwiftUI desaturates the system accent in a window that is not active, which
    /// would leave the selected card outlined in grey — the one thing on screen that
    /// must not be ambiguous.
    let accent: Color
    /// Selection colour for surfaces that carry text, such as the list's selected row.
    ///
    /// A shade darker than `accent`, and that is a deliberate departure from the mock:
    /// white on the design's `#0088b0` measures 4.08:1, just under the 4.5:1 the rest
    /// of the overlay holds itself to. Darkening the fill keeps the same hue while
    /// making the row text properly legible; the border keeps the brighter value, where
    /// contrast with text is not in question.
    let accentFill: Color
    let onAccentText: Color
    let onAccentSecondaryText: Color
    let liveIndicator: Color
    /// Marks a window whose application is capturing from the microphone.
    ///
    /// Orange because that is what macOS itself uses for the microphone in the menu bar, and a user
    /// who has learned "orange means something is listening" from the system should not have to
    /// learn a second colour here. Chrome draws this red on its own tab strip; the platform's
    /// convention wins over one browser's.
    ///
    /// Dark and light are genuinely different values rather than one colour reused. The light card
    /// is white, and the shade that measures 6.5:1 on a dark card measures 2.2:1 on white — under
    /// the 3:1 an icon has to clear.
    let microphoneIndicator: Color
    /// How far a card's fill may be pushed toward its window's icon hue, `0...1`.
    ///
    /// Small on purpose, and owned here rather than by the icon: the fill still has to carry text
    /// at 4.5:1, and that is the whole reason this type names its colours outright. `IconTint`
    /// supplies a hue; these three values are what keep the result inside a luminance band the
    /// palette's text colours were chosen against.
    let tintStrength: Double
    /// Saturation and brightness of the colour the fill is pushed toward. Together with
    /// `tintStrength` these bound the tint whatever hue an icon turns out to have.
    let tintSaturation: Double
    let tintBrightness: Double

    /// Colour under the radial caption.
    ///
    /// The hub rim is a void; this fill is the caption's surface — an opaque circle
    /// large enough for the source, title and status line, so a busy desktop cannot
    /// read through it. The ring and coupling may be translucent; this is not.
    let hubWellFill: Color

    /// Brand ring that sits on the well's rim and carries radial selection.
    ///
    /// The resting colour, used whenever there is no hue to take: a monochrome icon, Increase
    /// Contrast, or the tint setting turned off. What the ring actually draws is
    /// `hubAmbience(for:)`, which carries this hue only until the pointer reaches a window that
    /// has one of its own.
    let hubRing: Color

    /// Saturation the hub's ambience aims for at full vividness.
    ///
    /// Stated outright rather than inherited from `hubRing`, and that is the fix for a Light Mode
    /// hub that showed no colour at all. The ambience used to ask for the resting ring's own
    /// saturation — fine in Dark Mode, where that is 0.18, and useless in Light, where the resting
    /// ring is (250,255,255) and 0.0196 saturated. Rendered, every light window produced a rim of
    /// chroma 3 against Dark Mode's 16–39: nominally the right hue, and grey to look at.
    ///
    /// The resting ring is near-white on purpose — with no window under the pointer there is nothing
    /// to say — so how loudly a hue gets said had to stop being the same number.
    let hubAmbienceSaturation: Double

    /// How much of `hubAmbienceSaturation` may be given up to reach the target luminance.
    let hubAmbienceSaturationFloor: Double

    /// Fraction of the resting ring's luminance the ambience is solved onto.
    ///
    /// Below 1 in Light Mode because near white, chroma and luminance trade directly against each
    /// other: at the resting ring's own luminance there is no room for any colour, and every hue
    /// resolves to the same white. Coming down buys the chroma back. How far down is bounded by the
    /// well underneath — the rim has to stay lighter than what it encircles, which in Light Mode is
    /// already luminance 197–206 of a possible 255.
    let hubAmbienceLuminanceScale: Double

    /// How much stronger a selected radial wedge is tinted than an unselected one.
    ///
    /// Greater than 1 so the selected tile is a stronger version of itself rather than a recolor
    /// to the brand. The brand lives on the ring. Bounded so primary text still clears 4.5:1.
    let radialSelectedStrengthScale: Double

    /// Hue of a wedge's glass, used as a Liquid Glass tint and as the coloured wash.
    ///
    /// Brighter and more chromatic than `cardFill(tintedBy:)`, which has to carry 4.5:1
    /// text as an opaque plate. Glass gets its identity from a wash and a rim light, not
    /// from a solid fill, so this colour is allowed to be the icon's own.
    ///
    /// Saturation is the mock: dark tiles are stained glass (green Chrome, pink Slack,
    /// orange Claude), not grey material with a coloured edge. Light tiles are pastels
    /// at roughly 30% chroma on the selected cyan, 5–12% on the rest.
    func glassTint(for tint: IconTint?, selected: Bool, scheme: ColorScheme) -> Color {
        if selected {
            // Lit, and lit in the window's own colour.
            //
            // This used to return the brand cyan outright, on the authority of the mock — whose
            // selected wedge happens to be Chrome, drawn cyan. Reading one tile as "selection is
            // cyan" was the wrong generalisation: every *other* wedge on the ring is already its own
            // hue, and the rim light of this one has followed the window since `glassRim` started
            // deferring to `hubAmbience`. So the selected body was the one surface on screen that
            // threw the window's identity away at the moment of pointing at it, and it contradicted
            // its own edge while doing it.
            //
            // What made the cyan read as *selected* was never the hue, it was the level: 0.72
            // saturation at 0.54 brightness against a resting body that reaches at most 0.47 at
            // 0.23. Keeping that level and moving the hue keeps the signal and returns the identity.
            let litSaturation = scheme == .dark ? 0.72 : 0.30
            let lit = Color(
                hue: Self.brandHue,
                saturation: litSaturation,
                brightness: scheme == .dark ? 0.54 : 0.96,
                opacity: 1
            )
            // No hue to take — a monochrome icon, tinting switched off, Increase Contrast — leaves
            // the brand, which is what the hub ring falls back to for the same reason.
            guard let tint, let base = NSColor(lit).usingColorSpace(.sRGB) else { return lit }
            // Solved onto the cyan's luminance rather than reusing its brightness, because those
            // are different quantities and the difference is what would break this: holding
            // brightness while the hue moves swings luminance about 2.3x across the wheel, and this
            // surface carries the application's name. See `rehued`.
            return Self.rehued(
                base,
                to: tint.hue,
                saturation: litSaturation * min(1, max(0.6, tint.vividness)),
                saturationFloor: Self.ambienceSaturationFloor
            )
        }
        // Opaque, and a real colour rather than a veil of white.
        //
        // A window whose icon yields no usable hue — a monochrome one like Cursor, or any window
        // at all once icon tinting is switched off — used to land here on `white.opacity(0.06)`,
        // which after the wash left a card about 5% opaque: not a neutral card but very nearly no
        // card, taking whatever the wallpaper happened to be. That is why the greyscale-iconed
        // windows are the palest, most washed-out wedges on the ring in practice while the
        // references draw them as plain dark and plain light plates like all the others.
        //
        // Values are the references' own untinted bodies, measured per card rather than as a field
        // average: ChatGPT (19,19,19), Cursor (21,21,21) and Grok Bot (27,27,27) in the dark
        // reference, and 244–247 for the same three in the light one. A first pass read the dark
        // figure as 46 off a whole-annulus average, which folds in every *tinted* card and the rim
        // light on all of them; drawn at 46 the greyscale-iconed wedges were the brightest thing on
        // a dark ring instead of the darkest.
        guard let tint else {
            return scheme == .dark
                ? Color(.sRGB, white: 0.095, opacity: 1)
                : Color(.sRGB, white: 0.96, opacity: 1)
        }
        // These are the colour the card actually *is*, not a hint added to whatever is behind it,
        // and that changed what the numbers had to be.
        //
        // They were previously calibrated by rendering the overlay over flat black and flat cream,
        // which is not a condition any user is ever in. Measured over a real desktop the same
        // constants produced a dark card at luminance 106–119 against the reference's 55, with its
        // saturation cut from 0.34 to 0.20 — the wallpaper was supplying most of the card and the
        // tint was a wash on top of it. Worse, a Light Mode card over a *dark* desktop came out at
        // luminance 68, where its near-black label measures 1.70:1.
        //
        // So `glassWashOpacity` now lets the tint dominate, and these values are what the composite
        // has to land on rather than what looks right in isolation.
        //
        // Dark Mode is built additively rather than as a fixed HSB brightness, because that is what
        // the reference measures. Reading its cards one at a time: the *minimum* channel is close to
        // constant — 17 to 34 across every wedge, right where the untinted ones sit — while the
        // dominant channels rise with the icon, from 0 chroma on ChatGPT and Cursor through 16 on
        // Chrome and Kiro to 32 on Brave. The tint is light *added* on top of a common dark floor.
        //
        // A fixed brightness does the opposite. Holding it at 0.26 and varying only saturation makes
        // a more saturated card a *darker* one, so every wedge landed in the same narrow band: the
        // field measured chroma 0 at its 25th percentile and only 24 at its 90th, against the
        // reference's 6 and 52. Neutral windows were too bright and vivid ones not vivid enough — a
        // ring of interchangeable slate tiles, which is the "glass looks less tinted than the mock"
        // complaint stated in numbers.
        //
        // So the floor is fixed and the chroma is what `vividness` buys. `floor` is the untinted
        // body above; `lift` is up to 38/255 of added chroma, which is the reference's widest card.
        // Expressing that pair as HSB is only a conversion: brightness is the dominant channel and
        // saturation is the fraction of it the chroma occupies.
        //
        // Light Mode keeps a fixed brightness because a near-white plate has nowhere to add light
        // to: there the whole tint is chroma taken *out* of white, and 0.08 saturation holds the
        // reference's measured 13–16 chroma at a luminance the label can still be read against.
        //
        // The floor rises with vividness as well, which the reference also shows and a first pass at
        // this missed. Holding it flat at 0.085 put the whole field too dark and too chromatic at
        // once — luminance 23.6 at the median against the reference's 38.6, with chroma 25 against
        // its 15 — because chroma was the only thing vividness bought. In the reference the minimum
        // channel climbs too, from 17 on the greyscale wedges to 34 on the tinted ones and 62 on the
        // most vivid, so a saturated card is a *brighter* card there, not just a purer one.
        if scheme == .dark {
            let strength = min(1, max(0.30, tint.vividness))
            let floor = 0.075 + 0.045 * strength
            let lift = 0.105 * strength
            return Color(
                hue: tint.hue,
                saturation: lift / (floor + lift),
                brightness: floor + lift,
                opacity: 1
            )
        }
        return Color(
            hue: tint.hue,
            saturation: 0.08 * min(1, max(0.45, tint.vividness)),
            brightness: 1.0,
            opacity: 1
        )
    }

    /// How heavily `glassTint` is washed over the frosted substrate, `0...1`.
    ///
    /// High, in both schemes, and that is the correction rather than a preference.
    ///
    /// A wedge draws no opaque plate — unlike the strip, grid and list, whose fills the palette
    /// deliberately made fully opaque for exactly this reason — so whatever the frosted substrate
    /// transmits *is* the card. At 0.24 in Light Mode the wallpaper was supplying three quarters of
    /// it: the same window measured luminance 205 over a bright desktop and 68 over a dark one, so
    /// the card's identity, its lightness, and the contrast of its own label all belonged to the
    /// user's choice of wallpaper. In Dark Mode the tint's chroma was being diluted from 0.34 to
    /// 0.20, which is the visible half of the complaint: the glass looked far less tinted in
    /// practice than in the references.
    ///
    /// 0.95 leaves 5% transmission, which is enough for the desktop to modulate the surface and for
    /// the macOS 26 material to keep its edge behaviour, and little enough that the card is the same
    /// card over any wallpaper. The references are not translucent either: what makes their wedges
    /// read as glass is the rim light on both arcs and the thickness gradient between them, not what
    /// shows through.
    ///
    /// Raised from 0.92 for a reason that only appeared once `glassTint` got darker. 8% of the
    /// wallpaper is 8% either way, but it stopped being a modulation and started being the card: a
    /// dark tinted body is about 22 luminance, so a bright desktop was adding 19 to it and very
    /// nearly doubling it, where the same 8% over the old 46-luminance body moved it by a third.
    /// Measured across a black and a photographic desktop the dark card's spread was 10.5
    /// luminance at 0.92 and 6 at 0.95, and the light card gained the 7 it was short of the
    /// reference over a dark desktop.
    func glassWashOpacity(selected: Bool, scheme: ColorScheme) -> Double {
        switch (scheme, selected) {
        case (.dark, true): return 0.95
        case (.dark, false): return 0.95
        case (_, true): return 0.95
        case (_, false): return 0.95
        }
    }

    /// The hub's ambience: every glow the middle throws, hued by the window under the pointer.
    ///
    /// Matched to the ring's *perceived* luminance, not to its HSB brightness. Those are not the
    /// same thing, and the difference is not subtle: holding saturation and brightness fixed while
    /// only the hue moved put yellow at a relative luminance of 0.742 and purple at 0.325 — a
    /// 2.3x spread — so the hub's brightness depended on which application happened to be under
    /// the pointer, and a yellow-iconed one turned the rim back into the glaring torus that
    /// `HubChrome.ringGlowThickness` exists to prevent.
    ///
    /// So brightness is solved for per hue instead. Yellows and cyans are dimmed to the reference;
    /// blues and purples, which cannot reach it at any brightness, are allowed to give up a bounded
    /// share of their saturation for it. Alpha never moves.
    ///
    /// Returns `hubRing` unchanged when there is no hue to take. Callers pass a tint from
    /// `OverlayState.tint(for:)`, which already yields `nil` under Increase Contrast and when the
    /// user has turned icon tinting off, so both settings reach the hub without another check.
    func hubAmbience(for tint: IconTint?) -> Color {
        guard let tint, let base = NSColor(hubRing).usingColorSpace(.sRGB) else { return hubRing }
        return Self.rehued(
            base,
            to: tint.hue,
            // A washed-out icon gets a correspondingly quieter ambience, floored so a pastel still
            // reads as its own colour rather than collapsing back to the brand.
            saturation: hubAmbienceSaturation * min(1, max(0.6, tint.vividness)),
            saturationFloor: hubAmbienceSaturationFloor,
            luminanceScale: hubAmbienceLuminanceScale
        )
    }

    /// Move `base` onto `hue` while holding its *perceived* luminance.
    ///
    /// Shared by the hub's ambience and the selected wedge's glass, which are the two places a
    /// palette colour is re-hued to the window under the pointer. They need the same solve for the
    /// same reason, and it is not a solve worth having two copies of: it is eighteen rounds of
    /// bisection against a non-linear luminance curve, and a second copy would drift.
    ///
    /// Brightness is spent first. Where a hue cannot reach the reference at any brightness — cool
    /// hues, mostly — a bounded share of saturation goes instead, because the alternative is a
    /// colour that arrives as pale grey for every blue application and identifies nothing.
    ///
    /// - Parameters:
    ///   - saturation: what this hue asks for. A floor of 0 paired with a saturation of 1 turns the
    ///     solve around: instead of holding a chosen saturation and moving brightness, it finds the
    ///     most saturated colour that still lands on the target luminance. That is what a near-white
    ///     reference needs, where any chosen saturation is either unreachable or invisible.
    ///   - saturationFloor: the fraction of `saturation` it may be reduced to in order to reach the
    ///     reference luminance.
    ///   - luminanceScale: fraction of `base`'s luminance to aim for. Below 1 buys chroma, because
    ///     the two trade against each other as the reference approaches white.
    static func rehued(
        _ base: NSColor,
        to hue: Double,
        saturation: Double,
        saturationFloor: Double,
        luminanceScale: Double = 1
    ) -> Color {
        var baseHue: CGFloat = 0
        var baseSaturation: CGFloat = 0
        var baseBrightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&baseHue, saturation: &baseSaturation, brightness: &baseBrightness, alpha: &alpha)

        let reference = relativeLuminance(
            red: Double(base.redComponent),
            green: Double(base.greenComponent),
            blue: Double(base.blueComponent)
        ) * luminanceScale
        let wanted = saturation

        func luminance(saturation: Double, brightness: Double) -> Double {
            let (red, green, blue) = components(
                hue: hue,
                saturation: saturation,
                brightness: brightness
            )
            return relativeLuminance(red: red, green: green, blue: blue)
        }

        var resolvedSaturation = wanted
        var resolvedBrightness = Double(baseBrightness)

        if luminance(saturation: wanted, brightness: resolvedBrightness) > reference {
            // Monotonic in brightness at a fixed hue, so bisect down onto the reference.
            var low = 0.0
            var high = resolvedBrightness
            for _ in 0..<18 {
                let mid = (low + high) / 2
                if luminance(saturation: wanted, brightness: mid) > reference {
                    high = mid
                } else {
                    low = mid
                }
            }
            resolvedBrightness = (low + high) / 2
        } else if luminance(saturation: wanted, brightness: 1) < reference {
            // Even at full brightness this hue is darker than the reference. Desaturating raises
            // luminance, so spend saturation — down to the floor and no further.
            resolvedBrightness = 1
            var low = wanted * saturationFloor
            var high = wanted
            for _ in 0..<18 {
                let mid = (low + high) / 2
                if luminance(saturation: mid, brightness: 1) < reference {
                    high = mid
                } else {
                    low = mid
                }
            }
            resolvedSaturation = (low + high) / 2
        } else {
            var low = Double(baseBrightness)
            var high = 1.0
            for _ in 0..<18 {
                let mid = (low + high) / 2
                if luminance(saturation: wanted, brightness: mid) > reference {
                    high = mid
                } else {
                    low = mid
                }
            }
            resolvedBrightness = (low + high) / 2
        }

        let (red, green, blue) = components(
            hue: hue,
            saturation: resolvedSaturation,
            brightness: resolvedBrightness
        )
        // Built from the components that were actually solved for rather than handed back to
        // SwiftUI as HSB, so the luminance drawn is the luminance measured.
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: Double(alpha))
    }

    /// How much of its saturation a hue may give up to reach the reference luminance.
    static let ambienceSaturationFloor: Double = 0.55

    /// WCAG relative luminance, the curve `OverlayPaletteTests` measures every ratio with.
    static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// HSB to sRGB components, so the solve above does not pay for a colour-space round trip on
    /// every one of its iterations.
    static func components(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let wrapped = (hue - floor(hue)) * 6
        let sector = Int(wrapped) % 6
        let fraction = wrapped - floor(wrapped)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch sector {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    /// Inner-arc catch light. In the mock this is the glass cue: Chrome's inner edge is
    /// green, Slack's is pink, the selected one is lit by the hub.
    ///
    /// The selected case follows the ambience rather than the resting brand colour. The coupling
    /// tongue lands on exactly this arc, so a brand-cyan rim under a red tongue would show the
    /// join as a seam between two different lights.
    ///
    /// Pale, which is the whole difference between light caught on an edge and a line drawn along
    /// one. Sampled at its peak the reference's inner arc is (146,121,178) on its purple card —
    /// luminance 130 at 0.32 saturation, a washed lavender whose darkest channel is still 121. At
    /// 0.82 this overlay produced (72,191,157) and (63,124,187): 0.62–0.66 saturation with a
    /// darkest channel around 65, which is a vivid stroke rather than a highlight, and reads as an
    /// outline at any blur radius. Hue is untouched — a Chrome edge is still green, a Slack edge
    /// still pink, which is what the arc is for.
    func glassRim(for tint: IconTint?, selected: Bool, scheme: ColorScheme) -> Color {
        if selected { return hubAmbience(for: tint) }
        guard let tint else {
            return Color.white.opacity(scheme == .light ? 0.40 : 0.20)
        }
        return Color(
            hue: tint.hue,
            saturation: scheme == .dark ? 0.38 : 0.26,
            brightness: scheme == .dark ? 0.95 : 1.0,
            opacity: 1
        )
    }

    /// How strongly a radial wedge's own shadow lifts it off the desktop, `0...1`.
    ///
    /// Light needs more: a white tile on a white desktop has no edge without it. This is the
    /// shadow of the *wedge*, not of the hub. The well draws in front of the inward bleed, so
    /// the extra Light Mode weight cannot darken the caption — which is why this lives on the
    /// palette, where the contrast argument lives, rather than as a one-off in the view.
    let wedgeShadowOpacity: Double

    static func forScheme(_ scheme: ColorScheme) -> OverlayPalette {
        scheme == .dark ? .dark : .light
    }

    /// `--ps-*` dark theme.
    static let dark = OverlayPalette(
        cardFill: Color(.sRGB, red: 38 / 255, green: 44 / 255, blue: 51 / 255, opacity: 1),
        selectedCardFill: Color(.sRGB, red: 46 / 255, green: 54 / 255, blue: 63 / 255, opacity: 1),
        thumbnailFill: Color(.sRGB, red: 25 / 255, green: 29 / 255, blue: 34 / 255, opacity: 1),
        border: Color(.sRGB, white: 1, opacity: 0.10),
        strongBorder: Color(.sRGB, white: 1, opacity: 0.20),
        text: Color(.sRGB, white: 1, opacity: 1),
        secondaryText: Color(.sRGB, white: 1, opacity: 0.58),
        hubSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        chipFill: Color(.sRGB, red: 18 / 255, green: 22 / 255, blue: 26 / 255, opacity: 1),
        accent: Self.brand,
        accentFill: Self.brandFill,
        onAccentText: .white,
        onAccentSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        liveIndicator: Color(.sRGB, red: 98 / 255, green: 197 / 255, blue: 238 / 255, opacity: 1),
        // 6.5:1 against the dark card fill.
        microphoneIndicator: Color(.sRGB, red: 255 / 255, green: 159 / 255, blue: 10 / 255, opacity: 1),
        // Fully saturated but dark, which matters more here than it looks. Mixing a *bright* hue
        // into a near-black card raises its luminance, and the secondary line is white at 58% —
        // measured against yellows it fell to 4.4:1, just under the bar. Keeping the hue dark lets
        // the tint colour the card without lightening it, so contrast stays where it was.
        tintStrength: 0.26,
        tintSaturation: 1.0,
        tintBrightness: 0.26,
        // Black rather than the selected-card tint: the well is a hole, not another card, and its
        // job is to carry type, not to identify the window. The ring does that.
        //
        // Was (12,14,16). Profiled in annuli, the dark reference's interior is luminance 0 at every
        // percentile from 0.05 to 0.45 of the ring radius — not dark, *black* — and its climb to the
        // rim starts only past 0.6. Both this and `HubChrome.backdropIconOpacityDark` were holding
        // the middle above it; this is the smaller of the two contributions but it is the floor
        // everything else is measured from, so it goes first.
        hubWellFill: Color(.sRGB, red: 4 / 255, green: 5 / 255, blue: 6 / 255, opacity: 1),
        // The dark reference's rim, sampled at its peak: (179,223,213), hue 0.462, saturation 0.197.
        //
        // Taken as the *composited* target rather than as a starting colour, which is what makes it
        // the right value. The rim's layers sum to roughly one unit of opacity at the centreline, so
        // an additive stack of this colour lands on this colour. Anything more saturated cannot get
        // there: the previous 0.49 measured 0.51 on screen — the same hue reading as neon rather
        // than as light — and pushing brightness at it instead just clipped green to 255 and drained
        // the hue out of the brightest pixel in the overlay. There is no setting where an additive
        // rim is both brighter than its own source and still coloured.
        //
        // This is also the ceiling on `hubAmbience`, which takes saturation from here and only moves
        // hue, so calming the brand calms every window's ambience with it.
        // Brighter than the reference's measured (179,223,213), and for a mechanical reason rather
        // than a stylistic one: the rim composites normally now, so this value is a ceiling rather
        // than a contribution, and the blur spends part of it spreading the stroke's edges.
        //
        // How much was measured rather than estimated. Rendering with icon tinting off, so the ring
        // paints this colour and nothing substitutes its hue, the drawn peak came out at luminance
        // 200 from a source of 224 — the missing 11% is the blur, and the earlier "about 10%, so
        // start 5% above" halved the correction it had already worked out.
        //
        // The 8% overshoot that answer produced was given back once `HubChrome.ringGlowBlur` came
        // down to 0.7pt and stopped throwing the stroke's value into its shoulders — and then 8.5%
        // of it had to be put back, because the statistic it was being fitted to was the wrong one.
        //
        // Averaging every bearing's luminance at each radius, as the earlier passes did, dilutes a
        // line that wanders even one pixel: the two get averaged with their neighbours and the
        // reported peak lands below both. Measured that way the reference's rim reads 209.6, and the
        // rim was tuned to match it. Measured per bearing — each bearing's own brightest pixel,
        // which is what an eye follows around the circle — the reference reads 232.3 and ours read
        // 214.0. The rim was 8% dim against a target that was itself 10% low.
        //
        // So this is the reference's per-bearing rim divided by what a stroke at 0.97 opacity keeps
        // of its source. `HubHalo.crest` came down by the same factor at the same time, so the glow
        // stayed where it had already been measured to belong and only the line got brighter — which
        // is the difference between a brighter rim and a bigger smudge.
        hubRing: Color(.sRGB, red: 208 / 255, green: 254 / 255, blue: 244 / 255, opacity: 1),
        // The resting ring's own saturation, (254-208)/254, so Dark Mode is left exactly as it was:
        // it already reads as coloured, and the reported defect was Light Mode's alone.
        hubAmbienceSaturation: 0.1811,
        hubAmbienceSaturationFloor: Self.ambienceSaturationFloor,
        hubAmbienceLuminanceScale: 1.0,
        radialSelectedStrengthScale: 1.55,
        wedgeShadowOpacity: 0.34
    )

    /// `--ps-*` light theme.
    static let light = OverlayPalette(
        cardFill: Color(.sRGB, white: 1, opacity: 1),
        selectedCardFill: Color(.sRGB, white: 1, opacity: 1),
        thumbnailFill: Color(.sRGB, red: 231 / 255, green: 229 / 255, blue: 227 / 255, opacity: 1),
        border: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.16),
        strongBorder: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.30),
        text: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 1),
        // The design's 0.55 measures 3.7:1 on a white card, which is short of 4.5:1 for
        // 10pt type. Weighted up until the secondary line actually clears it — and weighted up
        // again to buy the headroom `hubWellFill` needs to stop being white. See there.
        secondaryText: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.76),
        hubSecondaryText: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.9),
        chipFill: Color(.sRGB, red: 252 / 255, green: 251 / 255, blue: 250 / 255, opacity: 1),
        accent: Self.brand,
        accentFill: Self.brandFill,
        onAccentText: .white,
        onAccentSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        liveIndicator: Color(.sRGB, red: 0 / 255, green: 106 / 255, blue: 141 / 255, opacity: 1),
        // Burnt rather than bright: the system's own orange measures 2.2:1 on a white card, so it
        // is darkened until it clears 3:1 with room to spare. 5.1:1 as written.
        microphoneIndicator: Color(.sRGB, red: 176 / 255, green: 84 / 255, blue: 0 / 255, opacity: 1),
        // A light card is white, so every point of tint costs luminance the secondary line is
        // measured against. This is the value the hue sweep in `OverlayPaletteTests` clears with
        // room to spare, and it is still enough to tell a ring of Chrome windows apart.
        tintStrength: 0.15,
        tintSaturation: 0.85,
        tintBrightness: 1.0,
        // A shallow recess, not a white disc. The light reference's hub interior measures luminance
        // 224–230 against cards at 235 and a rim crest at 250, so the middle is very slightly
        // *darker* than everything around it — the same "hole with a lit rim" the dark theme draws,
        // translated. At 252 there was nothing for the rim to be brighter than: the ring measured a
        // +3 lift where the reference gets +20, and no amount of ring opacity could fix it, because
        // in Light Mode the rim composites normally and 255 is the ceiling.
        //
        // This is what `secondaryText` was weighted up for. On this fill the 9pt line measures
        // 6.6:1, and 6.0:1 under the worst case the watermark can produce — a uniformly black icon.
        // `HubTintTests` measures both from the render.
        hubWellFill: Color(.sRGB, red: 231 / 255, green: 229 / 255, blue: 227 / 255, opacity: 1),
        // Near-white cyan, because in Light Mode the rim has to be *brighter* than what it sits on
        // and it composites normally rather than additively — so its own luminance is a hard ceiling
        // on the rim, however much opacity is thrown at it.
        //
        // Measured: the light reference's rim crests at (243,252,253), luminance 250, against an
        // interior of 229. At (70,190,230) — 0.70 saturation, luminance 190 — this overlay drew a
        // *darker* band than everything around it, a green-cyan stroke painted on white. At (214,
        // 250,255) the ceiling was 243, so the rim could not clear its own surroundings by more
        // than a few levels whatever else was tuned.
        //
        // This is a deliberate compromise rather than the reference exactly, and where the
        // compromise falls is now measured rather than reasoned about. Rendered, this stroke loses
        // about 8% of its source to the blur mixing with the well beside it: at (238,252,255),
        // luminance 248, the drawn rim came out at 228 against an interior of 221 — a +7 lift where
        // the reference gets +23. Raising the source to luminance 253 recovers most of the
        // difference and costs 5 points of the hue's already-slim chroma.
        //
        // That gap has since closed, from the other end. It was never really the source's ceiling —
        // it was that the glow around the rim had no shoulder, so the rim was a stroke sitting on
        // bare canvas with nothing lifting it. With `HubRingHalo` and the well's inward bloom now
        // cresting on the centreline instead of beside it, the rendered rim measures 252.4 against
        // the reference's 252.9, and the per-bearing spread is 1.00 against its 0.99.
        //
        // Red went up 4 points, and then to white, for a reason worth keeping: green and blue were
        // already clipping at 255 on screen while red arrived at 244, so the brightest pixel of the
        // overlay measured *more* saturated than the reference's (0.043 against 0.023) purely
        // because the two channels that had run out of room could not keep up with the one that had.
        // Raising the channel that was not clipping is the only direction that helps.
        //
        // And this is where that ends, one step short of white. Pure white was tried and reverted:
        // it gains 1.4 luminance on the rendered rim and costs the feature the hub is built around.
        // `hubAmbience` works by substituting the hovered window's hue into this colour, and a
        // colour with no saturation has no hue to substitute — `OverlayPaletteTests` and
        // `HubTintTests` both caught the ambience going flat across the whole wheel.
        //
        // The rim is at the ceiling either way. Its per-bearing peak renders 252.7 against the light
        // reference's 254.1, and that reference's rim is the only thing in its image which has
        // clipped — the card field's own ninth decile is 243.9. So in Light Mode "make the rim
        // brighter than the cards" is finished here, and anything further has to come from the
        // surround rather than from the rim. See the note on `wellScrimOpacityLight` in `HubChrome`.
        hubRing: Color(.sRGB, red: 250 / 255, green: 255 / 255, blue: 255 / 255, opacity: 1),
        // A held saturation at full brightness, which is what a floor of 1 and an unreachable
        // reference come to: no hue can match a near-white ring at this saturation, so every one of
        // them settles at full brightness with its saturation intact.
        //
        // Holding *saturation* rather than luminance here, which is the opposite of Dark Mode, and
        // measured rather than assumed. Solving for maximum chroma at a fixed luminance — the
        // obvious reading of "make it more colourful" — produced a wildly uneven ring: green came out
        // at chroma 71 where red managed 21, because green carries 0.7152 of the luminance weight and
        // so can be far more saturated at the same lightness. Held saturation gives every window the
        // same amount of colour and lets lightness vary instead, which on a light hub is the better
        // trade: a paler rim is merely paler, where in Dark Mode a brighter one is glare.
        hubAmbienceSaturation: 0.13,
        hubAmbienceSaturationFloor: 1.0,
        hubAmbienceLuminanceScale: 1.0,
        // Kept close to 1: every extra point of tint on a white card costs the secondary line,
        // and 1.85 failed 4.5:1 on blues. 1.3 is still visibly stronger than rest.
        radialSelectedStrengthScale: 1.3,
        wedgeShadowOpacity: 0.38
    )

    /// Hue of `hubRing` / the selected glass, as a fraction of the wheel.
    ///
    /// Shared so the selected wedge, the halo and the coupling stay one cyan rather
    /// than three neighbouring ones.
    private static let brandHue: Double = 0.532

    /// PeekSwitch's selection colour, `#0088b0`.
    private static let brand = Color(
        .sRGB,
        red: 0 / 255,
        green: 136 / 255,
        blue: 176 / 255,
        opacity: 1
    )

    /// The same hue, dark enough to carry white text at 4.5:1, `#00789b`.
    private static let brandFill = Color(
        .sRGB,
        red: 0 / 255,
        green: 120 / 255,
        blue: 155 / 255,
        opacity: 1
    )
}

private struct OverlayPaletteKey: EnvironmentKey {
    static let defaultValue = OverlayPalette.dark
}

extension EnvironmentValues {
    /// Resolved once near the root of the overlay, so every card, row and caption reads
    /// the same theme rather than each deciding for itself.
    var overlayPalette: OverlayPalette {
        get { self[OverlayPaletteKey.self] }
        set { self[OverlayPaletteKey.self] = newValue }
    }
}
