import SwiftUI

/// Marks which screen a window is on.
///
/// The glyph does most of the work. "Screen 2" only means something once you have
/// worked out which display is which, whereas a laptop outline versus a monitor
/// outline is immediately the built-in display versus the external one — which is how
/// the question actually gets asked. The number is kept alongside it so the label is
/// still unambiguous with two external monitors, and so it survives a glyph that fails
/// to resolve on some macOS version.
///
/// Only ever shown when more than one display is active; see
/// `OverlayState.display(for:)`.
struct DisplayBadge: View {

    let display: DisplayInfo
    /// Drawn on the accent fill, where the palette's normal text colours would vanish.
    var isOnAccent: Bool = false

    @Environment(\.overlayPalette) private var palette

    private var foreground: Color {
        isOnAccent ? palette.onAccentSecondaryText : palette.secondaryText
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 8, weight: .medium))
            Text(display.shortLabel)
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    isOnAccent ? palette.onAccentSecondaryText.opacity(0.5) : palette.border,
                    lineWidth: 1
                )
        )
        .accessibilityHidden(true)
        .help(display.detailedLabel)
    }
}
