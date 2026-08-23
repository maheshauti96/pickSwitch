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
    private static let positionedStyles: [OverlayLayoutStyle] = [.grid, .list, .circular]

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

    @Test("The preview area confirms the selection", arguments: [OverlayLayoutStyle.list, .circular])
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

    // MARK: - Circular and spiral

    /// Both round arrangements, since almost everything about them is shared.
    private static let radialStyles: [OverlayLayoutStyle] = [.circular, .spiral]

    /// The round geometry on its own, built directly so a test can name a winding without
    /// going through a style.
    private func radial(
        _ winding: RadialLayout.Winding,
        count: Int,
        selected: Int? = 0,
        available: CGSize = OverlayLayoutTests.roomy
    ) -> RadialLayout {
        RadialLayout(
            winding: winding,
            cardCount: count,
            selectedIndex: selected,
            availableContentWidth: available.width,
            availableContentHeight: available.height
        )
    }

    @Test("Both round styles have a winding, and no other style does")
    func onlyRoundStylesWind() {
        #expect(OverlayLayoutStyle.circular.radialWinding == .circular)
        #expect(OverlayLayoutStyle.spiral.radialWinding == .spiral)
        #expect(OverlayLayoutStyle.strip.radialWinding == nil)
        #expect(OverlayLayoutStyle.grid.radialWinding == nil)
        #expect(OverlayLayoutStyle.list.radialWinding == nil)
        // The one thing that follows from being round: a wedge cannot hold a screenshot.
        #expect(!OverlayLayoutStyle.circular.canShowThumbnails)
        #expect(!OverlayLayoutStyle.spiral.canShowThumbnails)
    }

    /// The persisted value that has always meant "the arrangement with wedges" keeps meaning the
    /// behaviour it shipped with, which is the concentric one. If this flips, everyone using it
    /// silently gets a different arrangement on upgrade.
    @Test("Raw value 3 is the circular winding")
    func rawValueThreeIsCircular() {
        #expect(OverlayLayoutStyle(rawValue: 3) == .circular)
        #expect(OverlayLayoutStyle(rawValue: 4) == .spiral)
    }

    // MARK: - Seating every window

    /// The point of the round arrangements: no paging. Every window gets a seat, and the
    /// arrangement shrinks to make room.
    @Test("Every window is seated at any realistic count", arguments: radialStyles)
    func everyWindowIsSeated(style: OverlayLayoutStyle) {
        let displays = [
            CGSize(width: 1512, height: 982),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1440, height: 900),
            CGSize(width: 1280, height: 800),
        ]

        for display in displays {
            let available = CGSize(
                width: display.width * StripLayout.maxWidthFraction,
                height: display.height * StripLayout.maxHeightFraction
            )
            // Up to the largest list the settings will produce.
            for count in [1, 5, 8, 9, 16, 17, SettingsStore.historyDepthRange.upperBound] {
                let subject = layout(style, count: count, available: available)
                #expect(
                    subject.visibleRange.count == count,
                    "\(style) paged \(count) windows on \(display)"
                )
                #expect(subject.hiddenCount == 0)
                #expect(subject.positionedCards().count == count)
            }
        }
    }

    /// Shrinking is what buys that, so it has to actually happen — and stay within bounds.
    @Test("The arrangement shrinks as the count grows", arguments: RadialLayout.Winding.allCases)
    func scaleShrinksWithCount(winding: RadialLayout.Winding) {
        let cramped = CGSize(width: 1300, height: 805)
        let few = radial(winding, count: 4, available: cramped)
        let many = radial(winding, count: 25, available: cramped)

        // A handful of windows gets the arrangement at its intended size, never a blown-up one.
        #expect(few.scale == 1)
        #expect(many.scale < few.scale)
        #expect(many.scale >= RadialLayout.minimumScale)

        // Monotonic: adding a window never makes the arrangement bigger.
        var previous: CGFloat = 1.001
        for count in 1...25 {
            let scale = radial(winding, count: count, available: cramped).scale
            #expect(scale <= previous + 0.0001, "\(count) windows scaled up")
            previous = scale
        }
    }

    @Test("The panel always fits the display", arguments: radialStyles)
    func radialPanelFitsTheDisplay(style: OverlayLayoutStyle) {
        for display in [
            CGSize(width: 1512, height: 982),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1280, height: 800),
        ] {
            let available = CGSize(
                width: display.width * StripLayout.maxWidthFraction,
                height: display.height * StripLayout.maxHeightFraction
            )
            for count in [1, 8, 16, 25] {
                let panel = layout(style, count: count, available: available).panelSize
                #expect(panel.width <= available.width + 0.001, "\(style)/\(count) on \(display)")
                #expect(panel.height <= available.height + 0.001, "\(style)/\(count) on \(display)")
            }
        }
    }

    /// Paging is the floor, not the plan: it only appears once shrinking has bottomed out, which
    /// takes a count far beyond any window list.
    @Test("Paging returns only past the shrink floor", arguments: RadialLayout.Winding.allCases)
    func pagingIsTheLastResort(winding: RadialLayout.Winding) {
        let tiny = CGSize(width: 520, height: 400)
        let subject = radial(winding, count: 200, available: tiny)

        // Seats were given up, but only after shrinking had run out of room.
        #expect(subject.seats < 200)
        #expect(subject.scale >= RadialLayout.minimumScale)
        // Still a whole turn at minimum, so it never degenerates into a fragment of an arc.
        #expect(subject.seats >= RadialLayout.seatsPerTurn)

        // And it seats as many as the floor allows: one more would have to shrink past it.
        let oneMore = radial(winding, count: subject.seats + 1, available: tiny)
        #expect(oneMore.seats == subject.seats)
    }

    // MARK: - Shared shape

    /// Seats have a fixed angular width in both windings, which is what makes the arc lengthen
    /// as windows are added rather than the seats spreading apart.
    @Test("Seat sweep is fixed and the run starts at the top", arguments: RadialLayout.Winding.allCases)
    func seatsAreFixedWidthFromTheTop(winding: RadialLayout.Winding) {
        for count in [3, 8, 16] {
            let subject = radial(winding, count: count)
            for seat in subject.visibleSeats {
                #expect(isClose(
                    seat.endAngle - seat.startAngle,
                    RadialLayout.sweep - RadialLayout.wedgeGap
                ))
            }

            let first = subject.seat(at: 0)
            #expect(first.midAngle > RadialLayout.startAngle)
            #expect(first.midAngle < RadialLayout.startAngle + RadialLayout.sweep)

            guard count > 1 else { continue }
            // y grows downward here, so clockwise puts the second seat right of and below the
            // first.
            let second = subject.seat(at: 1)
            #expect(second.midAngle > first.midAngle)
            #expect(second.contentFrame.midX > first.contentFrame.midX)
            #expect(second.contentFrame.midY > first.contentFrame.midY)
        }
    }

    /// Adding windows does not move the seats already placed — the arc grows at its open end.
    /// Only true while the scale holds, which is why this uses a count that does not shrink.
    @Test("Adding a window leaves the existing seats' angles alone", arguments: RadialLayout.Winding.allCases)
    func addingAWindowKeepsAngles(winding: RadialLayout.Winding) {
        let three = radial(winding, count: 3)
        let six = radial(winding, count: 6)
        for offset in 0..<3 {
            #expect(isClose(three.seat(at: offset).startAngle, six.seat(at: offset).startAngle))
        }
    }

    /// The content box has to sit inside the wedge that draws it, or a label overhangs a
    /// neighbour and the icon drifts out of the shape it belongs to. Checked at both windings and
    /// across the scale range, since the box is derived from the scaled geometry.
    @Test("Each content box sits within its own wedge", arguments: RadialLayout.Winding.allCases)
    func contentSitsInsideItsWedge(winding: RadialLayout.Winding) {
        for available in [Self.roomy, CGSize(width: 1300, height: 805), CGSize(width: 900, height: 620)] {
            for count in [1, 8, 16, 25] {
                let subject = radial(winding, count: count, available: available)
                for seat in subject.visibleSeats {
                    for corner in [
                        CGPoint(x: seat.contentFrame.minX, y: seat.contentFrame.minY),
                        CGPoint(x: seat.contentFrame.maxX, y: seat.contentFrame.minY),
                        CGPoint(x: seat.contentFrame.minX, y: seat.contentFrame.maxY),
                        CGPoint(x: seat.contentFrame.maxX, y: seat.contentFrame.maxY),
                    ] {
                        #expect(
                            subject.seatOffset(atContentPoint: corner) == seat.offset,
                            "\(winding): corner of seat \(seat.offset) outside it, \(count) windows at \(available)"
                        )
                    }
                }
            }
        }
    }

    @Test("Wedge contents stay inside the panel", arguments: radialStyles)
    func radialContentStaysInsidePanel(style: OverlayLayoutStyle) {
        for available in [Self.roomy, Self.cramped, CGSize(width: 1100, height: 620)] {
            for count in [1, 4, 12, 25] {
                let subject = layout(style, count: count, available: available)
                for card in subject.positionedCards() {
                    #expect(card.frame.minX >= -0.001)
                    #expect(card.frame.minY >= -0.001)
                    #expect(card.frame.maxX <= subject.panelSize.width + 0.001)
                    #expect(card.frame.maxY <= subject.panelSize.height + 0.001)
                }
            }
        }
    }

    // MARK: - Circular winding

    /// A turn is a true annulus: every seat in it shares both arcs.
    ///
    /// This is what makes the circular winding read as organised. The spiral deliberately does
    /// not do it, which is the whole distinction between the two.
    @Test("Circular: every seat in a turn shares the same arcs")
    func circularTurnsAreConcentric() {
        let subject = radial(.circular, count: RadialLayout.seatsPerTurn * 2)

        let byTurn = Dictionary(grouping: subject.visibleSeats) {
            RadialLayout.turn(ofSeat: $0.offset)
        }
        #expect(byTurn.count == 2)

        for (turn, seats) in byTurn {
            #expect(seats.count == RadialLayout.seatsPerTurn, "turn \(turn) was not full")
            let inner = seats[0].innerRadius
            let outer = seats[0].outerRadius
            for seat in seats {
                #expect(seat.innerRadius == inner, "seat \(seat.offset) broke its turn's inner arc")
                #expect(seat.outerRadius == outer, "seat \(seat.offset) broke its turn's outer arc")
            }
        }
    }

    /// Turns step outward by exactly one thickness plus one gap, so they nest without touching
    /// and without leaving a stripe of dead space between them.
    @Test("Circular: turns nest with a uniform gap")
    func circularTurnsNestUniformly() {
        let subject = radial(.circular, count: RadialLayout.seatsPerTurn * 2)

        for offset in 0..<(subject.seats - RadialLayout.seatsPerTurn) {
            let inner = subject.seat(at: offset)
            let outer = subject.seat(at: offset + RadialLayout.seatsPerTurn)
            // Same slot, so only the radius separates them — which means they line up radially
            // too, and the arrangement has columns rather than a scatter.
            #expect(isClose(inner.startAngle, outer.startAngle))
            #expect(isClose(inner.endAngle, outer.endAngle))
            #expect(outer.innerRadius >= inner.outerRadius)
            #expect(isClose(outer.innerRadius - inner.outerRadius, subject.turnGap))
        }
    }

    /// Every icon in a turn is the same distance from the middle, so they fall on one circle.
    @Test("Circular: contents of a turn sit on a common circle")
    func circularContentsShareARadius() {
        let subject = radial(.circular, count: RadialLayout.seatsPerTurn * 2)
        let centre = subject.centre

        for (turn, seats) in Dictionary(grouping: subject.visibleSeats, by: {
            RadialLayout.turn(ofSeat: $0.offset)
        }) {
            let distances = seats.map { seat in
                hypot(seat.contentFrame.midX - centre.x, seat.contentFrame.midY - centre.y)
            }
            guard let first = distances.first else { continue }
            for distance in distances {
                #expect(isClose(distance, first, tolerance: 0.01), "turn \(turn) icons drifted")
            }
        }
    }

    /// Angular gaps are identical all the way round, so no join looks tighter than another.
    @Test("Circular: the gap between neighbouring wedges is uniform")
    func circularGapsAreUniform() {
        let subject = radial(.circular, count: RadialLayout.seatsPerTurn * 2)

        for turn in 0..<2 {
            let base = turn * RadialLayout.seatsPerTurn
            for slot in 1..<RadialLayout.seatsPerTurn {
                let previous = subject.seat(at: base + slot - 1)
                let next = subject.seat(at: base + slot)
                #expect(isClose(next.startAngle - previous.endAngle, RadialLayout.wedgeGap))
            }
        }
    }

    // MARK: - Spiral winding

    /// Every seat sits a little further out than the last. That is the definition of the winding,
    /// and it is exactly what the circular one refuses to do.
    @Test("Spiral: the radius advances with every seat")
    func spiralAdvancesPerSeat() {
        let subject = radial(.spiral, count: RadialLayout.seatsPerTurn * 2)

        for offset in 1..<subject.seats {
            #expect(subject.seat(at: offset).innerRadius > subject.seat(at: offset - 1).innerRadius)
        }

        // One full turn out is one thickness plus one gap, which is what keeps the turns from
        // overlapping despite there being no snapping.
        for offset in 0..<(subject.seats - RadialLayout.seatsPerTurn) {
            let inner = subject.seat(at: offset)
            let outer = subject.seat(at: offset + RadialLayout.seatsPerTurn)
            #expect(isClose(inner.startAngle, outer.startAngle))
            #expect(outer.innerRadius >= inner.outerRadius)
            #expect(isClose(outer.innerRadius - inner.outerRadius, subject.turnGap))
        }
    }

    /// The two windings agree on the first seat and diverge immediately after. Pins that they are
    /// genuinely two arrangements rather than one with a cosmetic difference.
    @Test("The windings share a first seat and differ from the second")
    func windingsDivergeAfterTheFirstSeat() {
        let circular = radial(.circular, count: 8)
        let spiral = radial(.spiral, count: 8)

        #expect(isClose(circular.seat(at: 0).innerRadius, spiral.seat(at: 0).innerRadius))
        for offset in 1..<8 {
            #expect(circular.seat(at: offset).innerRadius < spiral.seat(at: offset).innerRadius)
        }
    }

    // MARK: - Radial hit testing

    /// The whole wedge is live, not just the box its contents sit in. This is the point of aiming
    /// at a ring: a flick in roughly the right direction has to land.
    @Test("Every part of a wedge selects it", arguments: radialStyles)
    func wedgeIsLiveThroughout(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 16, available: Self.roomy)
        guard let geometry = subject.radial else {
            Issue.record("\(style) should have radial geometry")
            return
        }

        for seat in geometry.visibleSeats {
            // Sample across the wedge, near both angular edges and both arcs.
            for angleFraction in [0.06, 0.3, 0.5, 0.7, 0.94] {
                for radiusFraction in [0.06, 0.5, 0.94] {
                    let angle = seat.startAngle + (seat.endAngle - seat.startAngle) * angleFraction
                    let radius = seat.innerRadius
                        + (seat.outerRadius - seat.innerRadius) * CGFloat(radiusFraction)
                    let point = CGPoint(
                        x: geometry.centre.x + radius * CGFloat(cos(angle)),
                        y: geometry.centre.y + radius * CGFloat(sin(angle))
                    )
                    #expect(
                        hit(subject, atTopLeft: point) == seat.offset,
                        "\(style) seat \(seat.offset) missed at angle \(angleFraction), radius \(radiusFraction)"
                    )
                }
            }
        }
    }

    /// The hollow middle is not a card. It confirms the selection instead, because it is where the
    /// selected window is named.
    @Test("The hub selects no card and confirms instead", arguments: radialStyles)
    func hubIsNotACard(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 9, selected: 4)
        let centre = subject.radialCentre

        #expect(hit(subject, atTopLeft: centre) == nil)
        #expect(subject.commitsSelection(atPanelPoint: appKitPoint(centre, in: subject)))
        #expect(
            subject.target(
                atPanelPoint: appKitPoint(centre, in: subject),
                scrollOffset: 0,
                selectedScale: style.selectedScale
            ) == .confirmSelection
        )
    }

    /// Beyond the outermost turn there is nothing, so a click there dismisses.
    @Test("Points outside the outermost turn hit nothing", arguments: radialStyles)
    func outsideTheArcHitsNothing(style: OverlayLayoutStyle) {
        let subject = layout(style, count: 12, available: Self.roomy)
        guard let geometry = subject.radial else {
            Issue.record("\(style) should have radial geometry")
            return
        }
        let beyond = geometry.outerRadius + 6

        for step in 0..<12 {
            let angle = Double(step) * .pi / 6
            let point = CGPoint(
                x: geometry.centre.x + beyond * CGFloat(cos(angle)),
                y: geometry.centre.y + beyond * CGFloat(sin(angle))
            )
            #expect(hit(subject, atTopLeft: point) == nil)
        }
    }

    /// Angles are compared modulo a full turn, so a seat that wraps past 2π still matches.
    @Test("Angle containment survives wrapping")
    func angleContainmentWraps() {
        let start = 1.5 * Double.pi
        let end = start + Double.pi / 6

        #expect(RadialLayout.angle(start + 0.05, isWithin: start, and: end))
        // The same direction expressed a full turn away.
        #expect(RadialLayout.angle(start + 0.05 - 2 * .pi, isWithin: start, and: end))
        #expect(!RadialLayout.angle(start - 0.05, isWithin: start, and: end))
        #expect(!RadialLayout.angle(end + 0.05, isWithin: start, and: end))
    }

    /// Wedges are the biggest targets of any arrangement, which is the trade for showing one line
    /// of text.
    @Test("A wedge is a large target", arguments: RadialLayout.Winding.allCases)
    func wedgesAreLargeTargets(winding: RadialLayout.Winding) {
        let subject = radial(winding, count: 8)

        for seat in subject.visibleSeats {
            let arc = seat.midRadius * CGFloat(seat.endAngle - seat.startAngle)
            #expect(isClose(seat.outerRadius - seat.innerRadius, subject.ringThickness))
            #expect(arc >= 100, "seat \(seat.offset) was only \(arc)pt of arc")
        }
    }


    // MARK: - Confirm region

    @Test("Clicking the preview switches, in the styles that have one")
    func previewRegionCommitsSelection() {
        for style in [OverlayLayoutStyle.list, .circular] {
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
        #expect(OverlayLayoutStyle.circular.rawValue == 3)
        #expect(OverlayLayoutStyle.spiral.rawValue == 4)
        #expect(OverlayLayoutStyle.allCases.count == 5)
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
        #expect(!OverlayLayoutStyle.circular.drawsBackdrop)
        #expect(OverlayLayoutStyle.list.drawsBackdrop)
    }

    @Test("Large panels are centred on the display, aimed ones follow the cursor")
    func placementAnchorsMatchTheStyle() {
        #expect(OverlayLayoutStyle.strip.placementAnchor == .cursor)
        #expect(OverlayLayoutStyle.circular.placementAnchor == .cursor)
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
