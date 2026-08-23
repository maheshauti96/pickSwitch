import SwiftUI

/// Marks a private browsing window.
///
/// Worth its own marker because nothing else on the card distinguishes one. An incognito window
/// carries the same application icon and, very often, a title as generic as "New Tab" — so
/// without this, telling a private window from an ordinary one means switching to it and looking.
///
/// Spectacles rather than a lock or a crossed-out eye: it is the metaphor Chromium itself uses for
/// the mode, so it is the one already learned.
struct IncognitoBadge: View {

    /// Drawn on the accent fill, where the palette's normal text colours would vanish.
    var isOnAccent: Bool = false
    var size: CGFloat = 9

    @Environment(\.overlayPalette) private var palette

    var body: some View {
        Image(systemName: "eyeglasses")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isOnAccent ? palette.onAccentSecondaryText : palette.secondaryText)
            .accessibilityHidden(true)
            .help("Incognito window")
    }
}
