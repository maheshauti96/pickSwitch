import CoreGraphics
import Foundation

/// Pure geometry for the horizontal strip (Requirement 3).
///
/// The strip does its own layout arithmetic rather than leaning on a SwiftUI
/// `ScrollView` for one concrete reason: hover selection is driven by polling the
/// global cursor position (see `OverlayController`), so the code must be able to
/// answer "which card is under this screen point" with the exact same numbers it
/// used to draw. A `ScrollView`'s internal offset is not observable, which would
/// leave drawing and hit-testing free to disagree.
///
/// Everything here is a value type with no UIKit/AppKit dependency, so all of it
/// is directly unit-testable.
struct StripLayout: Equatable {

    // MARK: - Fixed metrics

    /// Card size at rest. 16:10-ish thumbnail plus a two-line info footer.
    static let cardSize = CGSize(width: 208, height: 152)
    static let thumbnailHeight: CGFloat = 104
    static let cardSpacing: CGFloat = 12
    static let contentInset: CGFloat = 16
    /// Selected cards draw at this scale. Requirement 3.3 asks for 1.05–1.10.
    static let selectedScale: CGFloat = 1.08
    /// The strip never grows wider than this fraction of the display it sits on,
    /// so a user with 20 windows open still gets a panel that fits.
    static let maxWidthFraction: CGFloat = 0.86
    /// Same idea vertically, for the grid, list and radial styles. Kept a little
    /// tighter than the width so a full-height panel never looks like a takeover of
    /// the display.
    static let maxHeightFraction: CGFloat = 0.82

    // MARK: - Inputs

    let cardCount: Int
    let selectedIndex: Int?
    /// Width the strip is allowed to occupy, already excluding insets.
    let availableContentWidth: CGFloat

    // MARK: - Derived

    /// Total width of all cards laid end to end.
    var contentWidth: CGFloat {
        guard cardCount > 0 else { return 0 }
        return CGFloat(cardCount) * Self.cardSize.width
            + CGFloat(cardCount - 1) * Self.cardSpacing
    }

    /// Width of the scrollable viewport: the content, capped by what is available.
    var viewportWidth: CGFloat {
        min(contentWidth, max(0, availableContentWidth))
    }

    /// Minimum panel width, so the "no switchable windows" message has somewhere to
    /// live (Requirement 1.8). Without a floor, zero cards yields a 32pt-wide panel
    /// — just the two insets — and the message is clipped to nothing.
    static let emptyStateWidth: CGFloat = 320

    /// Full panel size including insets. Vertical inset is doubled at the top and
    /// bottom to leave room for the selected card's 1.08x scale to breathe.
    var panelSize: CGSize {
        let scaleHeadroom = Self.cardSize.height * (Self.selectedScale - 1)
        let height = Self.cardSize.height + Self.contentInset * 2 + scaleHeadroom

        guard cardCount > 0 else {
            return CGSize(width: Self.emptyStateWidth, height: height)
        }
        return CGSize(
            width: viewportWidth + Self.contentInset * 2,
            height: height
        )
    }

    var isScrollable: Bool { contentWidth > viewportWidth + 0.5 }

    /// Maximum legal scroll offset. Zero when everything already fits.
    var maxScrollOffset: CGFloat { max(0, contentWidth - viewportWidth) }

    /// Left edge of card `index` in content coordinates.
    func cardOriginX(at index: Int) -> CGFloat {
        CGFloat(index) * (Self.cardSize.width + Self.cardSpacing)
    }

    /// Frame of card `index` in content coordinates.
    func cardFrame(at index: Int) -> CGRect {
        CGRect(
            x: cardOriginX(at: index),
            y: 0,
            width: Self.cardSize.width,
            height: Self.cardSize.height
        )
    }

    /// Scroll offset that keeps the selected card fully inside the viewport
    /// (Requirement 3.8), using the minimum movement needed. Clamped to the legal
    /// range so the strip can never be scrolled past its ends.
    ///
    /// - Parameter current: the offset currently in effect, so an already-visible
    ///   selection does not cause the strip to jump.
    func scrollOffset(keepingSelectionVisible current: CGFloat) -> CGFloat {
        guard isScrollable, let index = selectedIndex, cardCount > 0 else { return 0 }

        let cardLeft = cardOriginX(at: index)
        let cardRight = cardLeft + Self.cardSize.width

        var offset = current
        if cardLeft < offset {
            offset = cardLeft
        } else if cardRight > offset + viewportWidth {
            offset = cardRight - viewportWidth
        }
        return min(max(offset, 0), maxScrollOffset)
    }

    /// Which card sits under `pointInContent`, or `nil` for the gaps between
    /// cards. Inverse of `cardFrame(at:)`, which is what makes hover reliable.
    func cardIndex(atContentPoint pointInContent: CGPoint) -> Int? {
        guard cardCount > 0 else { return nil }
        guard pointInContent.y >= 0, pointInContent.y <= Self.cardSize.height else { return nil }
        guard pointInContent.x >= 0 else { return nil }

        let stride = Self.cardSize.width + Self.cardSpacing
        let index = Int(floor(pointInContent.x / stride))
        guard index >= 0, index < cardCount else { return nil }

        // Reject the inter-card gutter so hover does not "stick" while crossing it.
        let offsetWithinCard = pointInContent.x - CGFloat(index) * stride
        guard offsetWithinCard <= Self.cardSize.width else { return nil }

        return index
    }

    /// Convert a point in panel coordinates (origin at the panel's bottom-left,
    /// matching AppKit) into content coordinates, then hit-test.
    func cardIndex(atPanelPoint pointInPanel: CGPoint, scrollOffset: CGFloat) -> Int? {
        let scaleHeadroom = Self.cardSize.height * (Self.selectedScale - 1)
        let contentPoint = CGPoint(
            x: pointInPanel.x - Self.contentInset + scrollOffset,
            y: pointInPanel.y - Self.contentInset - scaleHeadroom / 2
        )

        // The selected card is drawn above its neighbours at 1.08×. Test that visual
        // frame first so every pixel that looks like part of the card is clickable,
        // including the small fringe extending into the surrounding gutter.
        if let selectedIndex,
           selectedIndex >= 0,
           selectedIndex < cardCount {
            let horizontalGrowth = Self.cardSize.width * (Self.selectedScale - 1) / 2
            let verticalGrowth = Self.cardSize.height * (Self.selectedScale - 1) / 2
            let selectedVisualFrame = cardFrame(at: selectedIndex).insetBy(
                dx: -horizontalGrowth,
                dy: -verticalGrowth
            )
            if selectedVisualFrame.contains(contentPoint) {
                return selectedIndex
            }
        }

        return cardIndex(atContentPoint: contentPoint)
    }
}
