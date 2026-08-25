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

    /// How strongly the selected window's own icon shows through the spiral's middle, `0...1`.
    ///
    /// Measured, not chosen. The hub carries the smallest type in the app and every guarantee about
    /// that type assumed a flat fill behind it, so the question is how far the surface under the text
    /// may move. An icon has no luminance to reason about — it can be GitHub's near-black mark or a
    /// near-white one — so the bound comes from the worst case: solid white and solid black at this
    /// opacity, over every tinted fill, in both themes.
    ///
    /// The binding case is the 9-point secondary line, which is *translucent* in both themes, so
    /// moving the surface moves the text with it and the contrast between them closes from both ends.
    /// That is what makes these values as low as they are, and why the light theme's is not simply
    /// larger despite starting from white.
    ///
    /// `OverlayPaletteTests` holds the bound and also holds the opposite: that the value is close to
    /// the largest one that clears 4.5:1, so a future palette change cannot quietly leave the
    /// watermark invisible either.
    let hubArtworkOpacity: Double

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
        chipFill: Color(.sRGB, red: 18 / 255, green: 22 / 255, blue: 26 / 255, opacity: 1),
        accent: Self.brand,
        accentFill: Self.brandFill,
        onAccentText: .white,
        onAccentSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        liveIndicator: Color(.sRGB, red: 98 / 255, green: 197 / 255, blue: 238 / 255, opacity: 1),
        // Fully saturated but dark, which matters more here than it looks. Mixing a *bright* hue
        // into a near-black card raises its luminance, and the secondary line is white at 58% —
        // measured against yellows it fell to 4.4:1, just under the bar. Keeping the hue dark lets
        // the tint colour the card without lightening it, so contrast stays where it was.
        tintStrength: 0.26,
        tintSaturation: 1.0,
        tintBrightness: 0.26,
        // Lower than the light theme's. The dark card is near-black and the text on it is white, so
        // artwork can only close the gap between them; the light theme's white card with dark text
        // has the same asymmetry the other way round and more room to give.
        // Much higher than the opacity-only approach could allow, because the blend direction is
        // what keeps it safe now rather than the number being small.
        hubArtworkOpacity: 0.06
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
        // 10pt type. Weighted up until the secondary line actually clears it.
        secondaryText: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.68),
        chipFill: Color(.sRGB, red: 252 / 255, green: 251 / 255, blue: 250 / 255, opacity: 1),
        accent: Self.brand,
        accentFill: Self.brandFill,
        onAccentText: .white,
        onAccentSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        liveIndicator: Color(.sRGB, red: 0 / 255, green: 106 / 255, blue: 141 / 255, opacity: 1),
        // A light card is white, so every point of tint costs luminance the secondary line is
        // measured against. This is the value the hue sweep in `OverlayPaletteTests` clears with
        // room to spare, and it is still enough to tell a ring of Chrome windows apart.
        tintStrength: 0.15,
        tintSaturation: 0.85,
        tintBrightness: 1.0,
        hubArtworkOpacity: 0.10
    )

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
