import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// The geometry behind the four overlay arrangements.
///
/// The properties asserted here are the ones whose failure the user actually feels:
/// a panel that overflows the display, a card that is drawn somewhere the click
/// hit-test does not know about, or a windowed arrangement that scrolls the selection
/// off screen. Rendering and hit-testing read the same rectangles from
/// `OverlayLayout`, so testing the rectangles tests both.
@Suite("Overlay layout")
struct OverlayLayoutTests {

    /// A generously sized 16:10 display, and a small one, so every style is exercised
    /// both with room to spare and against its limits.
    private static let roomy = CGSize(width: 1600, height: 900)
    private static let cramped = CGSize(width: 700, height: 480)

    /// Styles that page by whole items, as opposed to the strip's pixel scrolling.
    private static let positionedStyles: [OverlayLayoutStyle] = [.grid, .list, .spiral]

    private func layout(
        _ style: OverlayLayoutStyle,
        count: Int,
        selected: Int? = 0,
        available: CGSize = OverlayLayoutTests.roomy,
        visibleStart: Int = 0
    ) -> OverlayLayout {
        OverlayLayout(
            style: style,
            cardCount: count,
            selectedIndex: selected,
            availableContentWidth: available.width,
            availableContentHeight: available.height,
            visibleStart: visibleStart
        )
    }

    /// Convert a point in panel top-left coordinates to the AppKit bottom-left
    /// coordinates that hit-testing consumes, exactly as the panel does.
    private func appKitPoint(_ point: CGPoint, in layout: OverlayLayout) -> CGPoint {
        CGPoint(x: point.x, y: layout.panelSize.height - point.y)
    }

    private func hit(_ layout: OverlayLayout, atTopLeft point: CGPoint) -> Int? {
        layout.cardIndex(
            atPanelPoint: appKitPoint(point, in: layout),
            scrollOffset: 0,
            selectedScale: layout.style.selectedScale
        )
    }

    // MARK: - Panel sizing

    @Test(
        "Every style fits inside the space the display allows",
        arguments: OverlayLayoutStyle.allCases
    )
    func panelFitsAvailableSpace(style: OverlayLayoutStyle) {
        for available in [Self.roomy, Self.cramped] {
            for count in [1, 3, 9, 25] {
                let subject = layout(style, count: count, available: available)
                // Insets are excluded from the available size, so a panel is allowed to
                // exceed it by the panel chrome — but never by a whole card, which is
                // what an unbounded layout would do.
                let slack = StripLayout.contentInset * 2
                #expect(
                    subject.panelSize.width <= available.width + slack,
                    "\(style) width overflowed with \(count) cards at \(available)"
                )
                #expect(
                    subject.panelSize.height <= available.height + slack,
                    "\(style) height overflowed with \(count) cards at \(available)"
                )
            }
        }
    }

    /// The panel is sized once when it is presented and never resized while the user
    /// scrolls. If panel size depended on the selection, every wheel click would
    /// reshape the window under the cursor.
    @Test(
        "Panel size does not depend on which card is selected",
        arguments: OverlayLayoutStyle.allCases
    )
    func panelSizeIsIndependentOfSelection(style: OverlayLayoutStyle) {
        let reference = layout(style, count: 25, selected: 0).panelSize
        for selected in 0..<25 {
            let size = layout(style, count: 25, selected: selected).panelSize
            #expect(isClose(size.width, reference.width), "\(style) width moved at \(selected)")
            #expect(isClose(size.height, reference.height), "\(style) height moved at \(selected)")
        }
    }

    /// Requirement 1.8: the empty-state message needs a box, and it is the same box
    /// whichever style is configured.
    @Test("An empty list falls back to the empty-state panel", arguments: OverlayLayoutStyle.allCases)
    func emptyListUsesEmptyStatePanel(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 0, selected: nil)
        #expect(isClose(subject.panelSize.width, StripLayout.emptyStateWidth))
        #expect(subject.positionedCards().isEmpty)
        #expect(subject.hiddenCount == 0)
    }

    // MARK: - Hit-testing parity

    /// The centre of every drawn card must hit-test back to that card. This is the
    /// invariant that the stuck-drawer bug violated.
    @Test("Every drawn card is hittable at its centre", arguments: positionedStyles)
    func drawnCardsAreHittableAtCentre(style: OverlayLayoutStyle) {
        for count in [1, 2, 5, 9, 25] {
            for selected in [0, count / 2, count - 1] {
                let subject = layout(style, count: count, selected: selected)
                for card in subject.positionedCards() {
                    let hitIndex = hit(subject, atTopLeft: CGPoint(x: card.frame.midX, y: card.frame.midY))
                    #expect(
                        hitIndex == card.index,
                        "\(style): card \(card.index) of \(count) missed at its centre"
                    )
                }
            }
        }
    }

    /// Hit-testing returns the entry's index in the full list, not its seat number.
    /// Anything else would activate the wrong window once the arrangement is showing
    /// a window onto a longer list.
    @Test("Hit results index the full list, not the visible slice", arguments: positionedStyles)
    func hitResultsIndexTheFullList(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 25, selected: 20)
        let cards = subject.positionedCards()
        #expect(!cards.isEmpty)

        for card in cards {
            #expect(subject.visibleRange.contains(card.index))
            let hitIndex = hit(subject, atTopLeft: CGPoint(x: card.frame.midX, y: card.frame.midY))
            #expect(hitIndex == card.index)
        }
    }

    /// The selected card is drawn larger than it sits. Those extra pixels look like
    /// part of the card, so they have to behave like part of it.
    ///
    /// Only the styles that actually scale. The spiral is excluded because it deliberately
    /// does not: a wedge grown about the centre of its bounding box slides off the ring, so it
    /// marks the selection with fill and border and leaves the geometry alone.
    @Test("The enlarged edge of the selected card is clickable", arguments: [OverlayLayoutStyle.grid])
    func selectedCardScaledEdgeIsClickable(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 8, selected: 3)
        guard let selected = subject.positionedCards().first(where: { $0.index == 3 }) else {
            Issue.record("selected card was not placed")
            return
        }

        let drawn = subject.drawnFrame(for: selected, selectedScale: style.selectedScale)
        #expect(drawn.width > selected.frame.width)

        // A point in the scaled fringe: outside the resting frame, inside the drawn one.
        let fringeX = (selected.frame.maxX + drawn.maxX) / 2
        let point = CGPoint(x: fringeX, y: selected.frame.midY)
        #expect(!selected.frame.contains(point))
        #expect(drawn.contains(point))
        #expect(hit(subject, atTopLeft: point) == 3)
    }

    @Test("Points outside every card hit nothing", arguments: positionedStyles)
    func pointsOutsideCardsHitNothing(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 6, selected: 0)
        let panel = subject.panelSize

        // Just inside each panel corner. No style places a card in the extreme
        // corner: the grid and list have insets, and the radial ring is round.
        for point in [
            CGPoint(x: 2, y: 2),
            CGPoint(x: panel.width - 2, y: 2),
            CGPoint(x: 2, y: panel.height - 2),
            CGPoint(x: panel.width - 2, y: panel.height - 2),
        ] {
            #expect(hit(subject, atTopLeft: point) == nil, "\(style) claimed a corner point")
        }
    }

    @Test("Hit-testing an empty list finds nothing", arguments: OverlayLayoutStyle.allCases)
    func hitTestingEmptyListFindsNothing(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 0, selected: nil)
        #expect(hit(subject, atTopLeft: CGPoint(x: 10, y: 10)) == nil)
    }

    // MARK: - Strip parity

    /// The strip is the one style with two descriptions of where its cards are:
    /// `positionedCards`, which places the close affordance, and `StripLayout`, which
    /// hit-tests clicks. If they drifted, the close button would sit somewhere the click
    /// handler does not expect — the exact failure mode this suite exists to prevent.
    @Test("Strip frames agree with strip hit-testing at every scroll offset")
    func stripFramesAgreeWithStripHitTesting() {
        let subject = layout(.strip, count: 12, selected: 0, available: CGSize(width: 700, height: 400))

        for offset in stride(from: CGFloat(0), through: subject.maxScrollOffset, by: 31) {
            for card in subject.positionedCards(scrollOffset: offset) {
                let centre = CGPoint(x: card.frame.midX, y: card.frame.midY)
                // Only cards actually inside the viewport are hittable; the rest are
                // scrolled out and legitimately are not.
                guard card.frame.minX >= 0,
                      card.frame.maxX <= subject.panelSize.width else { continue }

                let hit = subject.cardIndex(
                    atPanelPoint: appKitPoint(centre, in: subject),
                    scrollOffset: offset,
                    selectedScale: OverlayLayoutStyle.strip.selectedScale
                )
                #expect(hit == card.index, "offset \(offset), card \(card.index)")
            }
        }
    }

    // MARK: - Close affordance

    /// The button must be inside the card it belongs to, or it would look like it
    /// belongs to a neighbour.
    @Test("The close button sits within its own card", arguments: OverlayLayoutStyle.allCases)
    func closeButtonSitsWithinItsCard(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 6, selected: 2)

        for card in subject.positionedCards() {
            let drawn = subject.drawnFrame(for: card, selectedScale: style.selectedScale)
            let button = subject.closeButtonFrame(for: card, selectedScale: style.selectedScale)

            #expect(drawn.contains(button), "\(style): close button escapes card \(card.index)")
            #expect(isClose(button.width, OverlayLayout.CloseButton.size))
            #expect(isClose(button.height, OverlayLayout.CloseButton.size))
        }
    }

    /// A click on the affordance must close, not switch — and only on the selected card,
    /// which is the only card that draws one.
    @Test("Clicking the close button closes rather than switches", arguments: OverlayLayoutStyle.allCases)
    func closeButtonTargetsClose(style: OverlayLayoutStyle) {
        let selected = 2
        let subject = layout(style, count: 6, selected: selected)

        guard let card = subject.positionedCards().first(where: { $0.index == selected }) else {
            Issue.record("\(style): selected card was not placed")
            return
        }
        let button = subject.closeButtonFrame(for: card, selectedScale: style.selectedScale)
        let centre = appKitPoint(CGPoint(x: button.midX, y: button.midY), in: subject)

        #expect(
            subject.target(atPanelPoint: centre, scrollOffset: 0, selectedScale: style.selectedScale)
                == .close(selected)
        )

        // Hover must still resolve to the card, or moving onto the button would drop the
        // highlight from the card it belongs to.
        #expect(
            subject.cardIndex(atPanelPoint: centre, scrollOffset: 0, selectedScale: style.selectedScale)
                == selected
        )
    }

    @Test("Only the selected card offers a close button", arguments: OverlayLayoutStyle.allCases)
    func onlySelectedCardOffersClose(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 6, selected: 2)

        for card in subject.positionedCards() where card.index != 2 {
            let button = subject.closeButtonFrame(for: card, selectedScale: style.selectedScale)
            let centre = appKitPoint(CGPoint(x: button.midX, y: button.midY), in: subject)
            let target = subject.target(
                atPanelPoint: centre,
                scrollOffset: 0,
                selectedScale: style.selectedScale
            )
            #expect(target == .card(card.index), "\(style): card \(card.index) offered a close button")
        }
    }

    /// The rest of a card must still switch, or the affordance would have swallowed the
    /// card's primary action.
    @Test("The card centre still switches", arguments: OverlayLayoutStyle.allCases)
    func cardCentreStillSwitches(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 6, selected: 2)

        for card in subject.positionedCards() {
            let centre = appKitPoint(CGPoint(x: card.frame.midX, y: card.frame.midY), in: subject)
            let target = subject.target(
                atPanelPoint: centre,
                scrollOffset: 0,
                selectedScale: style.selectedScale
            )
            #expect(target == .card(card.index), "\(style): card \(card.index) centre did not switch")
        }
    }

    @Test("An empty overlay has nothing to hit", arguments: OverlayLayoutStyle.allCases)
    func emptyOverlayHasNoTargets(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 0, selected: nil)
        #expect(
            subject.target(atPanelPoint: CGPoint(x: 10, y: 10), scrollOffset: 0, selectedScale: 1)
                == .background
        )
    }

    @Test("The preview area confirms the selection", arguments: [OverlayLayoutStyle.list, .spiral])
    func previewAreaConfirms(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 9, selected: 4)
        guard let region = subject.confirmRegion else {
            Issue.record("\(style) should offer a confirm region")
            return
        }
        let centre = appKitPoint(CGPoint(x: region.midX, y: region.midY), in: subject)
        #expect(
            subject.target(atPanelPoint: centre, scrollOffset: 0, selectedScale: style.selectedScale)
                == .confirmSelection
        )
    }

    // MARK: - Visible window

    /// A user scrolling to a window they cannot see has no way to know it is selected.
    ///
    /// The window is paged by `OverlayState`, so the invariant is stated the way the state
    /// applies it: given wherever the window currently sits, moving it to keep the
    /// selection visible must actually make the selection visible.
    @Test("The selection is always on screen", arguments: OverlayLayoutStyle.allCases)
    func selectionIsAlwaysVisible(style: OverlayLayoutStyle) {
        for count in [1, 7, 12, 25] {
            for selected in 0..<count {
                // From a fresh presentation, which starts at the top.
                let fresh = layout(style, count: count, selected: selected, available: Self.cramped)
                let paged = layout(
                    style,
                    count: count,
                    selected: selected,
                    available: Self.cramped,
                    visibleStart: fresh.visibleStart(keepingSelectionVisible: 0)
                )
                #expect(
                    paged.visibleRange.contains(selected),
                    "\(style): selection \(selected) of \(count) fell outside \(paged.visibleRange)"
                )

                // And from the far end, so paging backwards is covered too.
                let fromEnd = layout(
                    style,
                    count: count,
                    selected: selected,
                    available: Self.cramped,
                    visibleStart: fresh.visibleStart(keepingSelectionVisible: count)
                )
                #expect(
                    fromEnd.visibleRange.contains(selected),
                    "\(style): selection \(selected) paging back fell outside \(fromEnd.visibleRange)"
                )
            }
        }
    }

    /// The fix for the overlay shaking under the pointer.
    ///
    /// Hover selects whatever card is under the cursor. If selecting also moved the cards,
    /// a different card would land under the cursor, which would select that one instead —
    /// a feedback loop that showed up as the overlay flickering. So a selection that is
    /// already on screen must move nothing at all.
    @Test("Selecting a visible card moves nothing", arguments: positionedStyles)
    func selectingVisibleCardMovesNothing(style: OverlayLayoutStyle) {
        let count = 25
        let reference = layout(style, count: count, selected: 0, available: Self.cramped)
        guard let capacity = reference.capacity, count > capacity else {
            Issue.record("\(style) needs to be paging for this to mean anything")
            return
        }

        // Park the window somewhere in the middle, then select each card it is showing.
        let parked = reference.visibleStart(keepingSelectionVisible: 8)
        let visible = layout(
            style,
            count: count,
            selected: nil,
            available: Self.cramped,
            visibleStart: parked
        ).visibleRange

        for selected in visible {
            let subject = layout(
                style,
                count: count,
                selected: selected,
                available: Self.cramped,
                visibleStart: parked
            )
            #expect(
                subject.visibleStart(keepingSelectionVisible: parked) == parked,
                "\(style): selecting visible card \(selected) moved the window"
            )
            #expect(subject.positionedCards() == layout(
                style,
                count: count,
                selected: selected,
                available: Self.cramped,
                visibleStart: parked
            ).positionedCards())
        }
    }

    /// Walking off the edge should advance by the smallest amount that brings the
    /// selection back, not jump the window to centre it.
    @Test("Stepping past the edge pages by the minimum", arguments: positionedStyles)
    func steppingPastEdgePagesByMinimum(style: OverlayLayoutStyle) {
        let count = 25
        var start = 0

        // Walk the selection forward one card at a time, exactly as the scroll wheel does.
        for selected in 0..<count {
            let subject = layout(
                style,
                count: count,
                selected: selected,
                available: Self.cramped,
                visibleStart: start
            )
            let next = subject.visibleStart(keepingSelectionVisible: start)

            #expect(next >= start, "\(style): the window moved backwards while stepping forward")

            let paged = layout(
                style,
                count: count,
                selected: selected,
                available: Self.cramped,
                visibleStart: next
            )
            #expect(
                paged.visibleRange.contains(selected),
                "\(style): card \(selected) still off screen after paging"
            )
            start = next
        }

        // Having walked to the end, the window must be showing the end.
        let final = layout(
            style,
            count: count,
            selected: count - 1,
            available: Self.cramped,
            visibleStart: start
        )
        #expect(final.visibleRange.upperBound == count)
    }

    @Test("The visible window stays inside the list", arguments: OverlayLayoutStyle.allCases)
    func visibleWindowStaysInBounds(style: OverlayLayoutStyle) {
        for count in [1, 7, 12, 25] {
            for selected in 0..<count {
                let subject = layout(style, count: count, selected: selected, available: Self.cramped)
                let range = subject.visibleRange
                #expect(range.lowerBound >= 0)
                #expect(range.upperBound <= count)
                #expect(subject.hiddenCount == count - range.count)
                #expect(subject.positionedCards().count == range.count)
            }
        }
    }

    @Test("The strip keeps every card in range and scrolls instead")
    func stripKeepsEveryCardInRange() {
        let subject = layout(.strip, count: 25, selected: 24, available: Self.cramped)
        #expect(subject.visibleRange == 0..<25)
        #expect(subject.hiddenCount == 0)
        #expect(subject.isScrollable)
        #expect(subject.scrollOffset(keepingSelectionVisible: 0) > 0)
    }

    @Test("Only the strip scrolls by pixels", arguments: positionedStyles)
    func onlyStripScrollsByPixels(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 25, selected: 24, available: Self.cramped)
        #expect(!subject.isScrollable)
        #expect(isClose(subject.maxScrollOffset, 0))
        #expect(isClose(subject.scrollOffset(keepingSelectionVisible: 500), 0))
    }

    // MARK: - Grid

    @Test("The grid never exceeds four columns and fits the width it is given")
    func gridColumnsRespectWidthAndCap() {
        #expect(layout(.grid, count: 25).gridColumns == OverlayLayout.Grid.maxColumns)
        // Never more columns than there are windows to put in them.
        #expect(layout(.grid, count: 2).gridColumns == 2)

        let narrow = layout(.grid, count: 25, available: CGSize(width: 520, height: 900))
        let card = OverlayCardMetrics.grid.size.width
        let used = CGFloat(narrow.gridColumns) * card
            + CGFloat(narrow.gridColumns - 1) * OverlayLayout.Grid.gap
        #expect(used <= 520)
        #expect(narrow.gridColumns >= 1)
    }

    @Test("The grid shows every window when they all fit")
    func gridShowsEverythingWhenItFits() {
        let subject = layout(.grid, count: 8, available: CGSize(width: 1600, height: 1200))
        #expect(subject.visibleRange == 0..<8)
        #expect(subject.hiddenCount == 0)
    }

    @Test("Grid cards never overlap")
    func gridCardsDoNotOverlap() {
        let cards = layout(.grid, count: 12).positionedCards()
        #expect(cards.count > 1)
        for (offset, card) in cards.enumerated() {
            for other in cards[(offset + 1)...] {
                #expect(!card.frame.intersects(other.frame), "grid cards \(card.index) and \(other.index) overlap")
            }
        }
    }

    // MARK: - List

    @Test("List rows never overlap and stay inside the sidebar")
    func listRowsStayInSidebar() {
        let subject = layout(.list, count: 25)
        let cards = subject.positionedCards()
        #expect(cards.count > 1)

        for card in cards {
            #expect(card.frame.minX >= 0)
            #expect(card.frame.maxX <= OverlayLayout.List.sidebarWidth)
            #expect(card.frame.maxY <= subject.panelSize.height)
        }
        for (offset, card) in cards.enumerated() {
            for other in cards[(offset + 1)...] {
                #expect(!card.frame.intersects(other.frame))
            }
        }
    }

    @Test("The list preview pane sits beside the rows, never over them")
    func listPreviewDoesNotOverlapRows() {
        let subject = layout(.list, count: 25)
        let detail = subject.listDetailFrame
        #expect(detail.minX >= OverlayLayout.List.sidebarWidth)
        #expect(detail.width >= 300)
        #expect(detail.maxX <= subject.panelSize.width)
        #expect(detail.maxY <= subject.panelSize.height)

        for card in subject.positionedCards() {
            #expect(!card.frame.intersects(detail))
        }
    }

    // MARK: - Spiral

    /// Twelve seats to a turn, two turns, and then it pages like every other style.
    @Test("The spiral seats up to two full turns")
    func spiralSeatsTwoTurns() {
        #expect(layout(.spiral, count: 25, available: Self.roomy).spiral.seats == SpiralLayout.maxSeats)
        #expect(layout(.spiral, count: 3).spiral.seats == 3)
        #expect(layout(.spiral, count: 1).spiral.seats == 1)
        // Comfortably more than the eight-seat ring this replaced.
        #expect(SpiralLayout.maxSeats == SpiralLayout.seatsPerTurn * 2)
    }

    /// The arc grows with the window count instead of the seats spreading apart.
    ///
    /// This is the difference between a spiral and the ring it replaces, and it is what makes
    /// three windows read as three wedges at the top rather than as three lonely cards at
    /// 120° to each other.
    @Test("Adding windows lengthens the arc and leaves each seat where it was")
    func spiralArcGrowsWithCount() {
        let three = layout(.spiral, count: 3).spiral
        let eight = layout(.spiral, count: 8).spiral

        #expect(isClose(three.seat(at: 0).startAngle, eight.seat(at: 0).startAngle))
        #expect(isClose(three.seat(at: 2).startAngle, eight.seat(at: 2).startAngle))

        // Each seat spans the same angle whatever the count.
        for seat in eight.visibleSeats {
            #expect(isClose(seat.endAngle - seat.startAngle, SpiralLayout.sweep - SpiralLayout.wedgeGap))
        }
    }

    /// The first seat is at the top, and the run proceeds clockwise from there.
    @Test("The first seat is at twelve o'clock and the arc turns clockwise")
    func spiralStartsAtTheTop() {
        let subject = layout(.spiral, count: 6).spiral
        let first = subject.seat(at: 0)
        let second = subject.seat(at: 1)

        // Straight up, allowing for the half-gap inset on the leading edge.
        #expect(first.midAngle < SpiralLayout.startAngle + SpiralLayout.sweep)
        #expect(first.midAngle > SpiralLayout.startAngle)
        #expect(second.midAngle > first.midAngle)

        // y grows downward here, so clockwise means the second seat sits right of the first
        // and lower than it.
        #expect(second.contentFrame.midX > first.contentFrame.midX)
        #expect(second.contentFrame.midY > first.contentFrame.midY)
    }

    /// Each seat sits a little further out than the one before, and a full turn later the
    /// spiral has moved out by exactly one ring thickness plus its gap — which is what stops
    /// the second turn from landing on top of the first.
    @Test("Turns nest without overlapping")
    func spiralTurnsDoNotOverlap() {
        let subject = layout(.spiral, count: SpiralLayout.maxSeats, available: Self.roomy).spiral

        for offset in 1..<subject.seats {
            #expect(subject.seat(at: offset).innerRadius > subject.seat(at: offset - 1).innerRadius)
        }

        for offset in 0..<(subject.seats - SpiralLayout.seatsPerTurn) {
            let inner = subject.seat(at: offset)
            let outer = subject.seat(at: offset + SpiralLayout.seatsPerTurn)
            // Same slot, so they share an angular span and only the radius keeps them apart.
            #expect(isClose(inner.startAngle, outer.startAngle))
            #expect(outer.innerRadius >= inner.outerRadius)
            #expect(isClose(outer.innerRadius - inner.outerRadius, SpiralLayout.turnGap))
        }
    }

    @Test("A cramped display winds fewer turns rather than overflowing")
    func spiralShrinksToFit() {
        let roomy = layout(.spiral, count: 25, available: Self.roomy)
        let cramped = layout(.spiral, count: 25, available: Self.cramped)

        #expect(roomy.spiral.seats == SpiralLayout.maxSeats)
        #expect(cramped.spiral.seats < roomy.spiral.seats)
        #expect(cramped.spiral.seats >= SpiralLayout.minimumSeats)
        #expect(cramped.panelSize.width < roomy.panelSize.width)
        // The windows that lost a seat are still reachable, and still counted.
        #expect(cramped.hiddenCount == 25 - cramped.spiral.seats)
    }

    @Test("Wedge contents stay inside the panel", arguments: [1, 4, 12, 25])
    func spiralContentStaysInsidePanel(count: Int) {
        for available in [Self.roomy, Self.cramped, CGSize(width: 1100, height: 620)] {
            let subject = layout(.spiral, count: count, available: available)
            for card in subject.positionedCards() {
                #expect(card.frame.minX >= -0.001)
                #expect(card.frame.minY >= -0.001)
                #expect(card.frame.maxX <= subject.panelSize.width + 0.001)
                #expect(card.frame.maxY <= subject.panelSize.height + 0.001)
            }
        }
    }

    /// The content box has to sit inside the wedge that draws it, or a label overhangs a
    /// neighbour and the icon drifts out of the shape it is supposed to be in.
    @Test("Each content box sits within its own wedge")
    func spiralContentSitsInsideItsWedge() {
        let subject = layout(.spiral, count: SpiralLayout.maxSeats, available: Self.roomy).spiral

        for seat in subject.visibleSeats {
            // Every corner of the box must be in the wedge's annulus and angular span.
            for corner in [
                CGPoint(x: seat.contentFrame.minX, y: seat.contentFrame.minY),
                CGPoint(x: seat.contentFrame.maxX, y: seat.contentFrame.minY),
                CGPoint(x: seat.contentFrame.minX, y: seat.contentFrame.maxY),
                CGPoint(x: seat.contentFrame.maxX, y: seat.contentFrame.maxY),
            ] {
                #expect(
                    subject.seatOffset(atContentPoint: corner) == seat.offset,
                    "a corner of seat \(seat.offset)'s content box fell outside it"
                )
            }
        }
    }

    /// The spiral is the only arrangement whose panel is driven by how many seats it winds, so
    /// it is the only one that can grow itself off the screen. Checked against the content box
    /// a real display actually offers, after `StripLayout`'s width and height fractions.
    @Test("The spiral panel fits the display it is drawn on")
    func spiralPanelFitsRealDisplays() {
        let displays = [
            CGSize(width: 1512, height: 982),   // 14" built-in
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1440, height: 900),
            CGSize(width: 3440, height: 1440),
            CGSize(width: 1280, height: 800),
        ]

        for display in displays {
            let available = CGSize(
                width: display.width * StripLayout.maxWidthFraction,
                height: display.height * StripLayout.maxHeightFraction
            )
            for count in [1, 4, 9, 16, 25, 40] {
                let subject = layout(.spiral, count: count, available: available)
                let panel = subject.panelSize

                #expect(
                    panel.width <= available.width + 0.001,
                    "\(count) windows on \(display) needed \(panel.width)pt of \(available.width)"
                )
                #expect(
                    panel.height <= available.height + 0.001,
                    "\(count) windows on \(display) needed \(panel.height)pt of \(available.height)"
                )
                // And it still seats a useful number rather than collapsing to the floor.
                #expect(subject.spiral.seats >= min(count, SpiralLayout.minimumSeats))
            }
        }
    }

    /// Wedges are the biggest targets of any arrangement, which is the trade for showing one
    /// line of text. Worth pinning, since it is the reason 45° seats were chosen over 30°.
    @Test("A wedge is a large target")
    func spiralWedgesAreLargeTargets() {
        let subject = layout(.spiral, count: 16, available: Self.roomy).spiral

        for seat in subject.visibleSeats {
            let arc = seat.midRadius * CGFloat(seat.endAngle - seat.startAngle)
            // Comfortably larger than a strip card's 208 × 152 in the dimension that matters
            // for aiming: depth along the flick.
            #expect(seat.outerRadius - seat.innerRadius == SpiralLayout.ringThickness)
            #expect(arc >= 100, "seat \(seat.offset) was only \(arc)pt of arc")
        }
    }

    // MARK: - Spiral hit testing

    /// The whole wedge is live, not just the box its contents sit in. This is the point of
    /// aiming at a ring: a flick in roughly the right direction has to land.
    @Test("Every part of a wedge selects it")
    func spiralWedgeIsLiveThroughout() {
        let subject = layout(.spiral, count: SpiralLayout.maxSeats, available: Self.roomy)
        let spiral = subject.spiral

        for seat in spiral.visibleSeats {
            // Sample across the wedge rather than only at its middle: near both angular
            // edges, and near both the inner and outer arc.
            for angleFraction in [0.06, 0.3, 0.5, 0.7, 0.94] {
                for radiusFraction in [0.06, 0.5, 0.94] {
                    let angle = seat.startAngle + (seat.endAngle - seat.startAngle) * angleFraction
                    let radius = seat.innerRadius
                        + (seat.outerRadius - seat.innerRadius) * CGFloat(radiusFraction)
                    let point = CGPoint(
                        x: spiral.centre.x + radius * CGFloat(cos(angle)),
                        y: spiral.centre.y + radius * CGFloat(sin(angle))
                    )
                    #expect(
                        hit(subject, atTopLeft: point) == seat.offset,
                        "seat \(seat.offset) missed at angle \(angleFraction), radius \(radiusFraction)"
                    )
                }
            }
        }
    }

    /// The hollow middle is not a card. It confirms the selection instead, because it is
    /// where the selected window is named.
    @Test("The hub selects no card and confirms instead")
    func spiralHubIsNotACard() {
        let subject = layout(.spiral, count: 9, selected: 4)
        let centre = CGPoint(x: subject.spiralCentre.x, y: subject.spiralCentre.y)

        #expect(hit(subject, atTopLeft: centre) == nil)
        #expect(subject.commitsSelection(atPanelPoint: appKitPoint(centre, in: subject)))
        #expect(
            subject.target(
                atPanelPoint: appKitPoint(centre, in: subject),
                scrollOffset: 0,
                selectedScale: OverlayLayoutStyle.spiral.selectedScale
            ) == .confirmSelection
        )
    }

    /// Beyond the outermost turn there is nothing, so a click there dismisses.
    @Test("Points outside the outermost turn hit nothing")
    func spiralOutsideTheArcHitsNothing() {
        let subject = layout(.spiral, count: 12, available: Self.roomy)
        let spiral = subject.spiral
        let beyond = spiral.outerRadius + 6

        for step in 0..<12 {
            let angle = Double(step) * .pi / 6
            let point = CGPoint(
                x: spiral.centre.x + beyond * CGFloat(cos(angle)),
                y: spiral.centre.y + beyond * CGFloat(sin(angle))
            )
            #expect(hit(subject, atTopLeft: point) == nil)
        }
    }

    /// A paged spiral maps seat positions onto the entries actually on screen, not onto
    /// entry zero — otherwise hovering the top wedge would select a window that is not there.
    @Test("A paged spiral hit-tests to the visible entries")
    func spiralHitTestingFollowsThePage() {
        let subject = layout(
            .spiral,
            count: 40,
            selected: 30,
            available: Self.roomy,
            visibleStart: 16
        )
        let range = subject.visibleRange
        #expect(!range.contains(0))

        let spiral = subject.spiral
        for seat in spiral.visibleSeats {
            let point = CGPoint(
                x: spiral.centre.x + seat.midRadius * CGFloat(cos(seat.midAngle)),
                y: spiral.centre.y + seat.midRadius * CGFloat(sin(seat.midAngle))
            )
            let index = hit(subject, atTopLeft: point)
            #expect(index == range.lowerBound + seat.offset)
            #expect(index.map { range.contains($0) } == true)
        }
    }

    /// Angles are compared modulo a full turn, so a seat that wraps past 2π still matches.
    @Test("Angle containment survives wrapping")
    func angleContainmentWraps() {
        let start = 1.5 * Double.pi
        let end = start + Double.pi / 6

        #expect(SpiralLayout.angle(start + 0.05, isWithin: start, and: end))
        // The same direction expressed a full turn away.
        #expect(SpiralLayout.angle(start + 0.05 - 2 * .pi, isWithin: start, and: end))
        #expect(!SpiralLayout.angle(start - 0.05, isWithin: start, and: end))
        #expect(!SpiralLayout.angle(end + 0.05, isWithin: start, and: end))
    }

    // MARK: - Confirm region

    @Test("Clicking the preview switches, in the styles that have one")
    func previewRegionCommitsSelection() {
        for style in [OverlayLayoutStyle.list, .spiral] {
            let subject = layout(style, count: 9, selected: 4)
            guard let region = subject.confirmRegion else {
                Issue.record("\(style) should offer a confirm region")
                continue
            }
            let centre = appKitPoint(CGPoint(x: region.midX, y: region.midY), in: subject)
            #expect(subject.commitsSelection(atPanelPoint: centre))
        }
    }

    @Test("Styles without a preview have no confirm region")
    func stylesWithoutPreviewHaveNoConfirmRegion() {
        for style in [OverlayLayoutStyle.strip, .grid] {
            let subject = layout(style, count: 9, selected: 4)
            #expect(subject.confirmRegion == nil)
            #expect(!subject.commitsSelection(atPanelPoint: CGPoint(x: 10, y: 10)))
        }
    }

    @Test("An empty list has nothing to confirm", arguments: OverlayLayoutStyle.allCases)
    func emptyListHasNoConfirmRegion(style: OverlayLayoutStyle) {
        #expect(layout(style, count: 0, selected: nil).confirmRegion == nil)
    }

    // MARK: - Style metadata

    @Test("Raw values are stable for persistence")
    func rawValuesAreStable() {
        #expect(OverlayLayoutStyle.strip.rawValue == 0)
        #expect(OverlayLayoutStyle.grid.rawValue == 1)
        #expect(OverlayLayoutStyle.list.rawValue == 2)
        #expect(OverlayLayoutStyle.spiral.rawValue == 3)
        #expect(OverlayLayoutStyle.allCases.count == 4)
    }

    @Test("Every style is presentable and distinct")
    func everyStyleIsPresentable() {
        let names = Set(OverlayLayoutStyle.allCases.map(\.displayName))
        let shortNames = Set(OverlayLayoutStyle.allCases.map(\.shortName))
        #expect(names.count == OverlayLayoutStyle.allCases.count)
        #expect(shortNames.count == OverlayLayoutStyle.allCases.count)

        for style in OverlayLayoutStyle.allCases {
            #expect(!style.explanation.isEmpty)
        }
    }

    /// Requirement 3.3 pins the selected scale to the 1.05–1.10 band for the strip.
    /// The other styles may sit below it, but none may exceed it.
    @Test("Selection scales stay within the specified band")
    func selectionScalesAreReasonable() {
        #expect(OverlayLayoutStyle.strip.selectedScale == StripLayout.selectedScale)
        for style in OverlayLayoutStyle.allCases {
            #expect(style.selectedScale >= 1.0)
            #expect(style.selectedScale <= 1.10)
        }
    }

    /// Cards already carry a fill, a border and a shadow, so a plate behind them is a
    /// container around things that are already containers. Only the list needs one,
    /// because its unselected rows have no fill of their own.
    @Test("Only the list draws a plate behind its cards")
    func onlyListDrawsABackdrop() {
        #expect(!OverlayLayoutStyle.strip.drawsBackdrop)
        #expect(!OverlayLayoutStyle.grid.drawsBackdrop)
        #expect(!OverlayLayoutStyle.spiral.drawsBackdrop)
        #expect(OverlayLayoutStyle.list.drawsBackdrop)
    }

    @Test("Large panels are centred on the display, aimed ones follow the cursor")
    func placementAnchorsMatchTheStyle() {
        #expect(OverlayLayoutStyle.strip.placementAnchor == .cursor)
        #expect(OverlayLayoutStyle.spiral.placementAnchor == .cursor)
        #expect(OverlayLayoutStyle.grid.placementAnchor == .displayCentre)
        #expect(OverlayLayoutStyle.list.placementAnchor == .displayCentre)
    }

    @Test(
        "Card metrics leave room for the metadata",
        arguments: OverlayLayoutStyle.allCases, OverlayViewMode.allCases
    )
    func cardMetricsLeaveRoomForMetadata(style: OverlayLayoutStyle, viewMode: OverlayViewMode) {
        let metrics = style.cardMetrics(for: viewMode)
        #expect(metrics.size.width > 0)
        #expect(metrics.artworkHeight > 0)
        #expect(metrics.artworkHeight < metrics.size.height)
        #expect(metrics.metadataHeight > 0)
    }

    /// The whole reason Icon View needed no geometry changes: every frame in this file is
    /// derived from card *size*, so if sizes match across modes, all of it is shared. Guards
    /// against a future tweak to an icon card's size silently altering Window View's layout.
    @Test("Card sizes are identical in both view modes", arguments: OverlayLayoutStyle.allCases)
    func cardSizesMatchAcrossViewModes(style: OverlayLayoutStyle) {
        #expect(style.cardMetrics(for: .window).size == style.cardMetrics(for: .icon).size)
    }
}
