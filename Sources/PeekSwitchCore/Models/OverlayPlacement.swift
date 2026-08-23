import CoreGraphics
import Foundation

/// Where the overlay panel goes (Requirement 13.1–13.3).
///
/// Pure math, kept away from `NSScreen` so it can be tested against synthetic
/// display arrangements including the awkward ones: cursor in a corner, panel
/// wider than the display, stacked displays with negative origins.
enum OverlayPlacement {

    /// What the panel is centred on before it is pushed inside the display.
    enum Anchor: Sendable {
        /// Under the hand, for styles the user aims at.
        case cursor
        /// Middle of the active display, for large panels that would otherwise jump
        /// around as the pointer moves.
        case displayCentre
    }

    /// Centre `panelSize` on `anchor`, then push it back inside `visibleFrame`.
    static func origin(
        panelSize: CGSize,
        cursor: CGPoint,
        visibleFrame: CGRect,
        anchor: Anchor
    ) -> CGPoint {
        switch anchor {
        case .cursor:
            return origin(panelSize: panelSize, cursor: cursor, visibleFrame: visibleFrame)
        case .displayCentre:
            return origin(
                panelSize: panelSize,
                cursor: CGPoint(x: visibleFrame.midX, y: visibleFrame.midY),
                visibleFrame: visibleFrame
            )
        }
    }

    /// Centre `panelSize` on `cursor`, then push it back inside `visibleFrame`.
    ///
    /// When the panel is larger than the visible frame in an axis, it is aligned to
    /// that axis's minimum edge instead of being centred; a panel hanging off both
    /// sides is worse than one hanging off the far side only.
    ///
    /// - Parameters:
    ///   - panelSize: size of the overlay panel.
    ///   - cursor: cursor position in screen coordinates.
    ///   - visibleFrame: the target display's visible frame, i.e. excluding the
    ///     menu bar and the Dock.
    /// - Returns: the panel origin, in the same coordinate space as `visibleFrame`.
    static func origin(
        panelSize: CGSize,
        cursor: CGPoint,
        visibleFrame: CGRect
    ) -> CGPoint {
        var x = cursor.x - panelSize.width / 2
        var y = cursor.y - panelSize.height / 2

        if panelSize.width >= visibleFrame.width {
            x = visibleFrame.minX
        } else {
            x = min(max(x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        }

        if panelSize.height >= visibleFrame.height {
            y = visibleFrame.minY
        } else {
            y = min(max(y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        }

        return CGPoint(x: x, y: y)
    }

    /// Content width the strip may use on a given display (Requirement 3.8 feeds
    /// off this): a fraction of the display, less the panel's own insets.
    static func availableContentWidth(visibleFrame: CGRect) -> CGFloat {
        let usable = visibleFrame.width * StripLayout.maxWidthFraction
        return max(StripLayout.cardSize.width, usable - StripLayout.contentInset * 2)
    }

    /// Height the overlay may occupy on a given display. The grid, list and radial
    /// styles are tall enough to need this; the strip is one card high and ignores it.
    ///
    /// The floor keeps a very short display (or a transient zero-height frame during
    /// reconfiguration) from producing a panel with no room for a single card.
    static func availableContentHeight(visibleFrame: CGRect) -> CGFloat {
        let usable = visibleFrame.height * StripLayout.maxHeightFraction
        return max(StripLayout.cardSize.height, usable - StripLayout.contentInset * 2)
    }

    /// Pick the display containing the cursor; fall back to the first display when
    /// the cursor is in no display's bounds, which happens transiently while
    /// displays are being reconfigured.
    static func displayIndexContaining(cursor: CGPoint, frames: [CGRect]) -> Int? {
        if let index = frames.firstIndex(where: { $0.contains(cursor) }) {
            return index
        }
        return frames.isEmpty ? nil : 0
    }
}
