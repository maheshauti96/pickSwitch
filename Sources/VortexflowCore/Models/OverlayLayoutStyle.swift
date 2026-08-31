import CoreGraphics
import Foundation

/// How the switcher arranges its windows on screen.
///
/// Each style answers a different question the user is asking when they press the trigger:
///
/// - `strip`: "which window did I just come from?" — a horizontal row ordered by
///   recency, cheapest to read at a glance and the default.
/// - `grid`: "show me everything" — every window at once, no scrolling to reason
///   about, best when the target is one of many.
/// - `list`: "I need the titles, not the pictures" — a compact row list beside one
///   large live preview, which is the only style that stays legible with a dozen
///   near-identical windows.
/// - `circular`: "let me aim" — windows as wedges in concentric rings around a hollow hub
///   under the pointer, so selecting is a flick of the wrist rather than a horizontal hunt.
/// - `spiral`: the same, wound as one continuous outward curve rather than as rings.
///
/// The raw values are persisted, so they must stay stable. Value 3 is `circular` because that
/// is the behaviour it has always shipped: the arrangement first added under the name "spiral"
/// snapped its radius per turn, which is what `circular` does. The per-seat winding that the
/// name implied is the new case, and it gets the new value.
enum OverlayLayoutStyle: Int, CaseIterable, Codable, Sendable {

    case strip = 0
    case grid = 1
    case list = 2
    case circular = 3
    case spiral = 4

    var displayName: String {
        switch self {
        case .strip: return "Strip (horizontal row)"
        case .grid: return "Grid (all windows)"
        case .list: return "List with preview"
        case .circular: return "Circular (rings around the pointer)"
        case .spiral: return "Spiral (one winding curve)"
        }
    }

    var shortName: String {
        switch self {
        case .strip: return "Strip"
        case .grid: return "Grid"
        case .list: return "List"
        case .circular: return "Circular"
        case .spiral: return "Spiral"
        }
    }

    var explanation: String {
        switch self {
        case .strip:
            return "A horizontal row of window previews ordered by how recently you used them. Scrolls when there are more windows than fit."
        case .grid:
            return "Every window at once in a grid, centred on the display. Best when you want to see everything rather than step through it."
        case .list:
            return "A compact list of windows beside one large live preview of the selected window. The most readable option when titles matter more than thumbnails."
        case .circular:
            return "Windows as wedges in concentric rings around the pointer, named in the hollow middle as you sweep over them. Every window is shown at once, shrinking to fit rather than paging. The tidier of the two round arrangements: a ring's wedges line up with each other."
        case .spiral:
            return "The same wedges, wound as one continuous curve so each sits slightly further out than the last. Less aligned than concentric rings by nature, and more of a sense of movement."
        }
    }

    /// Where the panel is anchored.
    ///
    /// Strip and radial follow the pointer: both are aimed at, and putting them under
    /// the hand keeps the travel short. Grid and list are large fixed panels that read
    /// as dialogs, and chasing the cursor with them only makes them jump around, so
    /// they sit in the middle of the active display.
    var placementAnchor: OverlayPlacement.Anchor {
        switch self {
        case .strip, .circular, .spiral: return .cursor
        case .grid, .list: return .displayCentre
        }
    }

    /// Whether the panel draws a plate behind the cards.
    ///
    /// Cards already carry their own fill, border and shadow, so for most styles a
    /// plate behind them is a second container around things that are already
    /// containers — it reads as a window floating over the desktop rather than as a
    /// switcher overlaid on it. Strip, grid and radial therefore let the desktop show
    /// through completely; the design's radial mock does exactly this.
    ///
    /// The list keeps its plate. It is the one style whose parts are not
    /// self-contained: unselected rows have no fill of their own, and the row column
    /// and the preview pane only read as one surface if there is a surface.
    var drawsBackdrop: Bool {
        switch self {
        case .strip, .grid, .circular, .spiral: return false
        case .list: return true
        }
    }

    /// Metrics for one window card in this style and view mode.
    ///
    /// Card *sizes* are identical across view modes, deliberately. Every piece of geometry in
    /// `OverlayLayout` — panel size, scroll offset, grid columns, ring radius, hit-testing — is
    /// derived from these sizes, so keeping them fixed means Icon View reuses all of it
    /// unchanged and cannot regress Window View. Only the card's internal composition differs.
    func cardMetrics(for viewMode: OverlayViewMode) -> OverlayCardMetrics {
        switch viewMode {
        case .window:
            switch self {
            case .strip, .list: return .strip
            case .grid: return .grid
            case .circular, .spiral: return .spiral
            }
        case .icon:
            switch self {
            case .strip, .list: return .iconStrip
            case .grid: return .iconGrid
            case .circular, .spiral: return .iconSpiral
            }
        }
    }

    /// How much the selected card grows. The strip lifts the selection out of a dense row,
    /// so it scales more than the roomier grid.
    ///
    /// The spiral does not scale at all. A wedge is positioned by angle and radius, and
    /// scaling one about the centre of its bounding box slides it off the ring and over its
    /// neighbours — so it announces the selection with fill, border and a small pop of the
    /// icon inside it, none of which move the geometry that hit-testing depends on.
    var selectedScale: CGFloat {
        switch self {
        case .strip: return StripLayout.selectedScale
        case .grid: return 1.04
        case .list, .circular, .spiral: return 1.0
        }
    }

    /// Whether this arrangement can show a window screenshot at all.
    ///
    /// The spiral cannot: its seats are annular sectors, and a rectangular capture clipped
    /// to a wedge is unreadable. It draws application icons in either view mode, so
    /// capturing for it would be work whose result is thrown away.
    var canShowThumbnails: Bool {
        radialWinding == nil
    }

    /// View modes this arrangement can actually honour.
    ///
    /// Spiral and Circular have no Window View: a wedge cannot hold a screenshot, so
    /// offering the choice would be a lie. Everything else offers both.
    var availableViewModes: [OverlayViewMode] {
        canShowThumbnails ? OverlayViewMode.allCases : [.icon]
    }

    /// The mode that will actually be drawn for a requested preference.
    func resolvedViewMode(_ requested: OverlayViewMode) -> OverlayViewMode {
        availableViewModes.contains(requested) ? requested : .icon
    }

    /// How this style winds its seats, or `nil` if it is not a round arrangement.
    ///
    /// One accessor rather than `self == .circular || self == .spiral` scattered about: every
    /// place that cares needs the winding as well as the fact, and this way adding a third
    /// winding later touches this switch and nothing else.
    var radialWinding: RadialLayout.Winding? {
        switch self {
        case .strip, .grid, .list: return nil
        case .circular: return .circular
        case .spiral: return .spiral
        }
    }
}

/// Sizing for one window card, so a single card view can serve every layout.
struct OverlayCardMetrics: Equatable, Sendable {

    /// Where the picture sits relative to the text.
    ///
    /// The two modes are mirror images: Window View leads with the screenshot and explains it
    /// underneath, Icon View states what the window is and then shows its icon. Naming it as a
    /// layout rather than a boolean keeps the card view honest about which half is which.
    enum ContentLayout: Equatable, Sendable {
        /// Screenshot on top, details beneath. Window View.
        case artworkThenMetadata
        /// Details on top, large icon beneath. Icon View.
        case metadataThenArtwork
    }

    let size: CGSize
    /// Height of the picture area — a screenshot in Window View, an application icon in Icon
    /// View. The remainder of the card is the metadata block.
    let artworkHeight: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    /// Whether the footer carries a second line with the application name.
    let showsSubtitle: Bool
    /// Radial seats are too small for a window title, so they name the application
    /// instead — which is also the thing you can recognise at ring distance.
    let usesApplicationNameAsPrimary: Bool
    let contentLayout: ContentLayout
    /// Side length of the application icon in Icon View. Ignored in Window View, where the
    /// artwork is a screenshot that fills the area.
    let artworkIconSize: CGFloat

    /// The text block: whatever the artwork does not occupy.
    var metadataHeight: CGFloat { size.height - artworkHeight }

    /// The same card at `factor` of its size.
    ///
    /// Only the round arrangements use this, and only because they are the ones that shrink to
    /// fit: every other style has a fixed card and pages instead. Lengths scale outright.
    ///
    /// Font sizes scale but stop at 9pt. Type does not stay legible the way a rectangle does,
    /// and a wedge whose label has gone illegible is worse than one with no label — which is
    /// why the wedge view drops the label entirely once its block is too short to hold one.
    func scaled(by factor: CGFloat) -> OverlayCardMetrics {
        guard factor < 1 else { return self }
        return OverlayCardMetrics(
            size: CGSize(width: size.width * factor, height: size.height * factor),
            artworkHeight: artworkHeight * factor,
            cornerRadius: cornerRadius * factor,
            iconSize: iconSize * factor,
            titleFontSize: max(9, titleFontSize * factor),
            subtitleFontSize: max(9, subtitleFontSize * factor),
            showsSubtitle: showsSubtitle,
            usesApplicationNameAsPrimary: usesApplicationNameAsPrimary,
            contentLayout: contentLayout,
            artworkIconSize: artworkIconSize * factor
        )
    }

    /// Requirement 3.2's card, unchanged: this is the shipped strip geometry.
    static let strip = OverlayCardMetrics(
        size: StripLayout.cardSize,
        artworkHeight: StripLayout.thumbnailHeight,
        cornerRadius: 10,
        // The application icon is the fastest thing to recognise on a card — faster than
        // reading a title — so it is worth the extra points. Bounded by the footer height,
        // which is 48pt on a strip card.
        iconSize: 28,
        titleFontSize: 12,
        // The application name is the part people scan for, so it is no longer the
        // afterthought size it was.
        subtitleFontSize: 12,
        showsSubtitle: true,
        usesApplicationNameAsPrimary: false,
        contentLayout: .artworkThenMetadata,
        artworkIconSize: 0
    )

    /// Wider and shorter than a strip card: a grid has horizontal room to spare and
    /// needs the vertical room for extra rows.
    static let grid = OverlayCardMetrics(
        size: CGSize(width: 232, height: 158),
        artworkHeight: 124,
        cornerRadius: 10,
        // A grid card's footer is 34pt, so this is close to the practical ceiling.
        iconSize: 26,
        titleFontSize: 12,
        subtitleFontSize: 11,
        showsSubtitle: false,
        usesApplicationNameAsPrimary: false,
        contentLayout: .artworkThenMetadata,
        artworkIconSize: 0
    )

    // MARK: - Icon View
    //
    // Same card sizes as Window View, inverted composition: the details go on top and a large
    // icon fills the space the screenshot used to. Sizes are held constant on purpose — see
    // `OverlayLayoutStyle.cardMetrics(for:)`.

    /// 208 × 152, as in Window View: 56pt of details over a 96pt icon well.
    static let iconStrip = OverlayCardMetrics(
        size: StripLayout.cardSize,
        artworkHeight: 96,
        cornerRadius: 10,
        // The small icon beside the name is redundant when a large one sits below it.
        iconSize: 0,
        titleFontSize: 13,
        subtitleFontSize: 11,
        showsSubtitle: true,
        usesApplicationNameAsPrimary: false,
        contentLayout: .metadataThenArtwork,
        artworkIconSize: 80
    )

    /// 232 × 158: the roomiest card, so the largest icon.
    static let iconGrid = OverlayCardMetrics(
        size: CGSize(width: 232, height: 158),
        artworkHeight: 100,
        cornerRadius: 10,
        iconSize: 0,
        titleFontSize: 13,
        subtitleFontSize: 11,
        showsSubtitle: true,
        usesApplicationNameAsPrimary: false,
        contentLayout: .metadataThenArtwork,
        artworkIconSize: 84
    )

    // MARK: - Spiral
    //
    // The spiral is the one arrangement where the view mode makes no difference, and both
    // presets are deliberately identical because of it. Its seats are annular sectors, and
    // a rectangular screenshot clipped to a wedge is unreadable — so a wedge shows an
    // application icon whichever mode is selected. `OverlayLayoutStyle.canShowThumbnails`
    // is the other half of that: nothing is captured for this arrangement.
    //
    // `size` here is the seat's upright content box, not a card. The wedge itself is
    // positioned and shaped by `SpiralLayout`, which owns the angles and radii; these
    // metrics only describe what is drawn inside it.

    /// The content box of a wedge: a 52pt icon over up to two lines naming the application.
    ///
    /// Short names remain on one line. Longer names wrap at a word boundary rather than turning
    /// "Google Chrome" into "Googl…"; the hollow middle still carries the selected window title.
    ///
    /// `size` is taken from `RadialLayout` rather than restated, so the two cannot drift. It
    /// is the box at scale 1; the view scales these metrics to match however far the
    /// arrangement has had to shrink.
    static let spiral = OverlayCardMetrics(
        size: RadialLayout.baseContentSize,
        artworkHeight: 52,
        // Generous, to match a wedge 120pt deep. At 9 the corners read as square against
        // arcs that long.
        cornerRadius: 13,
        // No small icon beside the label: the large one is directly above it.
        iconSize: 0,
        // This *is* the application name size — it is the only line a wedge shows.
        titleFontSize: 11,
        subtitleFontSize: 10,
        showsSubtitle: false,
        usesApplicationNameAsPrimary: true,
        contentLayout: .artworkThenMetadata,
        // A ceiling rather than the drawn size: the wedge gives the icon whatever the name and any
        // badges leave, so this only has to be large enough not to cap it first.
        artworkIconSize: 52
    )

    /// Identical to `spiral` by design. See the note above.
    static let iconSpiral = OverlayCardMetrics(
        size: RadialLayout.baseContentSize,
        artworkHeight: 52,
        cornerRadius: 13,
        iconSize: 0,
        titleFontSize: 11,
        subtitleFontSize: 10,
        showsSubtitle: false,
        usesApplicationNameAsPrimary: true,
        contentLayout: .artworkThenMetadata,
        artworkIconSize: 52
    )
}
