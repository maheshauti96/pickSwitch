import SwiftUI

/// Marks a result as a browser tab rather than a window.
///
/// Worth distinguishing, because the two behave differently in ways the user can feel: a
/// tab has no preview of its own, cannot be closed from here, and switching to one changes
/// what the browser is showing rather than just which window is in front.
struct TabBadge: View {

    var isOnAccent: Bool = false

    @Environment(\.overlayPalette) private var palette

    private var foreground: Color {
        isOnAccent ? palette.onAccentSecondaryText : palette.secondaryText
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "square.on.square")
                .font(.system(size: 8, weight: .medium))
            Text("Tab")
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
        .help("An open browser tab")
    }
}
