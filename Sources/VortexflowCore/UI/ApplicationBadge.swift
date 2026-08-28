import SwiftUI

/// Marks a search result as an installed application to open rather than an existing window.
struct ApplicationBadge: View {

    var isOnAccent: Bool = false

    @Environment(\.overlayPalette) private var palette

    private var foreground: Color {
        isOnAccent ? palette.onAccentSecondaryText : palette.secondaryText
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 8, weight: .medium))
            Text("App")
                .font(.system(size: 9, weight: .semibold))
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
        .help("An installed application; selecting it opens the app")
    }
}
