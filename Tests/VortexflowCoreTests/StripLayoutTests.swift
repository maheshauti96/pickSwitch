import CoreGraphics
import Testing
@testable import VortexflowCore

/// Requirement 3.3, 3.8 and the hover hit-testing that Requirement 4.7 depends on.
@Suite("Strip layout")
struct StripLayoutTests {

    private func layout(
        count: Int,
        selected: Int? = nil,
        width: CGFloat = 1000
    ) -> StripLayout {
        StripLayout(cardCount: count, selectedIndex: selected, availableContentWidth: width)
    }

    // MARK: - Sizing

    @Test("Content width includes inter-card spacing")
    func contentWidthAccountsForSpacing() {
        let subject = layout(count: 3)
        let expected = 3 * StripLayout.cardSize.width + 2 * StripLayout.cardSpacing
        #expect(isClose(subject.contentWidth, expected))
    }

    @Test("An empty strip has no content width")
    func emptyStripHasNoWidth() {
        #expect(layout(count: 0).contentWidth == 0)
    }

    @Test("Viewport is capped by the available width")
    func viewportIsCapped() {
        let narrow = layout(count: 20, width: 500)
        #expect(isClose(narrow.viewportWidth, 500))
        #expect(narrow.isScrollable)
    }

    @Test("Viewport shrinks to the content when everything fits")
    func viewportShrinksToContent() {
        let roomy = layout(count: 2, width: 5000)
        #expect(isClose(roomy.viewportWidth, roomy.contentWidth))
        #expect(!roomy.isScrollable)
        #expect(isClose(roomy.maxScrollOffset, 0))
    }

    /// The panel must leave vertical room for the selected card's scale-up, or the
    /// enlarged card would be clipped (Requirement 3.3).
    @Test("Panel height leaves headroom for the selected card scale")
    func panelHeightLeavesScaleHeadroom() {
        let subject = layout(count: 3, selected: 1)
        #expect(subject.panelSize.height > StripLayout.cardSize.height)

        let headroom = StripLayout.cardSize.height * (StripLayout.selectedScale - 1)
        let expected = StripLayout.cardSize.height + StripLayout.contentInset * 2 + headroom
        #expect(isClose(subject.panelSize.height, expected))
    }

    /// Requirement 3.3 pins the selected scale to the 1.05–1.10 band.
    @Test("Selected scale sits inside the specified range")
    func selectedScaleWithinSpecifiedRange() {
        #expect(StripLayout.selectedScale >= 1.05)
        #expect(StripLayout.selectedScale <= 1.10)
    }

    // MARK: - Scrolling

    @Test("No scrolling happens when the content fits")
    func noScrollWhenContentFits() {
        let subject = layout(count: 2, selected: 1, width: 5000)
        #expect(isClose(subject.scrollOffset(keepingSelectionVisible: 0), 0))
    }

    /// Requirement 3.8.
    @Test("Scrolling reveals a selection that is off the right edge")
    func scrollRevealsRightSelection() {
        let subject = layout(count: 20, selected: 19, width: 600)
        let offset = subject.scrollOffset(keepingSelectionVisible: 0)
        let cardRight = subject.cardOriginX(at: 19) + StripLayout.cardSize.width

        #expect(isClose(offset, cardRight - subject.viewportWidth))
        #expect(offset <= subject.maxScrollOffset + 0.001)
    }

    @Test("Scrolling reveals a selection that is off the left edge")
    func scrollRevealsLeftSelection() {
        let subject = layout(count: 20, selected: 0, width: 600)
        #expect(isClose(subject.scrollOffset(keepingSelectionVisible: 900), 0))
    }

    @Test("An already-visible selection does not move the strip")
    func visibleSelectionDoesNotScroll() {
        let subject = layout(count: 20, selected: 1, width: 700)
        #expect(isClose(subject.scrollOffset(keepingSelectionVisible: 0), 0))
    }

    @Test("Scroll offset never leaves its legal range", arguments: 0..<25)
    func scrollOffsetStaysInRange(selected: Int) {
        let subject = layout(count: 25, selected: selected, width: 640)
        for start in stride(from: CGFloat(-500), through: 4000, by: 250) {
            let offset = subject.scrollOffset(keepingSelectionVisible: start)
            #expect(offset >= 0)
            #expect(offset <= subject.maxScrollOffset + 0.001)
        }
    }

    /// The whole reason the strip does its own layout: after scrolling to a
    /// selection, that selection must actually be inside the viewport.
    @Test("The selected card is fully visible after scrolling", arguments: 0..<25)
    func selectedCardIsFullyVisible(selected: Int) {
        let subject = layout(count: 25, selected: selected, width: 640)
        let offset = subject.scrollOffset(keepingSelectionVisible: 0)
        let left = subject.cardOriginX(at: selected)
        let right = left + StripLayout.cardSize.width

        #expect(left >= offset - 0.001, "card \(selected) is clipped on the left")
        #expect(right <= offset + subject.viewportWidth + 0.001, "card \(selected) is clipped on the right")
    }

    // MARK: - Hit testing

    @Test("Hit test finds the card under its centre point", arguments: 0..<5)
    func hitTestFindsCardUnderCentre(index: Int) {
        let subject = layout(count: 5)
        let centre = CGPoint(
            x: subject.cardOriginX(at: index) + StripLayout.cardSize.width / 2,
            y: StripLayout.cardSize.height / 2
        )
        #expect(subject.cardIndex(atContentPoint: centre) == index)
    }

    @Test("Hit test rejects the gutter between cards")
    func hitTestRejectsGutter() {
        let subject = layout(count: 5)
        let gapCentre = CGPoint(
            x: StripLayout.cardSize.width + StripLayout.cardSpacing / 2,
            y: StripLayout.cardSize.height / 2
        )
        #expect(subject.cardIndex(atContentPoint: gapCentre) == nil)
    }

    @Test("Hit test rejects points outside the strip")
    func hitTestRejectsOutsidePoints() {
        let subject = layout(count: 5)
        let mid = StripLayout.cardSize.height / 2

        #expect(subject.cardIndex(atContentPoint: CGPoint(x: -5, y: mid)) == nil)
        #expect(subject.cardIndex(atContentPoint: CGPoint(x: 10, y: -5)) == nil)
        #expect(subject.cardIndex(atContentPoint: CGPoint(x: 10, y: StripLayout.cardSize.height + 5)) == nil)
        #expect(subject.cardIndex(atContentPoint: CGPoint(x: subject.contentWidth + 50, y: mid)) == nil)
    }

    @Test("Hit test on an empty strip finds nothing")
    func hitTestOnEmptyStrip() {
        #expect(layout(count: 0).cardIndex(atContentPoint: .zero) == nil)
    }

    /// `cardFrame` and `cardIndex` must be exact inverses, at every scroll offset.
    /// Drawing uses the former and hover uses the latter, so any disagreement shows
    /// up as the wrong card highlighting under the cursor.
    @Test("Card frames and hit testing round-trip at every scroll offset")
    func cardFrameAndHitTestRoundTrip() {
        let subject = layout(count: 12, selected: 0, width: 700)
        let headroom = StripLayout.cardSize.height * (StripLayout.selectedScale - 1)

        for offset in stride(from: CGFloat(0), through: subject.maxScrollOffset, by: 37) {
            for index in 0..<12 {
                let frame = subject.cardFrame(at: index)
                // Panel coordinates for the card centre, mirroring how the view lays
                // out: content inset, minus scroll, plus the scale headroom.
                let panelPoint = CGPoint(
                    x: frame.midX - offset + StripLayout.contentInset,
                    y: frame.midY + StripLayout.contentInset + headroom / 2
                )
                let hit = subject.cardIndex(atPanelPoint: panelPoint, scrollOffset: offset)

                // Only assert for cards actually inside the viewport; ones scrolled
                // out are legitimately unhittable.
                let visible = frame.minX >= offset && frame.maxX <= offset + subject.viewportWidth
                if visible {
                    #expect(hit == index, "offset \(offset), card \(index)")
                }
            }
        }
    }
}
