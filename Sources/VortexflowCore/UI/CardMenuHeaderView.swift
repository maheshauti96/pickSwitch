import AppKit
import SwiftUI

/// The preview and facts shown at the top of a card's context menu.
///
/// This view exists to be a *fixed* width, which is the whole reason the menu stopped sprawling. An
/// `NSMenu` is as wide as its widest item, and the heading item used to carry `entry.displayTitle`
/// verbatim — so a browser window titled with a full product name and a site suffix stretched the
/// menu across a third of the screen, and every short action item was padded out to match. Nothing
/// about the actions needed that room. Pinning the width here and truncating inside it means the
/// title no longer votes on how wide the menu is.
///
/// Deliberately styled with system semantic colours rather than `OverlayPalette`. The overlay's
/// palette belongs to the overlay's own chrome, drawn over the desktop on a plate we control. This is
/// drawn by AppKit inside a real menu, whose material and vibrancy come from the system, so borrowing
/// the overlay's colours would leave the header subtly out of step with the items directly below it.
struct CardMenuHeaderView: View {

    /// Fixed, and the reason the menu is no longer content-sized. Wide enough for a legible preview
    /// and a two-column fact list; narrow enough to sit under a pointer without covering the card it
    /// describes.
    static let width: CGFloat = 268

    private static let horizontalPadding: CGFloat = 13

    /// The preview well, exposed so the capture can be requested at the size it will be drawn at
    /// rather than at a size guessed elsewhere.
    static let previewWidth = width - horizontalPadding * 2
    /// 16:10 rather than 16:9. Most windows are not full-screen, and the taller box wastes less on
    /// letterboxing for the portrait-ish shapes that are common at this size.
    static let previewHeight = (previewWidth * 10 / 16).rounded()

    let details: CardDetails
    /// The live capture of this window, when one has arrived.
    let thumbnail: CGImage?
    /// Favicon for a matched browser window, otherwise the application's icon. Stands in for a
    /// capture that has not arrived, and identifies the application beside the title either way.
    let icon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            preview
            caption
            if !details.rows.isEmpty || details.displayNumber != nil {
                Divider().opacity(0.6)
                footer
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(width: Self.width, alignment: .leading)
        // The header is a label, not a target. Without this the whole block would swallow the click
        // that is on its way to the menu's tracking loop.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var preview: some View {
        ZStack {
            // Filled rather than left clear: an empty well should read as a picture area awaiting a
            // capture, not as a hole through the menu.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))

            if let thumbnail {
                Image(decorative: thumbnail, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    .resizable()
                    // Never distort the window's proportions, as everywhere else the capture is shown.
                    .aspectRatio(contentMode: .fit)
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.previewWidth, height: Self.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var caption: some View {
        HStack(alignment: .top, spacing: 7) {
            // Repeated beside the title even when it is also standing in for the preview above: at
            // 52pt in the well it reads as artwork, and at 16pt here it reads as identification.
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Two lines, because window titles carry the useful part at either end — a document
                // name at the front, a site or project at the back — and one line too often cuts off
                // whichever end distinguishes this window from the next.
                Text(details.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)

                Text(details.source)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    /// Facts at the leading edge, the screen chip trailing at the bottom.
    ///
    /// Bottom-aligned rather than top, so the chip stays in the corner however many facts sit beside
    /// it — anchored to the block's edge rather than floating against the first row.
    private var footer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !details.rows.isEmpty { facts }
            Spacer(minLength: 0)
            if let number = details.displayNumber {
                displayChip(number)
            }
        }
    }

    /// Which screen, as a colour first and a number second.
    ///
    /// The colour is what makes this quicker than the row it replaced: two menus opened on two windows
    /// answer "same screen or not" without either number being read. It is keyed on the display number
    /// so it is stable for a session — the same screen is the same colour every time the menu opens.
    private func displayChip(_ number: Int) -> some View {
        let tint = Self.displayTint(number)
        return Text("Display \(number)")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(0.16))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.5)
            )
            .fixedSize()
    }

    /// One colour per screen, wrapping if someone runs more displays than there are colours.
    ///
    /// Chosen to stay apart from each other rather than to be pretty: adjacent entries differ in hue
    /// far enough that two chips seen a second apart are not mistaken for one another, which is the
    /// only job the colour has.
    static func displayTint(_ number: Int) -> Color {
        let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .green]
        // Display numbers are 1-based, and a hostile or unset value must not trap on a negative index.
        let index = max(0, number - 1) % palette.count
        return palette[index]
    }

    /// A two-column grid, so the values line up whatever the labels are. Run together as
    /// "Desktop: Another · 20m ago · Tabs: 23 tabs" the same facts wrap unpredictably inside a fixed
    /// width and stop being scannable.
    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 3) {
            ForEach(details.rows, id: \.label) { row in
                GridRow {
                    Text(row.label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .gridColumnAlignment(.leading)
                    Text(row.value)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }

    /// One string for the whole block. VoiceOver reads the menu item this view belongs to, so the
    /// facts have to arrive as that item's label rather than as separate elements it would never
    /// visit.
    private var accessibilityLabel: String {
        var parts = [details.title, details.source]
        parts += details.rows.map { "\($0.label): \($0.value)" }
        // Spoken, because the chip's colour carries meaning that a screen reader cannot convey and
        // must not be the only way the screen is identified.
        if let number = details.displayNumber { parts.append("Display \(number)") }
        return parts.joined(separator: ", ")
    }
}
