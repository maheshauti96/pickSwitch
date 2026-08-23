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
/// The design solves this the same way: cards carry their own near-opaque fill
/// (92–94%) and name their text colour outright, so contrast is a property of the card
/// rather than a lucky consequence of what happens to be behind it.
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

    static func forScheme(_ scheme: ColorScheme) -> OverlayPalette {
        scheme == .dark ? .dark : .light
    }

    /// `--ps-*` dark theme.
    static let dark = OverlayPalette(
        cardFill: Color(.sRGB, red: 38 / 255, green: 44 / 255, blue: 51 / 255, opacity: 0.94),
        selectedCardFill: Color(.sRGB, red: 46 / 255, green: 54 / 255, blue: 63 / 255, opacity: 0.98),
        thumbnailFill: Color(.sRGB, red: 25 / 255, green: 29 / 255, blue: 34 / 255, opacity: 1),
        border: Color(.sRGB, white: 1, opacity: 0.10),
        strongBorder: Color(.sRGB, white: 1, opacity: 0.20),
        text: Color(.sRGB, white: 1, opacity: 1),
        secondaryText: Color(.sRGB, white: 1, opacity: 0.58),
        chipFill: Color(.sRGB, red: 18 / 255, green: 22 / 255, blue: 26 / 255, opacity: 0.86),
        accent: Self.brand,
        accentFill: Self.brandFill,
        onAccentText: .white,
        onAccentSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        liveIndicator: Color(.sRGB, red: 98 / 255, green: 197 / 255, blue: 238 / 255, opacity: 1)
    )

    /// `--ps-*` light theme.
    static let light = OverlayPalette(
        cardFill: Color(.sRGB, white: 1, opacity: 0.96),
        selectedCardFill: Color(.sRGB, white: 1, opacity: 1),
        thumbnailFill: Color(.sRGB, red: 231 / 255, green: 229 / 255, blue: 227 / 255, opacity: 1),
        border: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.16),
        strongBorder: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.30),
        text: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 1),
        // The design's 0.55 measures 3.7:1 on a white card, which is short of 4.5:1 for
        // 10pt type. Weighted up until the secondary line actually clears it.
        secondaryText: Color(.sRGB, red: 32 / 255, green: 30 / 255, blue: 29 / 255, opacity: 0.68),
        chipFill: Color(.sRGB, red: 252 / 255, green: 251 / 255, blue: 250 / 255, opacity: 0.92),
        accent: Self.brand,
        accentFill: Self.brandFill,
        onAccentText: .white,
        onAccentSecondaryText: Color(.sRGB, white: 1, opacity: 0.85),
        liveIndicator: Color(.sRGB, red: 0 / 255, green: 106 / 255, blue: 141 / 255, opacity: 1)
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
