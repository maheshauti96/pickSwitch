import AppKit
import SwiftUI

/// One window as a wedge of the spiral.
///
/// ## Why this is not `WindowCardView`
///
/// A card is a rectangle that contains its own contents. A wedge is an annular sector whose
/// position is an angle, and whose contents sit in an upright box inside it — the box is not
/// the shape, and the shape is not the layout unit. Bending the card view to draw both would
/// mean a rectangle that is sometimes not a rectangle.
///
/// The view is sized to the whole panel and paints only its own sector, for the reason given
/// on `WedgeShape`: drawing and hit-testing are then computed from one description of the
/// ring instead of two.
///
/// ## Why there is no thumbnail
///
/// A rectangular screenshot clipped to a wedge is unreadable, so the spiral shows application
/// icons in both view modes and nothing is captured for it — see
/// `OverlayLayoutStyle.canShowThumbnails`. The window's *title* is not shown here either;
/// there is no room for it at roughly 76pt of arc. The hub carries it instead.
struct WindowWedgeView: View {

    let entry: WindowEntry
    let seat: RadialLayout.Seat
    /// Centre of the arrangement in panel coordinates.
    let centre: CGPoint
    /// Size of the panel, which is also this view's size.
    let panelSize: CGSize
    let isSelected: Bool
    let isHovered: Bool
    let badgeCount: Int?
    let reduceMotion: Bool
    var metrics: OverlayCardMetrics = .spiral
    var display: DisplayInfo?
    /// Whether this is a private browsing window.
    var isIncognito: Bool = false
    /// The spiral draws no plate, so each wedge lifts itself off the desktop.
    var shadowRadius: CGFloat = 9
    var shadowOpacity: Double = 0.34

    @Environment(\.overlayPalette) private var palette

    private var fill: Color {
        if isSelected { return palette.accentFill }
        if isHovered { return palette.selectedCardFill }
        return palette.cardFill
    }

    private var borderColor: Color {
        if isSelected { return palette.accent }
        if isHovered { return palette.strongBorder }
        return palette.border
    }

    private var borderWidth: CGFloat {
        if isSelected { return reduceMotion ? 3 : 2 }
        return 1
    }

    /// Selection is drawn with an accent fill, so the text has to switch with it.
    private var textColor: Color {
        isSelected ? palette.onAccentText : palette.text
    }

    /// The selected wedge pops its icon rather than scaling the wedge.
    ///
    /// Scaling the wedge would move it: a sector is positioned by angle and radius, and
    /// growing it about the centre of its bounding box slides it off the ring and over its
    /// neighbours, while hit-testing carried on using the un-scaled angles. Growing only the
    /// contents gives the same "this one is live" read and moves no geometry.
    private var iconScale: CGFloat {
        guard isSelected, !reduceMotion else { return 1 }
        return 1.12
    }

    private var shape: WedgeShape {
        WedgeShape(seat: seat, centre: centre, cornerRadius: metrics.cornerRadius)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Only the fill casts a shadow. Shadowing the whole stack would blur the glow
            // and the label along with it.
            shape
                .fill(fill)
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: shadowRadius,
                    y: shadowRadius / 2
                )

            shape.stroke(borderColor, lineWidth: borderWidth)

            // A glow on the selection, so it still reads where the accent border meets a
            // similarly coloured window behind the panel.
            if isSelected {
                shape
                    .stroke(palette.accent.opacity(0.28), lineWidth: 5)
                    .blur(radius: 2)
            }

            content
                .frame(width: seat.contentFrame.width, height: seat.contentFrame.height)
                .position(x: seat.contentFrame.midX, y: seat.contentFrame.midY)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Contents

    /// Whether the metadata block still has room for a legible name.
    ///
    /// The arrangement shrinks to seat every window, and past a point the name's block is
    /// shorter than the smallest type worth setting in it. A cramped, clipped label is worse
    /// than none: the icon is the faster identifier anyway, and the hub still spells out
    /// whatever is under the pointer. So below the threshold the icon takes the whole box
    /// rather than sharing it with something unreadable.
    private var showsLabel: Bool {
        metrics.metadataHeight >= metrics.titleFontSize + 4
    }

    @ViewBuilder
    private var content: some View {
        if showsLabel {
            VStack(spacing: 3) {
                icon
                label
            }
        } else {
            icon
        }
    }

    /// Without a label the icon may use the whole box, which is what keeps a heavily shrunken
    /// arrangement identifiable at all.
    private var iconBandHeight: CGFloat {
        showsLabel ? metrics.artworkHeight : metrics.size.height
    }

    private var iconSide: CGFloat {
        min(metrics.artworkIconSize, iconBandHeight)
    }

    private var icon: some View {
        ZStack {
            if let applicationIcon = entry.applicationIcon {
                // `.interpolation(.high)`: a macOS icon arrives at 512pt and draws here at
                // 46, and the default filter makes that downscale visibly mushy.
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSide, height: iconSide)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: iconSide * 0.6, weight: .light))
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
                    .frame(width: iconSide, height: iconSide)
            }

            if entry.isMinimized {
                minimizedBadge
            }
        }
        .frame(height: iconBandHeight)
        .scaleEffect(iconScale)
    }

    /// The application name, plus whichever markers apply.
    ///
    /// One line only. A wedge has about 76pt of arc at the hub radius, which is roughly ten
    /// characters — enough to tell Slack from Safari, and not enough for a window title. The
    /// hub spells the selected window out in full.
    private var label: some View {
        HStack(spacing: 3) {
            if entry.isTab {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
            }

            Text(entry.applicationName)
                .font(.system(size: metrics.titleFontSize, weight: .medium))
                .lineLimit(1)
                // Shrink a little before resorting to an ellipsis. "Google Chrome" is one
                // point too wide for a wedge, and a ring of "Googl…" is most of what made the
                // arrangement look untidy — a name that is 15% smaller reads fine, a name
                // that is cut off does not.
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
                .foregroundStyle(textColor)

            // The glyph alone, without the screen number that `DisplayBadge` also carries.
            // Set beside a name, a bare "2" reads as part of the name — "Kiro 2" looks like a
            // window title. The laptop-versus-monitor outline says the same thing and cannot
            // be misread, and the hub spells the screen out in full for the selection.
            //
            // Deliberately no window-count badge either, unlike the other arrangements. It
            // says how many windows the application has, which is worth knowing on a strip
            // card that stands for one of several — but here every window already has its own
            // wedge, so three Chrome windows are three visible wedges.
            if isIncognito {
                IncognitoBadge(isOnAccent: isSelected, size: max(8, metrics.subtitleFontSize - 1))
            }

            if let display {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
                    .help(display.detailedLabel)
            }
        }
        .padding(.horizontal, 4)
    }

    private var minimizedBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 8, weight: .semibold))
                    .padding(3)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [entry.applicationName, entry.displayTitle]
        if let tab = entry.tab { parts.append("tab, \(tab.host)") }
        if isIncognito { parts.append("incognito") }
        if let display { parts.append(display.label) }
        if entry.isMinimized { parts.append("minimized") }
        if let badgeCount { parts.append("\(badgeCount) windows") }
        return parts.joined(separator: ", ")
    }
}
