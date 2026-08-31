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
    /// The application's icon. Identifies whose window this is, and stands in for a capture that
    /// has not arrived.
    let icon: NSImage?
    /// Minimize and close, drawn into the top-right of the identity bar.
    var windowControls: [CardMenuItem] = []
    /// Previous / pause / next, drawn under the facts when this window is playing,
    /// matching Chrome's own media controls on a playing tab.
    var media: [CardMenuItem] = []
    /// Tab search, drawn as a labelled row immediately under the preview.
    var contents: [CardMenuItem] = []
    /// The four halves, matching macOS Move & Resize.
    var moveResize: [CardMenuItem] = []
    /// Fill and the remaining arrangements, matching macOS Fill & Arrange.
    var fillArrange: [CardMenuItem] = []
    /// Full Screen and Move to another display.
    var placement: [CardMenuItem] = []
    @ObservedObject var hover: CardMenuHoverModel
    let onAction: (CardMenuItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            identityBar
            preview
            // Title, site, Desktop/Audio/Window — the same facts the hub names this
            // card with — sit directly under the picture, before tiling. That is the
            // Chrome media-card shape: artwork, what is playing, then controls.
            if showsCaption { caption }
            if hasFacts { facts }
            if !media.isEmpty { mediaRow }
            if !contents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(contents.enumerated()), id: \.offset) { _, action in
                        placementRow(action)
                    }
                }
            }
            if hasArrangement {
                Divider().opacity(0.6)
                arrangement
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(width: Self.width, alignment: .leading)
        // No `allowsHitTesting(false)` any more, and that is the consequence of moving the controls
        // inside this block: it used to be a pure label, and a label must not swallow the click on its
        // way to the menu's tracking loop. Now it contains buttons, so the item is enabled and the
        // view handles its own events — which is what a menu item's view is responsible for. Clicking
        // the inert parts does nothing, exactly as clicking a disabled menu item does nothing.
        .accessibilityElement(children: .contain)
    }

    private var hasArrangement: Bool {
        !moveResize.isEmpty || !fillArrange.isEmpty || !placement.isEmpty
    }

    private var hasFacts: Bool {
        !details.rows.isEmpty
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

    private var showsCaption: Bool {
        showsTitle || showsIdentifyingSource
    }

    /// The window title is worth a line when it is not just the application name again — "YouTube
    /// Music" under Google Chrome, not a second "Slack".
    private var showsTitle: Bool {
        let title = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title != details.applicationName
    }

    private var showsIdentifyingSource: Bool {
        if let source = details.identifyingSource, !source.isEmpty { return true }
        return false
    }

    /// Window title and site, under the preview, matching what the hub says about this card.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 1) {
            if showsTitle {
                Text(details.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
            }
            if let source = details.identifyingSource, !source.isEmpty {
                Text(source)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Chrome's Global Media Controls: previous, pause, next as a single player
    /// cluster, not a captioned glyph row. Captions would make this look like
    /// the tiling grid; the skip/pause glyphs are already the words.
    private var mediaRow: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(Array(media.enumerated()), id: \.offset) { _, action in
                    transportButton(action)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.45))
            )
            Spacer(minLength: 0)
        }
    }

    private func transportButton(_ action: CardMenuItem) -> some View {
        let isHovered = hover.isHovered(action)
        let isPause = action == .pausePlayback
        let symbol: String = {
            guard isPause else { return action.icon.symbolName }
            return hover.isPlaybackPaused ? "play.fill" : "pause.fill"
        }()
        let name = isPause
            ? (hover.isPlaybackPaused ? "Play" : "Pause")
            : action.title
        return Button {
            onAction(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: isPause ? 16 : 13, weight: .semibold))
                .frame(width: 52, height: 36)
                .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.accentColor : Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.setHovered(action, $0) }
        .accessibilityLabel(name)
        .help(name)
    }

    /// Application icon and name on the left, minimize and close on the right.
    private var identityBar: some View {
        HStack(alignment: .center, spacing: 7) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }
            Text(details.applicationName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            ForEach(Array(windowControls.enumerated()), id: \.offset) { _, action in
                CardMenuGlyphButton(action: action, hover: hover, onAction: onAction)
            }
        }
        // One element for everything descriptive: whose window, its title, the facts. VoiceOver
        // reads the menu item this view belongs to, so the facts have to arrive as that item's
        // label rather than as separate elements it would never visit.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The two grids macOS itself uses, then Full Screen and Move to another display.
    ///
    /// Below the preview rather than in a corner of it, because eight placements do not fit in a
    /// corner and because that is where the system menu puts them.
    private var arrangement: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !moveResize.isEmpty {
                tileSection(title: "Move & Resize", actions: moveResize)
            }
            if !fillArrange.isEmpty {
                tileSection(title: "Fill & Arrange", actions: fillArrange)
            }
            if !placement.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(placement.enumerated()), id: \.offset) { _, action in
                        Divider().opacity(0.6)
                        placementRow(action)
                    }
                }
            }
        }
    }

    private func tileSection(title: String, actions: [CardMenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    CardMenuGlyphButton(
                        action: action,
                        fillsWidth: true,
                        hover: hover,
                        onAction: onAction
                    )
                }
            }
        }
    }

    /// A labelled row, matching how macOS draws Full Screen and Move to Display under the grids.
    private func placementRow(_ action: CardMenuItem) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.icon.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(action.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(hover.isHovered(action) ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hover.isHovered(action) ? Color.accentColor : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover.setHovered(action, $0) }
        .accessibilityLabel(action.title)
        .help(action.title)
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
        .accessibilityHidden(true)
    }

    /// One string for the whole block. VoiceOver reads the menu item this view belongs to, so the
    /// facts have to arrive as that item's label rather than as separate elements it would never
    /// visit.
    private var accessibilityLabel: String {
        var parts = [details.applicationName, details.title]
        if details.source != details.applicationName {
            parts.append(details.source)
        }
        parts += details.rows.map { "\($0.label): \($0.value)" }
        return parts.joined(separator: ", ")
    }
}
