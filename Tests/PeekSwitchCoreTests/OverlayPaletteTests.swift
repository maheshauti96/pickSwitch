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

    @Test("Card fills are near-opaque, so contrast cannot depend on the desktop")
    func cardFillsAreNearOpaque() {
        for (name, palette) in palettes {
            #expect(components(palette.cardFill).alpha >= 0.9, "\(name) cardFill is too sheer")
            #expect(components(palette.selectedCardFill).alpha >= 0.9, "\(name) selected fill is too sheer")
            #expect(components(palette.thumbnailFill).alpha >= 0.98, "\(name) thumbnail well is not opaque")
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
