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

    /// Height the overlay may occupy on a given display. The grid and list retain the compact
    /// 82% budget; the radial styles use the reference's broader 94% canvas. Radial geometry owns
    /// its own 18pt edge padding, so subtracting the strip's inset here used to double-charge it
    /// and collapse the hub-to-wedge void at realistic window counts.
    ///
    /// Keep enough room for search chrome even after the radial panel has expanded. The floor
    /// still protects a transient zero-height frame during display reconfiguration.
    static func availableContentHeight(
        visibleFrame: CGRect,
        style: OverlayLayoutStyle
    ) -> CGFloat {
        if style.radialWinding != nil {
            let radialHeight = visibleFrame.height * 0.94
            let searchSafeHeight = visibleFrame.height - OverlayLayout.searchFieldHeight
            return max(StripLayout.cardSize.height, min(radialHeight, searchSafeHeight))
        }

        let usable = visibleFrame.height * StripLayout.maxHeightFraction
        return max(StripLayout.cardSize.height, usable - StripLayout.contentInset * 2)
    }

    /// Pick the display the pointer is on.
    ///
    /// Not `CGRect.contains`. AppKit reports a pointer resting in a display's top pixel
    /// row — the menu bar — at exactly `frame.maxY`, which `contains` treats as outside.
    /// On the main display that slip was invisible, because the fallback was the main
    /// display too. On any other display it sent the overlay to the wrong monitor: shortcut
    /// pressed with the pointer in the MacBook's menu bar, overlay drawn on the external
    /// screen, and the user — seeing nothing — pressing again and closing it.
    ///
    /// So each display is hit-tested the way the pointer's own geometry works (the
    /// `NSMouseInRect` rule, see `containsPointer`), and a pointer that still lands in no
    /// display — which happens transiently while displays are reconfigured — goes to the
    /// nearest display rather than an arbitrary first one.
    static func displayIndexContaining(cursor: CGPoint, frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let index = frames.firstIndex(where: { containsPointer(cursor, $0) }) {
            return index
        }

        var nearest = 0
        var nearestDistance = CGFloat.infinity
        for (index, frame) in frames.enumerated() {
            let dx = max(frame.minX - cursor.x, 0, cursor.x - frame.maxX)
            let dy = max(frame.minY - cursor.y, 0, cursor.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = index
            }
        }
        return nearest
    }

    /// `NSMouseInRect(point, frame, false)` without AppKit: the left and top edges are
    /// inside, the right and bottom edges are not. That is the range a pointer can
    /// actually report on a display in bottom-left screen coordinates: the top pixel row
    /// converts to `maxY` exactly, and the rightmost column to `maxX - 1`.
    static func containsPointer(_ point: CGPoint, _ frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX
            && point.y > frame.minY && point.y <= frame.maxY
    }
}
