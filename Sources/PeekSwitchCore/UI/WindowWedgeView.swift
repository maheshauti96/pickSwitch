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
    /// Favicon for a matched browser window, otherwise the application's own icon.
    let displayIcon: NSImage?
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
    /// Hue taken from this window's icon, so a ring of same-application wedges is still
    /// distinguishable. `nil` leaves the flat palette fill.
    var tint: IconTint?
    /// The spiral draws no plate, so each wedge lifts itself off the desktop.
    var shadowRadius: CGFloat = 9
    var shadowOpacity: Double = 0.34

    @Environment(\.overlayPalette) private var palette

    private var fill: Color {
        // Selection keeps the untinted accent. It is the strongest signal on screen and must not
        // shift hue with whatever application happens to be selected.
        if isSelected { return palette.accentFill }
        if isHovered { return palette.selectedCardFill(tintedBy: tint) }
        return palette.cardFill(tintedBy: tint)
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

    /// Whether the content box can hold both a two-line name and a useful icon.
    ///
    /// A radial label never degrades to one truncated line: it either gets enough room to wrap
    /// or, once the arrangement is too small, disappears and leaves identification to the icon
    /// and hub caption.
    private var labelBandHeight: CGFloat {
        metrics.titleFontSize * 2 + 6
    }

    private var contentSpacing: CGFloat { 2 }

    private var showsLabel: Bool {
        let minimumLabeledIconHeight: CGFloat = 24
        return metrics.size.height
            >= labelBandHeight + contentSpacing + minimumLabeledIconHeight
    }

    @ViewBuilder
    private var content: some View {
        if showsLabel {
            VStack(spacing: contentSpacing) {
                icon
                label
            }
        } else {
            icon
        }
    }

    /// Reserve the label's full two-line band first, then give the remaining height to the icon.
    /// Without a label the icon may use the whole box, keeping a shrunken arrangement legible.
    private var iconBandHeight: CGFloat {
        showsLabel
            ? max(0, metrics.size.height - labelBandHeight - contentSpacing)
            : metrics.size.height
    }

    private var iconSide: CGFloat {
        min(metrics.artworkIconSize, iconBandHeight)
    }

    private var icon: some View {
        ZStack {
            if let applicationIcon = displayIcon {
                // `.interpolation(.high)`: a macOS icon arrives at 512pt and draws here at
                // roughly 44pt, and the default filter makes that downscale visibly mushy.
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
    /// Every visible name may use two lines, so multi-word names such as “Google Chrome” wrap at
    /// their word boundary rather than becoming “Googl…”. At scales too small for two legible
    /// lines, `showsLabel` removes the label instead of bringing the truncation back.
    private var label: some View {
        HStack(spacing: 3) {
            if entry.isTab {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
            }

            if entry.isApplication {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
                    .help("Open installed application")
            }

            Text(entry.applicationName)
                .font(.system(size: metrics.titleFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
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
        .frame(maxWidth: .infinity)
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
        if entry.isApplication { parts.append("installed application") }
        if isIncognito { parts.append("incognito") }
        if let display { parts.append(display.label) }
        if entry.isMinimized { parts.append("minimized") }
        if let badgeCount { parts.append("\(badgeCount) windows") }
        return parts.joined(separator: ", ")
    }
}
