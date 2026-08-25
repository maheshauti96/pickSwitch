import AppKit
import SwiftUI

/// One window's card (Requirement 3.2).
///
/// Sizing comes from `OverlayCardMetrics` rather than being hard-coded, so the strip,
/// grid and radial styles all draw the same card at their own scale instead of each
/// growing its own near-copy.
struct WindowCardView: View {

    let entry: WindowEntry
    /// Favicon for a matched browser window, otherwise the application's own icon.
    let displayIcon: NSImage?
    let thumbnail: CGImage?
    let isSelected: Bool
    let isHovered: Bool
    let badgeCount: Int?
    let reduceMotion: Bool
    var metrics: OverlayCardMetrics = .strip
    /// Which screen this window is on, when there is more than one. Spoken by VoiceOver only: the
    /// switch animation shows a sighted user the screen by flying toward it, which a description
    /// cannot do.
    var display: DisplayInfo?
    /// Whether this is a private browsing window.
    var isIncognito: Bool = false
    /// Hue taken from this window's icon, so cards of different applications are separable at a
    /// glance. `nil` leaves the flat palette fill.
    var tint: IconTint?

    @Environment(\.overlayPalette) private var palette

    /// Near-opaque, so the card is legible over any desktop rather than only over a
    /// panel plate.
    ///
    /// Selection is carried by the border and glow here rather than by the fill, so a selected
    /// card keeps its tint instead of losing the identity it was picked out of.
    private var fill: Color {
        isSelected
            ? palette.selectedCardFill(tintedBy: tint)
            : palette.cardFill(tintedBy: tint)
    }

    private var borderColor: Color {
        if isSelected { return palette.accent }
        if isHovered { return palette.strongBorder }
        return palette.border
    }

    private var borderWidth: CGFloat {
        // Under Reduce Motion the scale change is gone, so the border carries more
        // of the signal (Requirement 15.2).
        if isSelected { return reduceMotion ? 3 : 2 }
        return 1
    }

    var body: some View {
        VStack(spacing: 0) {
            switch metrics.contentLayout {
            case .artworkThenMetadata:
                thumbnailArea
                infoArea
            case .metadataThenArtwork:
                // Details first, then the icon: the user reads what the window is, then sees
                // which application it belongs to.
                infoArea
                iconArtworkArea
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        // A glow ring on the selection, so it stands out even where the accent border
        // meets a similarly coloured window behind the card.
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(palette.accent.opacity(isSelected ? 0.24 : 0), lineWidth: 5)
                .blur(radius: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Pieces

    /// Icon View's picture area: one large application icon, centred.
    ///
    /// `.interpolation(.high)` matters here. A macOS icon is supplied at 512pt and drawn at 56–76,
    /// and the default interpolation makes that downscale visibly soft — the opposite of the
    /// "large, crisp icon" the mode exists to provide.
    private var iconArtworkArea: some View {
        ZStack {
            if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: metrics.artworkIconSize, height: metrics.artworkIconSize)
            } else {
                // An application with no icon is rare but real; a glyph at the same size keeps
                // the card's proportions rather than collapsing it.
                Image(systemName: "app.dashed")
                    .font(.system(size: metrics.artworkIconSize * 0.62, weight: .light))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: metrics.artworkIconSize, height: metrics.artworkIconSize)
            }

            if entry.isMinimized {
                minimizedBadge
            }
        }
        .frame(width: metrics.size.width, height: metrics.artworkHeight)
        .clipped()
    }

    private var thumbnailArea: some View {
        ZStack {
            // The well is filled explicitly rather than left transparent: an empty
            // preview should read as a picture area waiting for a capture, not as a
            // hole through to the desktop.
            palette.thumbnailFill

            if let thumbnail {
                // `Image(decorative:)` skips the accessibility string; the whole card
                // carries one label instead.
                Image(decorative: thumbnail, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    .resizable()
                    // Requirement 9.5: never distort the window's proportions.
                    .aspectRatio(contentMode: .fit)
            } else {
                // Requirement 9.3 / 9.9: app icon stands in until (or instead of) a
                // capture.
                placeholderIcon
            }

            if entry.isMinimized {
                minimizedBadge
            }
        }
        .frame(width: metrics.size.width, height: metrics.artworkHeight)
        .clipped()
    }

    private var placeholderIcon: some View {
        // Scaled off the thumbnail height so a radial seat does not get a strip-sized
        // icon filling it edge to edge. This is the stand-in shown before a capture
        // arrives, or instead of one without Screen Recording, so it is worth being big
        // enough to identify at a glance.
        let side = min(64, metrics.artworkHeight * 0.56)
        return Group {
            if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: side * 0.67, weight: .light))
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var minimizedBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Label("Minimized", systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
    }

    private var infoArea: some View {
        HStack(spacing: 7) {
            // Suppressed in Icon View: a small icon beside the name is redundant when a large
            // one sits directly below it.
            if metrics.iconSize > 0, let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: metrics.iconSize, height: metrics.iconSize)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Requirement 3.7: one line, tail-truncated.
                Text(primaryText)
                    .font(.system(size: metrics.titleFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Requirement 3.11: named against the card's own fill, which clears
                    // 4.5:1 in both appearances whatever is behind the overlay.
                    .foregroundStyle(palette.text)

                if metrics.showsSubtitle {
                    Text(entry.isApplication ? entry.displayTitle : entry.sourceLabel)
                        .font(.system(size: metrics.subtitleFontSize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if entry.isTab {
                TabBadge()
            }

            if entry.isApplication {
                ApplicationBadge()
            }

            // Private browsing is marked on the icon by `PrivateWindowIcon`, not here. It used to be
            // a glyph in this row and was missed: this row is where secondary details live, and
            // which session a window belongs to is not a secondary detail.

            if let badgeCount {
                // Requirement 3.6. Outlined rather than filled, matching the design's
                // window-count badge.
                Text("\(badgeCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(palette.strongBorder, lineWidth: 1)
                    )
                    .foregroundStyle(isSelected ? palette.text : palette.secondaryText)
                    .help("\(badgeCount) windows in \(entry.applicationName)")
            }
        }
        .padding(.horizontal, 9)
        // Fixed height with single-line text in both rows: the block cannot grow into the
        // artwork, so long titles truncate instead of overlapping.
        .frame(height: metrics.metadataHeight)
    }

    /// A radial seat is too narrow for a window title, so it names the application —
    /// which is the part you can recognise at ring distance anyway.
    private var primaryText: String {
        if entry.isApplication { return entry.applicationName }
        return metrics.usesApplicationNameAsPrimary ? entry.sourceLabel : entry.displayTitle
    }

    private var accessibilityLabel: String {
        var parts = [entry.applicationName, entry.displayTitle]
        if let tab = entry.tab { parts.append("tab, \(tab.host)") }
        if entry.isApplication { parts.append("installed application") }
        // The one result that leaves the switcher entirely, so it says so: every other result
        // raises something already open, and a screen reader user has no other way to tell.
        if entry.isWebSearch { parts.append("opens in your browser") }
        if isIncognito { parts.append("incognito") }
        if let display { parts.append(display.label) }
        if entry.isMinimized { parts.append("minimized") }
        if let badgeCount { parts.append("\(badgeCount) windows") }
        return parts.joined(separator: ", ")
    }
}
