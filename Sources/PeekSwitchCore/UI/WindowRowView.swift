import AppKit
import SwiftUI

/// One row in the list style's sidebar.
///
/// The design's mock showed only the application name per row. That reads well with
/// one window per app and badly with six Chrome windows, so the row carries the
/// application name over the window title: the app name is what you scan for, the
/// title is what disambiguates once you have found it.
struct WindowRowView: View {

    let entry: WindowEntry
    /// Favicon for a matched browser window, otherwise the application's own icon.
    let displayIcon: NSImage?
    let isSelected: Bool
    let isHovered: Bool
    let badgeCount: Int?
    /// Which screen this window is on, when there is more than one. Spoken by VoiceOver only.
    var display: DisplayInfo?
    /// Whether this is a private browsing window.
    var isIncognito: Bool = false
    /// Hue taken from this window's icon. `nil` leaves the row transparent as before.
    var tint: IconTint?

    @Environment(\.overlayPalette) private var palette

    /// Sized against the 40pt row: large enough to recognise, with the two text lines
    /// still fitting beside it.
    private static let iconSize: CGFloat = 26

    private var background: Color {
        // The fill variant, not the border variant: this surface carries text.
        if isSelected { return palette.accentFill }
        if isHovered { return palette.strongBorder.opacity(0.35) }
        // An untinted row stays transparent so the sidebar plate reads as one column; a tinted one
        // becomes its own chip, which is the point of the tint.
        guard let tint else { return .clear }
        return palette.cardFill(tintedBy: tint)
    }

    private var primaryColor: Color {
        isSelected ? palette.onAccentText : palette.text
    }

    private var secondaryColor: Color {
        isSelected ? palette.onAccentSecondaryText : palette.secondaryText
    }

    var body: some View {
        HStack(spacing: 9) {
            if let icon = displayIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 16, weight: .light))
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .foregroundStyle(secondaryColor)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.sourceLabel)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(primaryColor)

                Text(entry.displayTitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(secondaryColor)
            }

            Spacer(minLength: 0)

            if entry.isTab {
                TabBadge(isOnAccent: isSelected)
            }

            if entry.isApplication {
                ApplicationBadge(isOnAccent: isSelected)
            }

            // Private browsing is marked on the icon by `PrivateWindowIcon`, not in this row.

            if entry.isMinimized {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(secondaryColor)
            }

            if let badgeCount {
                Text("\(badgeCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(secondaryColor)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: OverlayLayout.List.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
