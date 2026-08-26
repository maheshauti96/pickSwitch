import CoreGraphics
import Foundation

/// Geometry for whichever overlay style is in force.
///
/// ## One source of truth
///
/// Every style computes its card rectangles here, and both the view and the click
/// hit-test read them from the same place. That is deliberate rather than tidy: the
/// stuck-drawer bug that shipped earlier was a hit-test that disagreed with what was
/// drawn, and the near-miss after it was the selected card being drawn 8% larger than
/// the rectangle that could be clicked. A layout that returns rectangles, rather than
/// one that describes an arrangement twice, cannot drift that way.
///
/// ## Coordinate spaces
///
/// `positionedCards` returns frames in **panel top-left coordinates**, because that is
/// what SwiftUI's `.position(x:y:)` wants. Hit-testing takes **AppKit panel
/// coordinates** (origin bottom-left), because that is what `NSEvent` and `NSWindow`
/// deal in, and flips once on the way in. The flip lives in exactly one function.
///
/// The strip is the exception and delegates to `StripLayout`: it scrolls by pixels
/// rather than by whole items, and its arrangement is already covered by tests and
/// shipped behaviour.
struct OverlayLayout: Equatable {

    // MARK: - Inputs

    let style: OverlayLayoutStyle
    let cardCount: Int
    let selectedIndex: Int?
    /// Content width the panel may occupy, insets already excluded.
    let availableContentWidth: CGFloat
    /// Content height the panel may occupy. Only the multi-row styles consult it.
    let availableContentHeight: CGFloat
    /// Whether the search field is showing, which reserves a strip along the top.
    ///
    /// Part of the layout rather than an overlay drawn on top, because otherwise the
    /// field would cover the first row of cards. Everything shifts down by the same
    /// amount, so the rectangles the click handler tests move with what is drawn.
    let isSearching: Bool
    /// Index of the first card on screen, for the styles that page by whole items.
    ///
    /// Held by `OverlayState` rather than derived from the selection, and that is the
    /// whole point. Deriving it — centring the window on the selection — meant every
    /// change of selection moved every card. Under the pointer that is a feedback loop:
    /// hovering selects a card, the arrangement shifts, a different card lands under the
    /// cursor, which selects that one instead. It read on screen as the overlay shaking
    /// and flashing. Storing the offset and moving it only when the selection would
    /// otherwise fall off the edge keeps the cards still.
    let visibleStart: Int

    init(
        style: OverlayLayoutStyle,
        cardCount: Int,
        selectedIndex: Int?,
        availableContentWidth: CGFloat,
        availableContentHeight: CGFloat,
        visibleStart: Int = 0,
        isSearching: Bool = false
    ) {
        self.style = style
        self.cardCount = cardCount
        self.selectedIndex = selectedIndex
        self.availableContentWidth = availableContentWidth
        self.availableContentHeight = availableContentHeight
        self.visibleStart = visibleStart
        self.isSearching = isSearching
    }

    /// Height reserved along the top of the panel for the search field.
    static let searchFieldHeight: CGFloat = 40

    /// Vertical shift applied to everything below the search field.
    var searchChrome: CGFloat { isSearching ? Self.searchFieldHeight : 0 }

    /// One card, and which entry it belongs to.
    ///
    /// The index is the entry's index in the full list, not its position on screen, so
    /// a hit-test result can be used directly as a selection even when the style is
    /// showing a window onto a longer list.
    struct PositionedCard: Equatable {
        let index: Int
        /// Frame in panel top-left coordinates, at rest (no selection scaling).
        let frame: CGRect
    }

    // MARK: - Style chrome

    enum Grid {
        static let horizontalInset: CGFloat = 20
        static let topInset: CGFloat = 20
        static let bottomInset: CGFloat = 20
        static let gap: CGFloat = 14
        static let maxColumns = 4

        /// No header row: the design's "ALL WINDOWS" caption was removed as noise, and
        /// the space it reserved goes with it.
        static var topChrome: CGFloat { topInset }
    }

    enum List {
        static let maxPanelWidth: CGFloat = 980
        static let maxPanelHeight: CGFloat = 520
        static let minPanelHeight: CGFloat = 320
        static let sidebarWidth: CGFloat = 312
        /// The preview pane stops being useful below this, so the panel refuses to
        /// shrink past sidebar + this.
        static let minDetailWidth: CGFloat = 380
        /// Tall enough for the application name over the window title, which is what
        /// keeps rows distinguishable when one app owns several windows. Sized against the
        /// 14pt name and 11pt title it has to hold without clipping either.
        static let rowHeight: CGFloat = 46
        static let rowGap: CGFloat = 3
        static let rowInset: CGFloat = 12
        static let verticalInset: CGFloat = 16
        static let detailInset: CGFloat = 20
        static let detailGap: CGFloat = 14
        static let detailFooterHeight: CGFloat = 46

        /// No "RECENT" caption above the rows, so the first row starts at the inset.
        static var sidebarTopChrome: CGFloat { verticalInset }
    }

    /// The per-card close affordance.
    enum CloseButton {
        static let size: CGFloat = 18
        static let inset: CGFloat = 5
    }

    // MARK: - Strip passthrough

    /// The strip's own layout. Also supplies the shared empty-state panel size.
    var strip: StripLayout {
        StripLayout(
            cardCount: cardCount,
            selectedIndex: selectedIndex,
            availableContentWidth: availableContentWidth
        )
    }

    var isScrollable: Bool { style == .strip && strip.isScrollable }
    var maxScrollOffset: CGFloat { style == .strip ? strip.maxScrollOffset : 0 }

    /// Only the strip scrolls by pixels; the other styles page by whole items through
    /// `visibleRange`, so their offset is always zero.
    func scrollOffset(keepingSelectionVisible current: CGFloat) -> CGFloat {
        style == .strip ? strip.scrollOffset(keepingSelectionVisible: current) : 0
    }

    // MARK: - Panel size

    var panelSize: CGSize {
        let content = contentPanelSize
        return CGSize(width: content.width, height: content.height + searchChrome)
    }

    /// The panel without the search field, which is what every other measurement — row
    /// capacity, grid rows, ring radius — is derived from. Reserving space for the field
    /// must not change how many cards fit.
    private var contentPanelSize: CGSize {
        // Requirement 1.8: the "no switchable windows" message needs a box to live in,
        // and it is the same box whichever style is selected.
        guard cardCount > 0 else { return strip.panelSize }

        switch style {
        case .strip:
            return strip.panelSize
        case .grid:
            return gridPanelSize
        case .list:
            return listPanelSize
        case .circular, .spiral:
            return radial?.panelSize ?? strip.panelSize
        }
    }

    // MARK: - Keyboard navigation

    /// How far an arrow key moves the selection in this arrangement, in list positions.
    ///
    /// The arrangements disagree about what an arrow means, and the disagreement is the whole
    /// reason this lives here rather than in the key handling. A grid is the only one where up
    /// and down are not simply "the previous and next window" — they cross a whole row, and only
    /// the layout knows how wide a row currently is.
    ///
    /// Every arrangement accepts all four keys rather than only the two along its own axis. On a
    /// horizontal strip, pressing Down to mean "further along" is a reasonable thing to try, and
    /// having it do nothing teaches the user that the keyboard is unreliable here. The cost of
    /// accepting it is nothing; the cost of ignoring it is a feature that feels broken.
    func selectionStep(for direction: ArrowDirection) -> Int {
        switch style {
        case .grid:
            // A row at a time vertically, so the selection tracks the column it was in.
            switch direction {
            case .left: return -1
            case .right: return 1
            case .up: return -gridColumns
            case .down: return gridColumns
            }

        case .strip, .list, .circular, .spiral:
            // Left and up go back, right and down go forward. For the ring arrangements that
            // means anticlockwise and clockwise, since the seats are laid out clockwise from
            // the top.
            switch direction {
            case .left, .up: return -1
            case .right, .down: return 1
            }
        }
    }

    // MARK: - Grid geometry

    var gridColumns: Int {
        guard cardCount > 0 else { return 1 }
        let card = OverlayCardMetrics.grid.size.width
        let fits = Int(floor((availableContentWidth + Grid.gap) / (card + Grid.gap)))
        return max(1, min(min(fits, Grid.maxColumns), cardCount))
    }

    var gridTotalRows: Int {
        guard cardCount > 0 else { return 0 }
        let columns = gridColumns
        return (cardCount + columns - 1) / columns
    }

    /// Rows that fit the display, which is what caps the panel height.
    var gridVisibleRows: Int {
        guard cardCount > 0 else { return 0 }
        let card = OverlayCardMetrics.grid.size.height
        let room = availableContentHeight - Grid.topChrome - Grid.bottomInset
        let fits = Int(floor((room + Grid.gap) / (card + Grid.gap)))
        return max(1, min(fits, gridTotalRows))
    }

    private var gridPanelSize: CGSize {
        let metrics = OverlayCardMetrics.grid
        let columns = CGFloat(gridColumns)
        let rows = CGFloat(gridVisibleRows)
        return CGSize(
            width: columns * metrics.size.width
                + (columns - 1) * Grid.gap
                + Grid.horizontalInset * 2,
            height: Grid.topChrome
                + rows * metrics.size.height
                + (rows - 1) * Grid.gap
                + Grid.bottomInset
        )
    }

    // MARK: - List geometry

    private var listPanelSize: CGSize {
        let width = max(
            List.sidebarWidth + List.minDetailWidth,
            min(List.maxPanelWidth, availableContentWidth)
        )
        let height = max(
            List.minPanelHeight,
            min(List.maxPanelHeight, availableContentHeight)
        )
        return CGSize(width: width, height: height)
    }

    /// Rows that fit the sidebar.
    var listVisibleRows: Int {
        guard cardCount > 0 else { return 0 }
        let room = listPanelSize.height - List.sidebarTopChrome - List.verticalInset
        let fits = Int(floor((room + List.rowGap) / (List.rowHeight + List.rowGap)))
        return max(1, min(fits, cardCount))
    }

    /// Frame of the preview pane, in panel top-left coordinates.
    var listDetailFrame: CGRect {
        let panel = listPanelSize
        return CGRect(
            x: List.sidebarWidth + List.detailInset,
            y: List.detailInset + searchChrome,
            width: panel.width - List.sidebarWidth - List.detailInset * 2,
            height: panel.height - List.detailInset * 2
        )
    }

    // MARK: - Radial geometry

    /// The round arrangements' own layout, which owns every angle and radius in them.
    ///
    /// Non-nil only for `circular` and `spiral`. Both share this geometry and differ only in
    /// the winding it is given.
    var radial: RadialLayout? {
        guard let winding = style.radialWinding else { return nil }
        return RadialLayout(
            winding: winding,
            cardCount: cardCount,
            selectedIndex: selectedIndex,
            availableContentWidth: availableContentWidth,
            availableContentHeight: availableContentHeight
        )
    }

    /// How far the round arrangement has shrunk to seat every window. 1 for every other style.
    var radialScale: CGFloat { radial?.scale ?? 1 }

    /// A wedge paired with the entry it shows, in panel coordinates.
    ///
    /// `PositionedCard` carries the upright content box, because that is what the rest of
    /// this type is about — placing content and hit-testing rectangles. The wedge needs its
    /// angles and radii too in order to be drawn, and this is how the view gets them
    /// without recomputing geometry that would then be free to disagree.
    struct PositionedSeat: Equatable {
        let index: Int
        let seat: RadialLayout.Seat
    }

    /// Centre of the arrangement, in panel coordinates.
    var radialCentre: CGPoint {
        guard let radial else { return CGPoint(x: panelSize.width / 2, y: panelSize.height / 2) }
        let centre = radial.centre
        return CGPoint(x: centre.x, y: centre.y + searchChrome)
    }

    /// Every visible wedge, in panel coordinates.
    var radialSeats: [PositionedSeat] {
        guard let radial, cardCount > 0 else { return [] }
        let range = visibleRange
        return range.enumerated().map { offset, index in
            let seat = radial.seat(at: offset)
            guard searchChrome != 0 else { return PositionedSeat(index: index, seat: seat) }
            return PositionedSeat(
                index: index,
                seat: RadialLayout.Seat(
                    offset: seat.offset,
                    startAngle: seat.startAngle,
                    endAngle: seat.endAngle,
                    innerRadius: seat.innerRadius,
                    outerRadius: seat.outerRadius,
                    contentFrame: seat.contentFrame.offsetBy(dx: 0, dy: searchChrome)
                )
            )
        }
    }

    /// The hollow middle, in panel coordinates.
    ///
    /// Not dead space: it captions whichever window is under the pointer. Wedges are too
    /// narrow for a window title, so without this three windows of one application are
    /// three identical icons.
    var radialHubFrame: CGRect {
        guard let radial else { return .zero }
        return radial.hubFrame.offsetBy(dx: 0, dy: searchChrome)
    }

    // MARK: - Visible window

    /// How many cards this style can show at once. `nil` for the strip, which shows
    /// every card and scrolls by pixels instead.
    var capacity: Int? {
        switch style {
        case .strip: return nil
        case .grid: return gridColumns * gridVisibleRows
        case .list: return listVisibleRows
        case .circular, .spiral: return radial?.seats ?? cardCount
        }
    }

    /// The slice of entries currently on screen.
    var visibleRange: Range<Int> {
        guard cardCount > 0 else { return 0..<0 }
        guard let capacity, cardCount > capacity else { return 0..<cardCount }

        let start = clampedVisibleStart(visibleStart, capacity: capacity)
        return start..<min(cardCount, start + capacity)
    }

    /// Where the visible window should sit, moving as little as possible from where it
    /// already is.
    ///
    /// The same contract as `StripLayout.scrollOffset(keepingSelectionVisible:)`: an
    /// already-visible selection does not move anything, and a selection past either edge
    /// pulls the window along by the smallest amount that brings it back into view.
    func visibleStart(keepingSelectionVisible current: Int) -> Int {
        guard cardCount > 0, let capacity, cardCount > capacity else { return 0 }
        guard let selectedIndex else { return clampedVisibleStart(current, capacity: capacity) }

        var start = clampedVisibleStart(current, capacity: capacity)

        if style == .grid {
            // Grids page by whole rows, or the columns would shear sideways.
            let columns = gridColumns
            let rows = gridVisibleRows
            var firstRow = start / columns
            let selectedRow = selectedIndex / columns

            if selectedRow < firstRow {
                firstRow = selectedRow
            } else if selectedRow >= firstRow + rows {
                firstRow = selectedRow - rows + 1
            }
            start = firstRow * columns
        } else {
            if selectedIndex < start {
                start = selectedIndex
            } else if selectedIndex >= start + capacity {
                start = selectedIndex - capacity + 1
            }
        }

        return clampedVisibleStart(start, capacity: capacity)
    }

    private func clampedVisibleStart(_ proposed: Int, capacity: Int) -> Int {
        guard style == .grid else {
            return Self.clamp(proposed, lower: 0, upper: max(0, cardCount - capacity))
        }

        // Grids clamp by row, not by item. Clamping to `cardCount - capacity` and then
        // snapping down to a row boundary can land a whole row short of the end — with
        // 25 cards in a 4 × 3 grid it stops at card 24 of 25 — so the limit has to be
        // expressed as the last row that can be the top row.
        let columns = gridColumns
        let lastFirstRow = max(0, gridTotalRows - gridVisibleRows)
        let firstRow = Self.clamp(proposed / columns, lower: 0, upper: lastFirstRow)
        return firstRow * columns
    }

    /// Windows not currently on screen.
    ///
    /// The invariant that says paging is working, and the tests hold the windowing logic to
    /// it. Shown to the user in exactly one place — the round arrangements' hub — because
    /// those are the two styles whose whole argument is that everything is visible at once;
    /// see `RadialLayout`'s note on the cap. The grid and list page visibly by their nature
    /// and need no counter for it.
    var hiddenCount: Int { max(0, cardCount - visibleRange.count) }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), max(lower, upper))
    }

    // MARK: - Card frames

    /// Every card currently on screen, at rest, in panel top-left coordinates.
    ///
    /// - Parameter scrollOffset: the strip's pixel offset. Ignored by the other styles,
    ///   which page by whole items and are always at offset zero.
    func positionedCards(scrollOffset: CGFloat = 0) -> [PositionedCard] {
        contentCards(scrollOffset: scrollOffset).map { card in
            guard searchChrome != 0 else { return card }
            return PositionedCard(
                index: card.index,
                frame: card.frame.offsetBy(dx: 0, dy: searchChrome)
            )
        }
    }

    private func contentCards(scrollOffset: CGFloat) -> [PositionedCard] {
        guard cardCount > 0 else { return [] }

        let range = visibleRange
        switch style {
        case .strip:
            // The same arithmetic `StripLayout.cardIndex` inverts: content inset, minus
            // the scroll offset, vertically centred inside the scale headroom. Kept in
            // step by `OverlayLayoutTests.stripFramesAgreeWithStripHitTesting`.
            let metrics = OverlayCardMetrics.strip
            let headroom = StripLayout.cardSize.height * (StripLayout.selectedScale - 1)
            return range.map { index in
                PositionedCard(
                    index: index,
                    frame: CGRect(
                        x: StripLayout.contentInset
                            + CGFloat(index) * (metrics.size.width + StripLayout.cardSpacing)
                            - scrollOffset,
                        y: StripLayout.contentInset + headroom / 2,
                        width: metrics.size.width,
                        height: metrics.size.height
                    )
                )
            }

        case .grid:
            let metrics = OverlayCardMetrics.grid
            let columns = gridColumns
            return range.enumerated().map { offset, index in
                let row = offset / columns
                let column = offset % columns
                return PositionedCard(
                    index: index,
                    frame: CGRect(
                        x: Grid.horizontalInset + CGFloat(column) * (metrics.size.width + Grid.gap),
                        y: Grid.topChrome + CGFloat(row) * (metrics.size.height + Grid.gap),
                        width: metrics.size.width,
                        height: metrics.size.height
                    )
                )
            }

        case .list:
            return range.enumerated().map { offset, index in
                PositionedCard(
                    index: index,
                    frame: CGRect(
                        x: List.rowInset,
                        y: List.sidebarTopChrome + CGFloat(offset) * (List.rowHeight + List.rowGap),
                        width: List.sidebarWidth - List.rowInset * 2,
                        height: List.rowHeight
                    )
                )
            }

        case .circular, .spiral:
            // The upright content box of each wedge. The wedge shape itself lives in
            // `radialSeats`, and clicks are resolved by angle rather than against these
            // rectangles — adjacent wedges have heavily overlapping bounding boxes, so a
            // rectangle test would hand points to the wrong neighbour.
            guard let layout = radial else { return [] }
            return range.enumerated().map { offset, index in
                PositionedCard(index: index, frame: layout.seat(at: offset).contentFrame)
            }
        }
    }

    /// Where the close affordance sits on a card.
    ///
    /// Measured from the card's *drawn* frame, so it stays on the corner of the
    /// selected card even while that card is scaled up. The button itself does not
    /// scale — it is drawn as an overlay outside the scale transform — which keeps it a
    /// constant, comfortably clickable size.
    func closeButtonFrame(for card: PositionedCard, selectedScale: CGFloat) -> CGRect {
        let drawn = drawnFrame(for: card, selectedScale: selectedScale)
        let size = CloseButton.size

        switch style {
        case .list:
            // A row is too short for a top corner; the button rides the trailing edge.
            return CGRect(
                x: drawn.maxX - CloseButton.inset - size,
                y: drawn.midY - size / 2,
                width: size,
                height: size
            )
        case .circular, .spiral:
            // Not the content box's corner. That box holds the icon, so a button on its corner
            // sits on the icon — directly under the cursor that just hovered the wedge to select
            // it, which makes closing the window the easiest thing to do by accident.
            //
            // The wedge's own outer-trailing corner instead: the emptiest part of the seat, and
            // the analogue of a card's top-right corner. For the wedge at the top of the ring it
            // is literally that.
            return radialCloseButtonFrame(forCardIndex: card.index) ?? CGRect(
                x: drawn.maxX - CloseButton.inset - size,
                y: drawn.minY + CloseButton.inset,
                width: size,
                height: size
            )

        case .strip, .grid:
            return CGRect(
                x: drawn.maxX - CloseButton.inset - size,
                y: drawn.minY + CloseButton.inset,
                width: size,
                height: size
            )
        }
    }

    /// The close affordance on a wedge, tucked inside its outer-trailing corner.
    ///
    /// Positioned in polar terms because the wedge is: back from the clockwise edge by an arc's
    /// worth of inset, and in from the outer arc by the same. The radius is clamped so the button
    /// stays within the annulus however far the arrangement has been scaled down — on a crowded
    /// ring the wedge can be shallower than the button is tall, and poking outside the shape it
    /// belongs to would look like a detached dot.
    private func radialCloseButtonFrame(forCardIndex index: Int) -> CGRect? {
        guard let seat = radialSeats.first(where: { $0.index == index })?.seat else { return nil }

        let size = CloseButton.size
        let half = size / 2
        let inset = CloseButton.inset + half

        let radius = min(
            max(seat.innerRadius + half, seat.outerRadius - inset),
            seat.outerRadius - half
        )
        // Arc length converted to angle at the radius the button actually sits at, so the inset
        // looks the same on the inner turn as on the outer one.
        let angle = seat.endAngle - Double(inset / max(1, radius))
        let centre = radialCentre

        return CGRect(
            x: centre.x + radius * CGFloat(cos(angle)) - half,
            y: centre.y + radius * CGFloat(sin(angle)) - half,
            width: size,
            height: size
        )
    }

    /// The frame a card is actually drawn at, including the selection scale-up.
    ///
    /// Hit-testing uses this, so the enlarged edges of the selected card are clickable
    /// rather than being a dead border that silently does nothing.
    func drawnFrame(for card: PositionedCard, selectedScale: CGFloat) -> CGRect {
        guard card.index == selectedIndex, selectedScale > 1 else { return card.frame }
        let growX = card.frame.width * (selectedScale - 1) / 2
        let growY = card.frame.height * (selectedScale - 1) / 2
        return card.frame.insetBy(dx: -growX, dy: -growY)
    }

    // MARK: - Confirm region

    /// Area that commits the current selection rather than dismissing, in panel
    /// top-left coordinates.
    ///
    /// The list devotes a large area to a preview of the *selected* window, and the spiral
    /// names it in the hub. Treating a click on either as "clicked nothing, so close" is the
    /// wrong reading of the gesture — the user aimed at the window they want, and it happens
    /// to be rendered there instead of as a card.
    var confirmRegion: CGRect? {
        guard cardCount > 0 else { return nil }
        switch style {
        case .strip, .grid: return nil
        case .list: return listDetailFrame
        case .circular, .spiral: return radialHubFrame
        }
    }

    /// Whether a click at this AppKit panel point should switch to the selection.
    func commitsSelection(atPanelPoint pointInPanel: CGPoint) -> Bool {
        guard cardCount > 0 else { return false }
        switch style {
        case .strip, .grid:
            return false
        case .list:
            guard let region = confirmRegion else { return false }
            return region.contains(topLeftPoint(pointInPanel))
        case .circular, .spiral:
            // Circular, not the hub's bounding square. The square's corners already reached
            // into the first ring; the halo now paints a band just outside the circle, and a
            // click on that painted band over an empty slot has to confirm — it looks like
            // hub, not like desktop. Distance is from `radialCentre`, which already includes
            // search chrome, matching `radialHubFrame`.
            let point = topLeftPoint(pointInPanel)
            let centre = radialCentre
            let dx = point.x - centre.x
            let dy = point.y - centre.y
            let radius = (dx * dx + dy * dy).squareRoot()
            return radius <= radialHubFrame.width / 2 + HubChrome.haloReach
        }
    }

    // MARK: - Hit testing

    /// What a click at this point should do.
    ///
    /// One function rather than a chain of separate probes, because a click has exactly
    /// one meaning and the precedence between those meanings is the interesting part:
    /// the close affordance sits on top of a card, so it has to be tested before the
    /// card underneath it.
    enum HitTarget: Equatable {
        /// Switch to this window.
        case card(Int)
        /// Close this window and leave the overlay open.
        case close(Int)
        /// Switch to whatever is selected — the large preview in the list and radial
        /// styles.
        case confirmSelection
        /// Nothing actionable; dismiss.
        case background
    }

    func target(
        atPanelPoint pointInPanel: CGPoint,
        scrollOffset: CGFloat,
        selectedScale: CGFloat
    ) -> HitTarget {
        guard cardCount > 0 else { return .background }

        guard let index = cardIndex(
            atPanelPoint: pointInPanel,
            scrollOffset: scrollOffset,
            selectedScale: selectedScale
        ) else {
            return commitsSelection(atPanelPoint: pointInPanel) ? .confirmSelection : .background
        }

        // Restricted to the selected card because that is the only card the button is
        // drawn on. Accepting it on any card would create a small region on every card
        // that closes a window the user never saw highlighted — and since hover drives
        // selection, the card under the cursor is the selected one anyway.
        let point = topLeftPoint(pointInPanel)
        if index == selectedIndex,
           let card = positionedCards(scrollOffset: scrollOffset).first(where: { $0.index == index }),
           closeButtonFrame(for: card, selectedScale: selectedScale).contains(point) {
            return .close(index)
        }

        return .card(index)
    }

    /// Which entry sits under a point given in AppKit panel coordinates.
    ///
    /// Used for hover as well as clicks, which is why it resolves the close affordance
    /// to the card beneath it: moving onto the button must not drop the highlight.
    ///
    /// - Parameters:
    ///   - pointInPanel: point relative to the panel's bottom-left corner.
    ///   - scrollOffset: the strip's current pixel offset; ignored by other styles.
    ///   - selectedScale: the scale the selected card is drawn at, so its enlarged
    ///     edges hit-test as part of it.
    func cardIndex(
        atPanelPoint pointInPanel: CGPoint,
        scrollOffset: CGFloat,
        selectedScale: CGFloat
    ) -> Int? {
        guard cardCount > 0 else { return nil }

        if style == .strip {
            return strip.cardIndex(atPanelPoint: pointInPanel, scrollOffset: scrollOffset)
        }

        // Resolved by angle and radius rather than against the content boxes, so the whole
        // wedge is live right into its corners. This is the point of aiming at a ring: a
        // flick in roughly the right direction has to land, and the content box covers about
        // half of the wedge it sits in.
        if let radial {
            let point = topLeftPoint(pointInPanel)
            let inContent = CGPoint(x: point.x, y: point.y - searchChrome)
            guard let offset = radial.seatOffset(atContentPoint: inContent) else { return nil }
            let range = visibleRange
            let index = range.lowerBound + offset
            return range.contains(index) ? index : nil
        }

        let point = topLeftPoint(pointInPanel)
        let cards = positionedCards(scrollOffset: scrollOffset)

        // The selected card is drawn above its neighbours, so it wins where its
        // enlarged frame overlaps them.
        if let selected = cards.first(where: { $0.index == selectedIndex }),
           drawnFrame(for: selected, selectedScale: selectedScale).contains(point) {
            return selected.index
        }

        return cards.first { $0.frame.contains(point) }?.index
    }

    /// The one place AppKit's bottom-left origin becomes SwiftUI's top-left origin.
    private func topLeftPoint(_ pointInPanel: CGPoint) -> CGPoint {
        CGPoint(x: pointInPanel.x, y: panelSize.height - pointInPanel.y)
    }
}
