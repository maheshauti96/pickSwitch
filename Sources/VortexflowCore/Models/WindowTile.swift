import CoreGraphics

/// Where a window goes when it is sent to half its screen.
///
/// Pure geometry, deliberately. The rest of tiling is two Accessibility writes that can only be
/// exercised against a live window on a real desk, so the part that can be wrong in a way nobody
/// notices — which half is "top" — is kept here where a test can pin it.
/// Only the two vertical halves. Top and bottom were offered first and removed: a half-height window
/// is a shape almost nothing is designed for — a browser, an editor or a terminal at 456pt tall shows
/// so few lines that the tiling is undone immediately — whereas side-by-side halves are the
/// arrangement people actually want two windows in.
enum WindowTile: String, Equatable, CaseIterable, Sendable {

    case leftHalf
    case rightHalf

    /// The window's new frame inside the screen's usable area.
    ///
    /// - Parameter visibleBounds: the screen's usable rectangle in **Quartz global display
    ///   coordinates** — origin at the top-left of the main display, y increasing *downward*, the
    ///   space `DisplayInfo.bounds` and `kAXPositionAttribute` both use. That direction is the whole
    ///   subtlety: the top half is the half with the *smaller* y, so reading this as `NSScreen`
    ///   coordinates silently swaps top and bottom and nothing else looks wrong.
    ///
    ///   It must be the *visible* bounds rather than the display bounds, or a tiled window slides
    ///   under the menu bar and the Dock.
    func frame(in visibleBounds: CGRect) -> CGRect {
        // Rounded to a whole point, with the remainder given to the second half. Splitting an odd
        // width into two halves of `width / 2` leaves a half-point seam down the middle of the
        // screen, or a half-point overhang past its edge.
        let halfWidth = (visibleBounds.width / 2).rounded()

        switch self {
        case .leftHalf:
            return CGRect(
                x: visibleBounds.minX, y: visibleBounds.minY,
                width: halfWidth, height: visibleBounds.height
            )
        case .rightHalf:
            return CGRect(
                x: visibleBounds.minX + halfWidth, y: visibleBounds.minY,
                width: visibleBounds.width - halfWidth, height: visibleBounds.height
            )
        }
    }

    /// The glyph, chosen to match the shapes macOS itself uses in its Move & Resize menu so the row
    /// reads as the same set of choices rather than as this app's invention.
    var symbolName: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        }
    }

    var title: String {
        switch self {
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        }
    }
}
