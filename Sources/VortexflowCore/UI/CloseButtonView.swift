import SwiftUI

/// The close affordance drawn on the card under the cursor.
///
/// Purely a picture. It is not a `Button`, and that is not an oversight: the overlay
/// panel never becomes key, so SwiftUI gestures inside it are unreliable, and the left
/// click is already intercepted by the HID event tap before AppKit would route it here.
/// Clicks are resolved geometrically against `OverlayLayout.closeButtonFrame(for:)`,
/// which is the same rectangle this view is positioned at — so the drawing and the
/// hit-test cannot disagree.
struct CloseButtonView: View {

    /// True while the cursor is over the button itself, so it can darken under the
    /// pointer the way a real button would.
    var isActive: Bool = false

    @Environment(\.overlayPalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.chipFill)
            Circle()
                .strokeBorder(isActive ? palette.strongBorder : palette.border, lineWidth: 1)
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isActive ? palette.text : palette.secondaryText)
        }
        .frame(width: OverlayLayout.CloseButton.size, height: OverlayLayout.CloseButton.size)
        // Shadowed because it sits over a window screenshot, which can be any colour.
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}
