import AppKit
import SwiftUI

/// The large preview of the selected window, used by the list style's detail pane and
/// the radial style's centre.
///
/// Both styles show the same thing at a different size, and the only real difference
/// is where the caption sits: the radial centre has no room beside the image so the
/// caption floats over it, while the list pane has a column to spare and puts the
/// caption underneath.
struct WindowPreviewView: View {

    let entry: WindowEntry?
    /// Favicon for a matched browser window, otherwise the application's own icon.
    let displayIcon: NSImage?
    let thumbnail: CGImage?
    /// Draw the caption over the image on a gradient instead of below it.
    let overlaysCaption: Bool
    /// Whether the selected window's preview is being refreshed live
    /// (Requirement 9.6–9.8), which is worth saying out loud since it explains why
    /// this one preview moves and the others do not.
    var showsLiveBadge: Bool = true
    /// In Icon View there is no screenshot to show, so the pane shows the application's icon at
    /// size instead. Nothing is captured in that mode, so a "LIVE" badge would be a lie.
    var showsIconInsteadOfThumbnail: Bool = false
    /// Which screen the previewed window is on, when there is more than one. Spoken by VoiceOver
    /// only.
    var display: DisplayInfo?
    /// Whether this is a private browsing window.
    var isIncognito: Bool = false

    @Environment(\.overlayPalette) private var palette

    var body: some View {
        Group {
            if overlaysCaption {
                ZStack(alignment: .bottom) {
                    image
                    captionOverlay
                }
            } else {
                VStack(spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        image
                        if showsLiveBadge, thumbnail != nil { liveBadge.padding(12) }
                    }
                    caption
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var image: some View {
        ZStack {
            // Opaque: the radial centre preview sits over the desktop with no plate
            // behind it, and a translucent well would show the wallpaper through the
            // "picture" and take the caption's contrast with it.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.thumbnailFill)

            if let thumbnail, !showsIconInsteadOfThumbnail {
                Image(decorative: thumbnail, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    .resizable()
                    // Requirement 9.5.
                    .aspectRatio(contentMode: .fit)
            } else if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // Larger in Icon View, where this is the whole point of the pane rather
                    // than a stand-in for a capture that has not arrived.
                    .frame(
                        width: showsIconInsteadOfThumbnail ? 132 : 72,
                        height: showsIconInsteadOfThumbnail ? 132 : 72
                    )
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(palette.liveIndicator)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(palette.liveIndicator)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private var caption: some View {
        HStack(spacing: 10) {
            if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(titleLine)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(palette.text)

                Text(metaLine)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(height: OverlayLayout.List.detailFooterHeight - 12)
    }

    private var captionOverlay: some View {
        HStack(spacing: 8) {
            if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(titleLine)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(palette.text)

                Text(metaLine)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 9)
        .background(
            // Fades the card fill up over the screenshot, so the caption always has
            // something solid under it however light the window behind it is.
            LinearGradient(
                colors: [palette.cardFill.opacity(0), palette.cardFill],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // The caption must not eat clicks aimed at the centre preview.
        .allowsHitTesting(false)
    }

    private var titleLine: String {
        guard let entry else { return "" }
        return entry.isApplication ? entry.applicationName : entry.displayTitle
    }

    /// Built only from facts the enumerator actually has, in the design's
    /// "app · detail" shape. The mock's "active 12 s ago" is still missing:
    /// MRU order is tracked, but not a per-window timestamp worth printing.
    private var metaLine: String {
        guard let entry else { return "" }
        if entry.isApplication {
            return ["Application", "Return to open"].joined(separator: "  ·  ")
        }
        // A tab's address says more than its geometry, which it does not have.
        if let tab = entry.tab {
            return [entry.applicationName, "Tab", tab.host].joined(separator: "  ·  ")
        }
        var parts = [entry.applicationName]
        if isIncognito {
            parts.append("Incognito")
        }
        // No screen here either. Naming the display was the most defensible place to do it, since
        // "DELL U2720Q" beats "Screen 2" — but it is still answering a question the switch
        // animation answers by flying toward that screen.
        if entry.isMinimized {
            parts.append("Minimized")
        } else if entry.frame.width > 1, entry.frame.height > 1 {
            parts.append("\(Int(entry.frame.width)) × \(Int(entry.frame.height))")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var accessibilityLabel: String {
        guard let entry else { return "No window selected" }
        if entry.isApplication {
            return "Open \(entry.applicationName), installed application"
        }
        var label = "Preview of \(entry.applicationName), \(entry.displayTitle)"
        if isIncognito { label += ", incognito" }
        if let display { label += ", \(display.label)" }
        return label
    }
}
