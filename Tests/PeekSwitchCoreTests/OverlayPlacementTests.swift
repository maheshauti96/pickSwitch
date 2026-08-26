import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// Requirement 13.1–13.3.
@Suite("Overlay placement")
struct OverlayPlacementTests {

    /// A 1920x1080 display with the menu bar removed, origin at zero.
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    /// A second display placed to the left, which puts its origin negative — the
    /// arrangement that catches sign bugs in clamping.
    private let leftOfPrimary = CGRect(x: -1512, y: 100, width: 1512, height: 900)

    private let panel = CGSize(width: 700, height: 200)

    // MARK: - Centring

    @Test("The panel centres on the cursor when there is room")
    func panelCentresOnCursor() {
        let cursor = CGPoint(x: 960, y: 500)
        let origin = OverlayPlacement.origin(panelSize: panel, cursor: cursor, visibleFrame: primary)

        #expect(isClose(origin.x, cursor.x - panel.width / 2))
        #expect(isClose(origin.y, cursor.y - panel.height / 2))
    }

    // MARK: - Clamping

    /// Requirement 13.3.
    @Test("The panel is pushed in from the right edge")
    func panelClampsFromRight() {
        let origin = OverlayPlacement.origin(
            panelSize: panel,
            cursor: CGPoint(x: 1900, y: 500),
            visibleFrame: primary
        )
        #expect(isClose(origin.x, primary.maxX - panel.width))
        #expect(origin.x + panel.width <= primary.maxX + 0.001)
    }

    @Test("The panel is pushed in from the left edge")
    func panelClampsFromLeft() {
        let origin = OverlayPlacement.origin(
            panelSize: panel,
            cursor: CGPoint(x: 10, y: 500),
            visibleFrame: primary
        )
        #expect(isClose(origin.x, primary.minX))
    }

    @Test("The panel is pushed in from the top and bottom edges")
    func panelClampsVertically() {
        let top = OverlayPlacement.origin(
            panelSize: panel,
            cursor: CGPoint(x: 960, y: primary.maxY - 5),
            visibleFrame: primary
        )
        #expect(isClose(top.y, primary.maxY - panel.height))

        let bottom = OverlayPlacement.origin(
            panelSize: panel,
            cursor: CGPoint(x: 960, y: primary.minY + 5),
            visibleFrame: primary
        )
        #expect(isClose(bottom.y, primary.minY))
    }

    @Test("The panel stays inside a display with a negative origin")
    func panelStaysInsideNegativeOriginDisplay() {
        let origin = OverlayPlacement.origin(
            panelSize: panel,
            cursor: CGPoint(x: -1500, y: 150),
            visibleFrame: leftOfPrimary
        )
        #expect(origin.x >= leftOfPrimary.minX - 0.001)
        #expect(origin.x + panel.width <= leftOfPrimary.maxX + 0.001)
        #expect(origin.y >= leftOfPrimary.minY - 0.001)
        #expect(origin.y + panel.height <= leftOfPrimary.maxY + 0.001)
    }

    /// Sweep the cursor across and beyond the whole display; the panel must never
    /// hang off an edge.
    @Test("The panel is never placed outside the visible frame")
    func panelNeverEscapesVisibleFrame() {
        for frame in [primary, leftOfPrimary] {
            for x in stride(from: frame.minX - 200, through: frame.maxX + 200, by: 97) {
                for y in stride(from: frame.minY - 200, through: frame.maxY + 200, by: 89) {
                    let origin = OverlayPlacement.origin(
                        panelSize: panel,
                        cursor: CGPoint(x: x, y: y),
                        visibleFrame: frame
                    )
                    #expect(origin.x >= frame.minX - 0.001)
                    #expect(origin.x + panel.width <= frame.maxX + 0.001)
                    #expect(origin.y >= frame.minY - 0.001)
                    #expect(origin.y + panel.height <= frame.maxY + 0.001)
                }
            }
        }
    }

    /// A panel wider than the display cannot fit. Aligning it to the minimum edge is
    /// better than centring it and losing content on both sides.
    @Test("An oversized panel aligns to the minimum edge")
    func oversizedPanelAlignsToMinEdge() {
        let oversized = CGSize(width: primary.width + 400, height: primary.height + 400)
        let origin = OverlayPlacement.origin(
            panelSize: oversized,
            cursor: CGPoint(x: 960, y: 500),
            visibleFrame: primary
        )
        #expect(isClose(origin.x, primary.minX))
        #expect(isClose(origin.y, primary.minY))
    }

    // MARK: - Content width

    @Test("Available content width leaves room for insets and stays on the display")
    func availableContentWidthFitsDisplay() {
        let width = OverlayPlacement.availableContentWidth(visibleFrame: primary)
        #expect(width < primary.width)
        #expect(width > 0)
    }

    /// Even a very narrow display must be able to show one whole card.
    @Test("Available content width never drops below one card")
    func availableContentWidthFitsOneCard() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 400)
        let width = OverlayPlacement.availableContentWidth(visibleFrame: tiny)
        #expect(width >= StripLayout.cardSize.width)
    }

    // MARK: - Display selection

    /// Requirement 13.1.
    @Test("The display containing the cursor is chosen")
    func displayContainingCursorIsChosen() {
        let frames = [primary, leftOfPrimary]
        #expect(OverlayPlacement.displayIndexContaining(cursor: CGPoint(x: 500, y: 500), frames: frames) == 0)
        #expect(OverlayPlacement.displayIndexContaining(cursor: CGPoint(x: -700, y: 500), frames: frames) == 1)
    }

    @Test("A cursor outside every display falls back to the first")
    func cursorOutsideAllDisplaysFallsBack() {
        let frames = [primary, leftOfPrimary]
        #expect(OverlayPlacement.displayIndexContaining(cursor: CGPoint(x: 9000, y: 9000), frames: frames) == 0)
    }

    @Test("No displays yields no index")
    func noDisplaysYieldsNoIndex() {
        #expect(OverlayPlacement.displayIndexContaining(cursor: .zero, frames: []) == nil)
    }

    // MARK: - Anchors

    /// The grid and list are large enough that chasing the pointer with them just
    /// makes them jump around, so they centre on the display instead.
    @Test("A display-centred panel ignores the cursor")
    func displayCentredPanelIgnoresCursor() {
        let size = CGSize(width: 900, height: 500)
        let farCorner = OverlayPlacement.origin(
            panelSize: size,
            cursor: CGPoint(x: 60, y: 60),
            visibleFrame: primary,
            anchor: .displayCentre
        )
        let elsewhere = OverlayPlacement.origin(
            panelSize: size,
            cursor: CGPoint(x: 1800, y: 900),
            visibleFrame: primary,
            anchor: .displayCentre
        )

        #expect(isClose(farCorner.x, elsewhere.x))
        #expect(isClose(farCorner.y, elsewhere.y))
        #expect(isClose(farCorner.x, primary.midX - size.width / 2))
        #expect(isClose(farCorner.y, primary.midY - size.height / 2))
    }

    @Test("A cursor-anchored panel still tracks the pointer")
    func cursorAnchoredPanelTracksPointer() {
        let size = CGSize(width: 600, height: 200)
        let cursor = CGPoint(x: 800, y: 600)
        let anchored = OverlayPlacement.origin(
            panelSize: size,
            cursor: cursor,
            visibleFrame: primary,
            anchor: .cursor
        )
        let direct = OverlayPlacement.origin(
            panelSize: size,
            cursor: cursor,
            visibleFrame: primary
        )

        #expect(isClose(anchored.x, direct.x))
        #expect(isClose(anchored.y, direct.y))
        #expect(isClose(anchored.x, cursor.x - size.width / 2))
    }

    /// Whatever the anchor, the panel must not hang off the display.
    @Test("Both anchors keep the panel on the display")
    func bothAnchorsKeepPanelOnDisplay() {
        let size = CGSize(width: 1000, height: 600)
        for anchor in [OverlayPlacement.Anchor.cursor, .displayCentre] {
            for cursor in [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 1920, y: 1055),
                CGPoint(x: 960, y: 500),
            ] {
                let origin = OverlayPlacement.origin(
                    panelSize: size,
                    cursor: cursor,
                    visibleFrame: primary,
                    anchor: anchor
                )
                #expect(origin.x >= primary.minX - 0.001)
                #expect(origin.y >= primary.minY - 0.001)
                #expect(origin.x + size.width <= primary.maxX + 0.001)
                #expect(origin.y + size.height <= primary.maxY + 0.001)
            }
        }
    }

    @Test("Available content height leaves room and stays on the display")
    func availableContentHeightFitsDisplay() {
        let height = OverlayPlacement.availableContentHeight(
            visibleFrame: primary,
            style: .grid
        )
        #expect(height > 0)
        #expect(height <= primary.height)

        // Never so small that a single card cannot be drawn.
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 120)
        #expect(
            OverlayPlacement.availableContentHeight(visibleFrame: tiny, style: .grid)
                >= StripLayout.cardSize.height
        )
    }

    @Test("Radial layouts receive 94% of display height without changing card layouts")
    func radialHeightBudgetMatchesTheReference() {
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let compact = OverlayPlacement.availableContentHeight(
            visibleFrame: builtIn,
            style: .grid
        )

        for style in [OverlayLayoutStyle.circular, .spiral] {
            let radial = OverlayPlacement.availableContentHeight(
                visibleFrame: builtIn,
                style: style
            )
            #expect(isClose(radial, builtIn.height * 0.94, tolerance: 0.001))
            #expect(radial > compact)
            #expect(radial + OverlayLayout.searchFieldHeight <= builtIn.height + 0.001)
        }
    }
}
