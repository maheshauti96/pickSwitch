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
