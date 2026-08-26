import AppKit
import SwiftUI
import Testing
@testable import PeekSwitchCore

/// Requirement 3.11: overlay text clears 4.5:1 against what it is drawn on.
///
/// This suite exists because of a real regression. The cards used to be a 5% tint of
/// `.primary` over the panel's plate; once the plate went away the tint became a tint
/// of the user's wallpaper, and in the wrong combination the application names went
/// invisible. Contrast was never actually pinned down — it was inherited from the
/// backdrop and happened to work.
///
/// Card fills are translucent, so the composite depends on what is behind the overlay.
/// Every ratio here is therefore checked against both black and white backgrounds,
/// which bracket every possible desktop.
@Suite("Overlay palette")
struct OverlayPaletteTests {

    private struct RGBA {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    private static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
    private static let white = RGBA(red: 1, green: 1, blue: 1, alpha: 1)

    /// WCAG normal-text minimum. The overlay's smallest type is 10pt, which is normal
    /// text by any reading, so the large-text allowance does not apply.
    private static let minimumRatio: Double = 4.5

    private func components(_ color: Color) -> RGBA {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            Issue.record("could not resolve \(color) into sRGB")
            return RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return RGBA(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
    }

    /// Standard source-over composite.
    private func composite(_ foreground: RGBA, over background: RGBA) -> RGBA {
        let alpha = foreground.alpha
        return RGBA(
            red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha),
            alpha: 1
        )
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: RGBA) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red)
            + 0.7152 * channel(color.green)
            + 0.0722 * channel(color.blue)
    }

    private func ratio(_ first: RGBA, _ second: RGBA) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Contrast of `text` drawn on `fill`, where `fill` itself sits on `desktop`.
    private func ratio(text: Color, on fill: Color, over desktop: RGBA) -> Double {
        let surface = composite(components(fill), over: desktop)
        let inked = composite(components(text), over: surface)
        return ratio(inked, surface)
    }

    private var palettes: [(name: String, palette: OverlayPalette)] {
        [("dark", .dark), ("light", .light)]
    }

    // MARK: - Card text

    /// The exact case the user reported: application names on a card.
    @Test("Primary text is legible on a card over any desktop")
    func primaryTextOnCard() {
        for (name, palette) in palettes {
            for (desktop, label) in [(Self.black, "black"), (Self.white, "white")] {
                for (fill, fillName) in [
                    (palette.cardFill, "cardFill"),
                    (palette.selectedCardFill, "selectedCardFill"),
                ] {
                    let value = ratio(text: palette.text, on: fill, over: desktop)
                    #expect(
                        value >= Self.minimumRatio,
                        "\(name) \(fillName) over \(label): \(value) < \(Self.minimumRatio)"
                    )
                }
            }
        }
    }

    @Test("Secondary text is legible on a card over any desktop")
    func secondaryTextOnCard() {
        for (name, palette) in palettes {
            for (desktop, label) in [(Self.black, "black"), (Self.white, "white")] {
                let value = ratio(text: palette.secondaryText, on: palette.cardFill, over: desktop)
                #expect(
                    value >= Self.minimumRatio,
                    "\(name) secondary over \(label): \(value) < \(Self.minimumRatio)"
                )
            }
        }
    }

    /// The thumbnail well shows through wherever a capture has not arrived, and the
    /// placeholder glyph is drawn on it.
    @Test("Placeholder text is legible in the thumbnail well")
    func secondaryTextOnThumbnailWell() {
        for (name, palette) in palettes {
            let value = ratio(text: palette.secondaryText, on: palette.thumbnailFill, over: Self.black)
            #expect(value >= 3.0, "\(name) placeholder glyph: \(value) < 3.0")
        }
    }

    // MARK: - Chrome

    @Test("Hub well text is legible over any desktop")
    func hubWellTextIsLegible() {
        for (name, palette) in palettes {
            for (desktop, label) in [(Self.black, "black"), (Self.white, "white")] {
                let primary = ratio(text: palette.text, on: palette.hubWellFill, over: desktop)
                #expect(
                    primary >= Self.minimumRatio,
                    "\(name) hub well primary over \(label): \(primary)"
                )
                let secondary = ratio(
                    text: palette.secondaryText,
                    on: palette.hubWellFill,
                    over: desktop
                )
                #expect(
                    secondary >= Self.minimumRatio,
                    "\(name) hub well secondary over \(label): \(secondary)"
                )
            }
        }
    }

    /// The well is a hole, not another card: it must not pick up the selected window's hue,
    /// or the caption's surface would shift every time the pointer moved.
    @Test("Glass tint follows the icon hue and stays chromatic")
    func glassTintIsChromatic() {
        let red = components(OverlayPalette.dark.glassTint(
            for: IconTint(hue: 0, vividness: 1),
            selected: false,
            scheme: .dark
        ))
        let green = components(OverlayPalette.dark.glassTint(
            for: IconTint(hue: 1.0 / 3, vividness: 1),
            selected: false,
            scheme: .dark
        ))
        #expect(red.red > green.red)
        #expect(green.green > red.green)

        // Relative chroma, not the raw channel spread. The two only agree at a fixed brightness,
        // and this tint's brightness is set by how dark the reference's card bodies measure —
        // raising it to match them widens the spread without the colour becoming any purer, so a
        // spread threshold would pass or fail on the wrong quantity.
        func chroma(_ colour: RGBA) -> Double {
            let high = max(colour.red, colour.green, colour.blue)
            let low = min(colour.red, colour.green, colour.blue)
            return high == 0 ? 0 : (high - low) / high
        }

        #expect(
            chroma(red) > 0.30,
            "dark glass tint is too grey to match the mock: chroma \(chroma(red))"
        )

        // A pastel, not a saturated colour worn thin. Light Mode composites this at near-full
        // opacity, so its chroma *is* the card's chroma — and the reference's light card bodies
        // measure 0.053. A tint of 0.24 was correct only while the wash was 0.24 and the wallpaper
        // supplied the rest; drawn at full strength it would be four times the reference.
        let lightRed = components(OverlayPalette.light.glassTint(
            for: IconTint(hue: 0, vividness: 1),
            selected: false,
            scheme: .light
        ))
        #expect(
            chroma(lightRed) > 0.04,
            "light glass tint has no hue left: chroma \(chroma(lightRed))"
        )
        #expect(
            chroma(lightRed) < 0.16,
            "light glass tint is no longer a pastel: chroma \(chroma(lightRed))"
        )
    }

    /// A dark wedge is a dark floor with the icon's light added on top, not a fixed grey stained to
    /// order — and the difference is measurable in two directions at once.
    ///
    /// The references' dark cards share a floor: the minimum channel is 17–34 on every wedge,
    /// greyscale and vivid alike, while the dominant channels climb from 0 chroma on ChatGPT and
    /// Cursor to 32 on Brave. That makes a vivid card a *brighter* card there. Built the other way —
    /// one brightness for all, saturation carrying vividness — a vivid card is a darker one, and the
    /// whole ring collapses into the same narrow band: rendered, the field measured chroma 0 at its
    /// 25th percentile and 24 at its 90th against the references' 6 and 52, which is the "the glass
    /// looks less tinted than the mock" complaint expressed as numbers.
    @Test("A dark wedge adds the icon's light to a common floor")
    func darkGlassTintAddsToAFloor() {
        let plate = components(OverlayPalette.dark.glassTint(for: nil, selected: false, scheme: .dark))

        // The untinted plate is one of the reference's dark bodies, not a mid grey. At 0.18 the
        // greyscale-iconed wedges were the *brightest* on a dark ring instead of the darkest.
        #expect(
            plate.red < 0.13,
            "dark untinted glass is a mid grey rather than a dark plate: \(plate.red)"
        )

        var previousPeak = 0.0
        var previousFloor = -1.0
        for vividness in [0.3, 0.5, 0.7, 1.0] {
            let colour = components(OverlayPalette.dark.glassTint(
                for: IconTint(hue: 1.0 / 3, vividness: vividness),
                selected: false,
                scheme: .dark
            ))
            let peak = max(colour.red, colour.green, colour.blue)
            let floor = min(colour.red, colour.green, colour.blue)

            // More vivid is brighter, not just purer.
            #expect(
                peak > previousPeak,
                "vividness \(vividness) is no brighter than the step below it: \(peak)"
            )
            // And it climbs from the same floor the greyscale wedges sit on, within the drift the
            // reference itself shows.
            #expect(
                abs(floor - plate.red) < 0.05,
                "vividness \(vividness) floor \(floor) has left the untinted plate at \(plate.red)"
            )
            #expect(floor >= previousFloor, "the floor fell as vividness rose: \(floor)")
            previousPeak = peak
            previousFloor = floor
        }
    }

    /// The wash is the card, not a hint added to whatever is behind it.
    ///
    /// A wedge draws no opaque plate, so whatever the frosted substrate transmits is the card. At
    /// the previous values — 0.76 in Dark Mode and 0.24 in Light — the wallpaper was supplying most
    /// of it: the same window measured luminance 205 over a bright desktop and 68 over a dark one,
    /// which made the card's identity, its lightness *and* the contrast of its own label properties
    /// of the user's wallpaper rather than of the window. `OverlayRenderingTests` measures that from
    /// the render; this pins the constant that decides it.
    @Test("The glass wash owns the card rather than hinting at it")
    func glassWashOwnsTheCard() {
        for (name, palette) in palettes {
            let scheme: ColorScheme = name == "dark" ? .dark : .light
            for selected in [true, false] {
                let wash = palette.glassWashOpacity(selected: selected, scheme: scheme)
                #expect(
                    wash >= 0.85,
                    "\(name) \(selected ? "selected" : "rest") wash \(wash) leaves the card to the desktop"
                )
                // Not entirely opaque: the remainder is what lets the desktop modulate the surface
                // and what the macOS 26 material needs to behave like a material at its edges.
                #expect(wash < 1, "\(name) \(selected ? "selected" : "rest") wash admits no light at all")
            }
        }

        // Selection is carried by the tint's own colour rather than by how hard it is washed on,
        // which is what lets both be near-opaque without the two becoming indistinguishable.
        for (name, palette) in palettes {
            let scheme: ColorScheme = name == "dark" ? .dark : .light
            let tint = IconTint(hue: 1.0 / 3, vividness: 1)
            let rest = components(palette.glassTint(for: tint, selected: false, scheme: scheme))
            let chosen = components(palette.glassTint(for: tint, selected: true, scheme: scheme))
            let distance = abs(rest.red - chosen.red)
                + abs(rest.green - chosen.green)
                + abs(rest.blue - chosen.blue)
            #expect(distance > 0.10, "\(name) selected glass is not distinguishable: \(distance)")
        }
    }

    @Test("Glass rim colour follows the icon, and selection follows the hub's ambience")
    func glassRimTracksTheIcon() {
        let red = components(OverlayPalette.dark.glassRim(
            for: IconTint(hue: 0, vividness: 1),
            selected: false,
            scheme: .dark
        ))
        let green = components(OverlayPalette.dark.glassRim(
            for: IconTint(hue: 1.0 / 3, vividness: 1),
            selected: false,
            scheme: .dark
        ))
        #expect(red.red > green.red)
        #expect(green.green > red.green)

        // The coupling tongue lands on this arc, so the two have to be one light. With no hue to
        // take it falls back to the resting ring colour; with one it follows the ambience.
        let tint = IconTint(hue: 0, vividness: 1)
        let selected = OverlayPalette.dark.glassRim(for: tint, selected: true, scheme: .dark)
        #expect(selected == OverlayPalette.dark.hubAmbience(for: tint))
        #expect(
            OverlayPalette.dark.glassRim(for: nil, selected: true, scheme: .dark)
                == OverlayPalette.dark.hubRing
        )
    }

    @Test("Radial wedge shadows live on the palette")
    func wedgeShadowOpacityIsAPaletteValue() {
        #expect(OverlayPalette.dark.wedgeShadowOpacity > 0)
        #expect(OverlayPalette.light.wedgeShadowOpacity > OverlayPalette.dark.wedgeShadowOpacity)
        #expect(OverlayPalette.light.wedgeShadowOpacity <= 0.5)
        #expect(OverlayPalette.dark.wedgeShadowOpacity <= OverlayPalette.light.wedgeShadowOpacity)
    }

    /// The ambience lights four compositing layers at once, so what has to stay put across hues is
    /// its *perceived* luminance — not its HSB brightness, which is a different quantity.
    ///
    /// This is the regression the test exists for. Holding saturation and brightness fixed and
    /// letting only the hue move looks correct and measures wrong: yellow arrived at a relative
    /// luminance of 0.742 against purple's 0.325, a 2.3x spread, so the hub's brightness depended
    /// on which application was under the pointer and a yellow-iconed one turned the rim into a
    /// glaring torus. Brightness is now solved per hue, so it is brightness that moves and
    /// luminance that holds.
    @Test("The hub ambience holds its luminance across the colour wheel")
    func hubAmbienceHoldsItsLuminance() {
        for (name, palette) in palettes {
            #expect(palette.hubAmbience(for: nil) == palette.hubRing, "\(name) lost its fallback")

            let ring = components(palette.hubRing)
            let reference = OverlayPalette.relativeLuminance(
                red: ring.red,
                green: ring.green,
                blue: ring.blue
            )

            var luminances: [Double] = []
            for step in 0..<12 {
                let hue = Double(step) / 12
                let ambience = palette.hubAmbience(for: IconTint(hue: hue, vividness: 1))
                let resolved = components(ambience)
                let luminance = OverlayPalette.relativeLuminance(
                    red: resolved.red,
                    green: resolved.green,
                    blue: resolved.blue
                )
                luminances.append(luminance)

                // Never brighter than the brand it stands in for. This is the half that was
                // producing the glare.
                #expect(
                    luminance <= reference + 0.01,
                    "\(name) hue \(hue) is brighter than the ring: \(luminance) vs \(reference)"
                )
                #expect(resolved.alpha == ring.alpha, "\(name) alpha moved at hue \(hue)")

                // The hue itself still arrives intact — the solve spends brightness and
                // saturation, never hue.
                var resolvedHue: CGFloat = 0
                var resolvedSaturation: CGFloat = 0
                var resolvedBrightness: CGFloat = 0
                var resolvedAlpha: CGFloat = 0
                NSColor(ambience).usingColorSpace(.sRGB)?.getHue(
                    &resolvedHue,
                    saturation: &resolvedSaturation,
                    brightness: &resolvedBrightness,
                    alpha: &resolvedAlpha
                )
                let drift = abs(Double(resolvedHue) - hue)
                #expect(min(drift, 1 - drift) < 0.02, "\(name) hue \(hue) became \(resolvedHue)")
            }

            // Cool hues cannot reach the reference at any brightness, so a spread survives — but a
            // bounded one, and far from the 2.3x that shipped.
            let spread = luminances.max()! / luminances.min()!
            #expect(spread <= 1.4, "\(name) ambience luminance spread is \(spread)")
            #expect(
                luminances.min()! >= reference * 0.70,
                "\(name) dimmest ambience is \(luminances.min()!) against \(reference)"
            )

            // And distinct hues stay distinguishable after all that bounding.
            let red = components(palette.hubAmbience(for: IconTint(hue: 0, vividness: 1)))
            let green = components(palette.hubAmbience(for: IconTint(hue: 1.0 / 3, vividness: 1)))
            #expect(red.red > green.red, "\(name) red ambience is not redder")
            #expect(green.green > red.green, "\(name) green ambience is not greener")
        }
    }

    /// The well transmits some of the wallpaper on purpose, so the caption's surface is a *range*
    /// rather than a colour — and this is where that range is pinned.
    ///
    /// It has to be stated here rather than measured from a render, and that is a real limitation
    /// rather than a preference. The blur is `NSVisualEffectView` with `.behindWindow` blending,
    /// composited by the window server behind the layer; inside `cacheDisplay` there is no window and
    /// no desktop, so it resolves to a fallback tint. A render test would measure that fallback and
    /// learn nothing about the wallpaper case, which is the only case that can fail.
    ///
    /// So the arithmetic is done over the extremes instead, and deliberately pessimistically: the
    /// material is assumed to pass the desktop through *untouched*, which no real material does. If
    /// the ratio holds for pure white and pure black behind the glass then it holds for every
    /// wallpaper and every material tint in between.
    ///
    /// The watermark is folded in at the same point because it is in the same place — under the
    /// scrim, over the blur. That stacking is what lets it be drawn at 0.85 instead of 0.05: it is
    /// bounded by the same layer that bounds the wallpaper, so a uniformly white icon in Dark Mode is
    /// not a worse case than a white desktop, it is the same case.
    ///
    /// The binding constraint is the *secondary* line rather than the primary, which is not the
    /// intuition. `secondaryText` is translucent white in Dark Mode, so it composites brighter as its
    /// own surface brightens and gives up contrast about twice as fast as opaque white would.
    /// How much of the rim's inward glow reaches the caption's outermost glyph, in Dark Mode.
    ///
    /// Taken at the tightest hub the layout will produce, where the caption is the largest fraction
    /// of the radius and therefore sits furthest out into the glow. `captionFitsTheFlatScrim` is
    /// what guarantees the caption stops at `wellOpaqueFraction`; this is the same radius expressed
    /// as a distance in from the rim, which is the unit `HubHalo.decay` is written in.
    private static var bloomUnderTheCaption: Double {
        let hubRadius = RadialLayout.minimumHubRadius
        let ringRadius = hubRadius - HubChrome.ringInset
        let captionOuter = hubRadius * HubChrome.wellOpaqueFraction
        let offset = Double((ringRadius - captionOuter) / HubChrome.haloSpread)
        // `HubWell`'s Dark Mode crest.
        return 0.55 * HubHalo.level(atSpreadOffset: offset)
    }

    @Test("Caption text clears 4.5:1 over any wallpaper the well transmits")
    func captionSurvivesAnyWallpaperThroughTheWell() {
        for (name, palette, scheme) in [
            ("dark", OverlayPalette.dark, ColorScheme.dark),
            ("light", OverlayPalette.light, .light),
        ] {
            let scrim = scheme == .dark
                ? HubChrome.wellScrimOpacityDark
                : HubChrome.wellScrimOpacityLight
            let iconOpacity = scheme == .dark
                ? HubChrome.backdropIconOpacityDark
                : HubChrome.backdropIconOpacityLight

            // Both extremes, for the desktop and for the icon over it. Sweeping all four states the
            // property rather than the answer.
            for (desktopName, desktop) in [("white", Self.white), ("black", Self.black)] {
                for (iconName, iconColour) in [("white", Self.white), ("black", Self.black)] {
                    var icon = iconColour
                    icon.alpha = iconOpacity
                    let throughTheBlur = composite(icon, over: desktop)

                    var tint = components(palette.hubWellFill)
                    tint.alpha = scrim
                    let scrimmed = composite(tint, over: throughTheBlur)

                    // And then the rim's inward glow, which lands *on top of* the scrim and so is
                    // the one thing here the scrim does not bound.
                    //
                    // It was previously left out because the bloom crested 8pt inside the rim and
                    // faded to nothing well before the type. It still fades before the type, but it
                    // is no longer safe to leave unstated: the bloom now crests on the centreline
                    // and traces `HubHalo.decay` inward, so its value under the caption follows from
                    // the same table that sets how far the glow reaches outward. Anything that
                    // widens that reach walks light toward the caption, and this is where that has
                    // to fail.
                    //
                    // Bounded with white rather than with `hubRing`, because the hub's ambience
                    // takes the hue of the window under the pointer and white is the worst any hue
                    // can composite to for translucent white type. In Light Mode the glow moves the
                    // surface *away* from the ink, so the bound there is the glow's absence and
                    // including it would only flatter the result.
                    var glow = Self.white
                    glow.alpha = scheme == .dark ? Self.bloomUnderTheCaption : 0
                    let surface = composite(glow, over: scrimmed)

                    for (label, colour) in [
                        ("primary", palette.text),
                        // The hub's own secondary weight, not the card one. This is the line that
                        // sets the bound, so testing the wrong one would pass while shipping
                        // unreadable type — or fail while nothing was wrong.
                        ("secondary", palette.hubSecondaryText),
                    ] {
                        let value = ratio(composite(components(colour), over: surface), surface)
                        #expect(
                            value >= Self.minimumRatio,
                            """
                            \(name) \(label) is \(value):1 on a well transmitting a \(desktopName) \
                            desktop under a \(iconName) watermark — scrim \(scrim), icon \(iconOpacity)
                            """
                        )
                    }
                }
            }

            // And the scrim is not so heavy that the feature is gone. Past this the well is a plate
            // again with extra steps, which is the thing being fixed.
            #expect(
                scrim <= 0.86,
                "\(name) scrim \(scrim) transmits too little for the well to read as glass"
            )
        }
    }

    @Test("The hub well is not the selected-card tint")
    func hubWellIsNotATintedCard() {
        for (name, palette) in palettes {
            let red = palette.selectedCardFill(tintedBy: IconTint(hue: 0, vividness: 1))
            #expect(
                components(palette.hubWellFill).red != components(red).red
                    || components(palette.hubWellFill).green != components(red).green,
                "\(name) hub well matches a red-tinted selected card"
            )
        }
    }

    @Test("Caption chips are legible with no plate behind them")
    func captionChipsAreLegible() {
        for (name, palette) in palettes {
            for (desktop, label) in [(Self.black, "black"), (Self.white, "white")] {
                let value = ratio(text: palette.secondaryText, on: palette.chipFill, over: desktop)
                #expect(
                    value >= Self.minimumRatio,
                    "\(name) chip over \(label): \(value) < \(Self.minimumRatio)"
                )
            }
        }
    }

    /// The list's selected row is filled with the accent colour and its text inverts.
    @Test("Text on the selection colour is legible")
    func textOnAccentIsLegible() {
        for (name, palette) in palettes {
            let primary = ratio(text: palette.onAccentText, on: palette.accentFill, over: Self.black)
            #expect(primary >= Self.minimumRatio, "\(name) on-accent primary: \(primary)")

            let secondary = ratio(
                text: palette.onAccentSecondaryText,
                on: palette.accentFill,
                over: Self.black
            )
            #expect(secondary >= 3.0, "\(name) on-accent secondary: \(secondary)")
        }
    }

    /// The border variant is the brighter one; only the fill variant has to hold text.
    /// If they were ever collapsed into one value, one of the two jobs would regress.
    @Test("The selection fill is darker than the selection border")
    func selectionFillIsDarkerThanBorder() {
        for (name, palette) in palettes {
            let border = luminance(components(palette.accent))
            let fill = luminance(components(palette.accentFill))
            #expect(fill < border, "\(name) accent fill is not darker than the border")
        }
    }

    // MARK: - Selection visibility

    /// The selection border has to be obvious against the card it outlines, in both
    /// themes, without depending on the window being active.
    @Test("The selection colour stands out against the card it outlines")
    func accentStandsOutAgainstCard() {
        for (name, palette) in palettes {
            let surface = composite(components(palette.selectedCardFill), over: Self.black)
            let value = ratio(components(palette.accent), surface)
            #expect(value >= 1.6, "\(name) accent against selected card: \(value)")
        }
    }

    /// Only the list draws a backdrop. For every other arrangement a card is the sole thing between
    /// its own caption and the desktop, so these surfaces have to be fully opaque rather than
    /// merely close to it.
    ///
    /// The last few percent were not cosmetic. At 92–96% a text-heavy window behind the overlay read
    /// straight through it, and the spiral's hollow middle was the worst case: the most translucent
    /// surface in the app carrying the smallest type.
    @Test("Surfaces that carry text are opaque, so contrast cannot depend on the desktop")
    func textCarryingSurfacesAreOpaque() {
        for (name, palette) in palettes {
            for (fill, fillName) in [
                (palette.cardFill, "cardFill"),
                (palette.selectedCardFill, "selectedCardFill"),
                (palette.chipFill, "chipFill"),
                (palette.thumbnailFill, "thumbnailFill"),
                (palette.hubWellFill, "hubWellFill"),
            ] {
                #expect(
                    components(fill).alpha == 1,
                    "\(name) \(fillName) is translucent; the desktop will read through it"
                )
            }
        }
    }

    /// A tint must not reintroduce the translucency either.
    @Test("Tinting keeps a fill opaque at every hue")
    func tintedFillsAreOpaque() {
        for (name, palette) in palettes {
            for tint in Self.everyHue {
                #expect(
                    components(palette.cardFill(tintedBy: tint)).alpha == 1,
                    "\(name) hue \(tint.hue) produced a translucent fill"
                )
            }
        }
    }

    // MARK: - Theme selection

    // MARK: - Icon tints

    /// Every hue an icon can possibly have, at full vividness, which is the strongest tint the
    /// palette will ever apply.
    private static let everyHue: [IconTint] = stride(from: 0.0, to: 1.0, by: 1.0 / 72.0)
        .map { IconTint(hue: $0, vividness: 1) }

    /// The guarantee that makes tinting safe at all: the hue is the icon's, but the luminance band
    /// is the palette's, so text keeps clearing 4.5:1 whatever application it belongs to.
    ///
    /// Without this the feature would reintroduce exactly the regression this suite was written
    /// for — a fill chosen from something other than the palette, and contrast left to luck.
    @Test("Tinted cards keep their text legible at every hue")
    func tintedCardsKeepTextLegible() {
        for (name, palette) in palettes {
            for tint in Self.everyHue {
                for (desktop, label) in [(Self.black, "black"), (Self.white, "white")] {
                    for (fill, fillName) in [
                        (palette.cardFill(tintedBy: tint), "cardFill"),
                        (palette.selectedCardFill(tintedBy: tint), "selectedCardFill"),
                        (palette.radialSelectedFill(tintedBy: tint), "radialSelectedFill"),
                    ] {
                        let primary = ratio(text: palette.text, on: fill, over: desktop)
                        #expect(
                            primary >= Self.minimumRatio,
                            """
                            \(name) \(fillName) hue \(tint.hue) over \(label): \
                            primary \(primary) < \(Self.minimumRatio)
                            """
                        )

                        let secondary = ratio(text: palette.secondaryText, on: fill, over: desktop)
                        #expect(
                            secondary >= Self.minimumRatio,
                            """
                            \(name) \(fillName) hue \(tint.hue) over \(label): \
                            secondary \(secondary) < \(Self.minimumRatio)
                            """
                        )
                    }
                }
            }
        }
    }

    /// Tinting must not thin the fill out, or contrast would start depending on the desktop again.
    @Test("Tinted fills stay as opaque as the flat ones")
    func tintedFillsStayOpaque() {
        for (name, palette) in palettes {
            for tint in Self.everyHue {
                let tinted = components(palette.cardFill(tintedBy: tint))
                #expect(
                    tinted.alpha == components(palette.cardFill).alpha,
                    "\(name) hue \(tint.hue) changed the fill's opacity"
                )
            }
        }
    }

    /// The selection colour is deliberately not tintable. It is the one unambiguous signal on
    /// screen, and it would stop being one if it shifted hue with the selected application.
    @Test("A window with no usable icon colour gets the flat palette")
    func noTintMeansNoChange() {
        for (_, palette) in palettes {
            #expect(palette.cardFill(tintedBy: nil) == palette.cardFill)
            #expect(palette.selectedCardFill(tintedBy: nil) == palette.selectedCardFill)
            #expect(palette.radialSelectedFill(tintedBy: nil) == palette.selectedCardFill)
        }
    }

    /// Distinct hues have to produce distinct fills, or the feature buys nothing.
    @Test("Different hues produce visibly different fills")
    func differentHuesDiffer() {
        for (name, palette) in palettes {
            let red = components(palette.cardFill(tintedBy: IconTint(hue: 0, vividness: 1)))
            let green = components(palette.cardFill(tintedBy: IconTint(hue: 1.0 / 3, vividness: 1)))
            let blue = components(palette.cardFill(tintedBy: IconTint(hue: 2.0 / 3, vividness: 1)))

            #expect(abs(red.red - green.red) > 0.02, "\(name) red and green fills are too close")
            #expect(abs(green.green - blue.green) > 0.02, "\(name) green and blue fills are too close")
            #expect(abs(blue.blue - red.blue) > 0.02, "\(name) blue and red fills are too close")
        }
    }

    /// A selected radial wedge has to be a stronger self, not merely a different border.
    ///
    /// Compared as distance from the untinted base across all three channels: a red icon on a
    /// white card only moves green and blue, so looking at the red channel alone reports no tint.
    @Test("A selected radial wedge is more tinted than an unselected one")
    func radialSelectedIsStronger() {
        for (name, palette) in palettes {
            let tint = IconTint(hue: 0, vividness: 1)
            let rest = components(palette.cardFill(tintedBy: tint))
            let restBase = components(palette.cardFill)
            let selected = components(palette.radialSelectedFill(tintedBy: tint))
            let selectedBase = components(palette.selectedCardFill)
            let restDelta = abs(rest.red - restBase.red)
                + abs(rest.green - restBase.green)
                + abs(rest.blue - restBase.blue)
            let selectedDelta = abs(selected.red - selectedBase.red)
                + abs(selected.green - selectedBase.green)
                + abs(selected.blue - selectedBase.blue)
            #expect(
                selectedDelta > restDelta,
                "\(name) selected radial tint \(selectedDelta) is not stronger than rest \(restDelta)"
            )
        }
    }

    // MARK: - Sampling

    private func solidImage(_ color: NSColor, side: Int = 32) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32
        ) else {
            Issue.record("could not allocate a test bitmap")
            return NSImage()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    @Test("A solid icon reports its own hue")
    func sampledHueMatchesTheIcon() {
        let cases: [(name: String, color: NSColor, hue: Double)] = [
            ("red", NSColor(srgbRed: 0.90, green: 0.15, blue: 0.15, alpha: 1), 0),
            ("green", NSColor(srgbRed: 0.15, green: 0.80, blue: 0.25, alpha: 1), 1.0 / 3),
            ("blue", NSColor(srgbRed: 0.15, green: 0.25, blue: 0.90, alpha: 1), 2.0 / 3),
        ]

        for (name, color, expected) in cases {
            guard let tint = IconTint.sampled(from: solidImage(color)) else {
                Issue.record("\(name) icon reported no tint")
                continue
            }
            // Compared as an angle, so red sampling as 0.99 counts as red rather than as magenta.
            let distance = min(
                abs(tint.hue - expected),
                1 - abs(tint.hue - expected)
            )
            #expect(distance < 0.05, "\(name) sampled as hue \(tint.hue), expected \(expected)")
            #expect(tint.vividness > 0.4, "\(name) sampled as washed out: \(tint.vividness)")
        }
    }

    /// A monochrome icon has no hue to report, and inventing one would tint two unrelated
    /// applications identically.
    @Test("Grey, black and white icons report no tint")
    func monochromeIconsReportNoTint() {
        for (name, color) in [
            ("grey", NSColor(white: 0.5, alpha: 1)),
            ("black", NSColor(white: 0.02, alpha: 1)),
            ("white", NSColor(white: 1, alpha: 1)),
        ] {
            #expect(
                IconTint.sampled(from: solidImage(color)) == nil,
                "\(name) icon produced a tint"
            )
        }
    }

    /// A fully transparent icon has no pixels worth sampling.
    @Test("A transparent icon reports no tint")
    func transparentIconReportsNoTint() {
        #expect(IconTint.sampled(from: solidImage(.clear)) == nil)
    }

    // MARK: - Separation

    /// Shortest distance between two hues, treating them as angles.
    private func hueDistance(_ first: Double, _ second: Double) -> Double {
        let raw = abs(first - second)
        return min(raw, 1 - raw)
    }

    /// The case from a real desktop: Figma, VS Code and Safari all sample within six degrees, so
    /// faithfully reporting their hues produces three containers that look the same.
    @Test("Clustered hues are pushed apart")
    func clusteredHuesAreSeparated() {
        let clustered = [
            "com.figma.Desktop": IconTint(hue: 0.549, vividness: 0.9),
            "com.microsoft.VSCode": IconTint(hue: 0.567, vividness: 0.9),
            "com.apple.Safari": IconTint(hue: 0.568, vividness: 0.9),
        ]

        let separated = IconTint.separated(clustered)
        #expect(separated.count == clustered.count)

        let hues = separated.values.map(\.hue).sorted()
        for (first, second) in zip(hues, hues.dropFirst()) {
            // Not the full separation for every pair — the drift limit takes precedence — but
            // enough that neighbouring containers no longer read as one colour.
            #expect(
                hueDistance(first, second) > 0.02,
                "hues \(first) and \(second) are still indistinguishable"
            )
        }
    }

    /// The honesty limit. A blue application must still look blue, or the tint has stopped
    /// describing its icon and is simply making colours up.
    @Test("No hue is moved further than the drift limit")
    func separationRespectsTheDriftLimit() {
        // Eight icons crammed into 20°, which is worse than any real desktop.
        let crowded = Dictionary(
            uniqueKeysWithValues: (0..<8).map { index in
                ("app.\(index)", IconTint(hue: 0.55 + Double(index) * 0.007, vividness: 1))
            }
        )

        let separated = IconTint.separated(crowded)
        for (key, tint) in crowded {
            guard let moved = separated[key] else {
                Issue.record("\(key) lost its tint")
                continue
            }
            #expect(
                hueDistance(tint.hue, moved.hue) <= 0.0601,
                "\(key) drifted from \(tint.hue) to \(moved.hue)"
            )
        }
    }

    /// Hues that are already far apart are left exactly as their icons reported them.
    @Test("Well-spread hues are left alone")
    func spreadHuesAreUnchanged() {
        let spread = [
            "red": IconTint(hue: 0.02, vividness: 1),
            "green": IconTint(hue: 0.35, vividness: 1),
            "blue": IconTint(hue: 0.62, vividness: 1),
        ]
        #expect(IconTint.separated(spread) == spread)
    }

    @Test("A single tint is never moved")
    func singleTintIsUnchanged() {
        let single = ["only": IconTint(hue: 0.5, vividness: 0.8)]
        #expect(IconTint.separated(single) == single)
    }

    /// Separation must not depend on dictionary iteration order, or an application's colour would
    /// change between presentations for no visible reason.
    @Test("Separation is stable whatever order the tints arrive in")
    func separationIsOrderIndependent() {
        let pairs = [
            ("com.a.app", IconTint(hue: 0.550, vividness: 1)),
            ("com.b.app", IconTint(hue: 0.556, vividness: 1)),
            ("com.c.app", IconTint(hue: 0.562, vividness: 1)),
            ("com.d.app", IconTint(hue: 0.300, vividness: 1)),
        ]

        let forward = IconTint.separated(Dictionary(uniqueKeysWithValues: pairs))
        let backward = IconTint.separated(Dictionary(uniqueKeysWithValues: pairs.reversed()))
        #expect(forward == backward)
    }

    /// Vividness belongs to the icon and is never traded away for separation.
    @Test("Separation changes only the hue")
    func separationPreservesVividness() {
        let tints = [
            "a": IconTint(hue: 0.55, vividness: 0.42),
            "b": IconTint(hue: 0.56, vividness: 0.91),
        ]
        let separated = IconTint.separated(tints)
        #expect(separated["a"]?.vividness == 0.42)
        #expect(separated["b"]?.vividness == 0.91)
    }

    /// Every separated hue still has to survive the palette's contrast guarantee.
    @Test("Separated hues stay legible")
    func separatedHuesStayLegible() {
        let clustered = Dictionary(
            uniqueKeysWithValues: (0..<12).map { index in
                ("app.\(index)", IconTint(hue: 0.10 + Double(index) * 0.005, vividness: 1))
            }
        )

        for (name, palette) in palettes {
            for tint in IconTint.separated(clustered).values {
                for (desktop, label) in [(Self.black, "black"), (Self.white, "white")] {
                    let fill = palette.cardFill(tintedBy: tint)
                    let secondary = ratio(text: palette.secondaryText, on: fill, over: desktop)
                    #expect(
                        secondary >= Self.minimumRatio,
                        "\(name) separated hue \(tint.hue) over \(label): \(secondary)"
                    )
                }
            }
        }
    }

    // MARK: - Theme selection

    @Test("The palette follows the system appearance")
    func paletteFollowsAppearance() {
        #expect(OverlayPalette.forScheme(.dark).text == OverlayPalette.dark.text)
        #expect(OverlayPalette.forScheme(.light).text == OverlayPalette.light.text)

        // The two themes must genuinely differ, or one appearance is wrong.
        #expect(OverlayPalette.dark.text != OverlayPalette.light.text)
        #expect(OverlayPalette.dark.cardFill != OverlayPalette.light.cardFill)
        // Selection colour is intentionally shared: it is the product's colour, not a
        // system accent that would desaturate in a window that is never key.
        #expect(OverlayPalette.dark.accent == OverlayPalette.light.accent)
    }
}
