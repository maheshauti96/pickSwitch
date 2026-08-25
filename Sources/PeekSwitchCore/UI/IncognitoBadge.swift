import SwiftUI

/// Marks a private browsing window in the hub caption.
///
/// Everywhere a window is drawn with its icon, the marker goes on the icon instead — see
/// `PrivateWindowIcon`. The hub is the exception: it is a text caption in the centre of the radial
/// arrangement with no icon to badge, and it is also where the eye rests, so the fact still has to
/// be stated there.
///
/// Drawn as a filled disc rather than a bare glyph so that it reads as the same marker as the one on
/// the icons. It was a bare 9-point glyph in the palette's secondary colour, sitting in a row of
/// other small glyphs, and it was reported as unnoticeable twice.
///
/// Spectacles, because that is the metaphor Chromium uses for the mode itself, so it is the one
/// already learned. Not a lock: a lock means HTTPS everywhere else in a browser.
struct IncognitoBadge: View {

    /// Drawn on the accent fill, where the palette's normal text colours would vanish.
    var isOnAccent: Bool = false
    /// Diameter of the disc.
    var size: CGFloat = 14

    @Environment(\.overlayPalette) private var palette

    var body: some View {
        Image(systemName: "eyeglasses")
            // The glasses are wide, so the glyph is sized off the disc's width and left to keep its
            // own proportions rather than being fitted to the height.
            .font(.system(size: size * 0.58, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(white: 0.12)))
            .overlay(
                // Separates the disc from whatever it sits on, in either theme.
                Circle().strokeBorder(
                    isOnAccent ? palette.onAccentSecondaryText : palette.secondaryText,
                    lineWidth: max(1, size * 0.07)
                )
            )
            .accessibilityHidden(true)
            .help("Incognito window")
    }
}
