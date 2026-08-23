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
    let seat: SpiralLayout.Seat
    /// Centre of the spiral in panel coordinates.
    let centre: CGPoint
    /// Size of the panel, which is also this view's size.
    let panelSize: CGSize
    let isSelected: Bool
    let isHovered: Bool
    let badgeCount: Int?
    let reduceMotion: Bool
    var metrics: OverlayCardMetrics = .spiral
    var display: DisplayInfo?
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

    private var content: some View {
        VStack(spacing: 3) {
            icon
            label
        }
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
                    .frame(width: metrics.artworkIconSize, height: metrics.artworkIconSize)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: metrics.artworkIconSize * 0.6, weight: .light))
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
                    .frame(width: metrics.artworkIconSize, height: metrics.artworkIconSize)
            }

            if entry.isMinimized {
                minimizedBadge
            }
        }
        .frame(height: metrics.artworkHeight)
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
                .truncationMode(.tail)
                .foregroundStyle(textColor)

            if let display {
                Text(display.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
            }

            if let badgeCount {
                Text("\(badgeCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                isSelected ? palette.onAccentSecondaryText.opacity(0.5) : palette.strongBorder,
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(isSelected ? palette.onAccentSecondaryText : palette.secondaryText)
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
        if let display { parts.append(display.label) }
        if entry.isMinimized { parts.append("minimized") }
        if let badgeCount { parts.append("\(badgeCount) windows") }
        return parts.joined(separator: ", ")
    }
}
