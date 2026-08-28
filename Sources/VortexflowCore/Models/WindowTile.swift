import CoreGraphics

/// Where a window is sent on its screen.
///
/// Pure geometry, deliberately. The rest of tiling is two Accessibility writes that can only be
/// exercised against a live window on a real desk, so the part that can be wrong in a way nobody
/// notices — which half is "top" — is kept here where a test can pin it.
///
/// The two rows match macOS's own window menu: Move & Resize is the four halves, Fill & Arrange
/// is fill, the two-thirds panes, and the first quarter. macOS's Fill & Arrange buttons pick a
/// second window; these frames apply the same shapes to *this* window so the menu does not have
/// to become a picker. Quartz y grows *downward*, so the top half is the half with the *smaller* y.
enum WindowTile: String, Equatable, CaseIterable, Sendable {

    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case fill
    case leftTwoThirds
    case rightTwoThirds
    case topLeft

    /// The four halves, in the order macOS draws them.
    static let moveResize: [WindowTile] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]

    /// Fill and the remaining arrangements, in the order macOS draws them.
    static let fillArrange: [WindowTile] = [.fill, .leftTwoThirds, .rightTwoThirds, .topLeft]

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
        // Rounded to a whole point, with the remainder given to the complementary pane. Splitting
        // an odd width into two halves of `width / 2` leaves a half-point seam, or a half-point
        // overhang past the edge.
        let halfWidth = (visibleBounds.width / 2).rounded()
        let halfHeight = (visibleBounds.height / 2).rounded()
        let twoThirdsWidth = (visibleBounds.width * 2 / 3).rounded()

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
        case .topHalf:
            return CGRect(
                x: visibleBounds.minX, y: visibleBounds.minY,
                width: visibleBounds.width, height: halfHeight
            )
        case .bottomHalf:
            return CGRect(
                x: visibleBounds.minX, y: visibleBounds.minY + halfHeight,
                width: visibleBounds.width, height: visibleBounds.height - halfHeight
            )
        case .fill:
            return visibleBounds
        case .leftTwoThirds:
            return CGRect(
                x: visibleBounds.minX, y: visibleBounds.minY,
                width: twoThirdsWidth, height: visibleBounds.height
            )
        case .rightTwoThirds:
            return CGRect(
                x: visibleBounds.minX + (visibleBounds.width - twoThirdsWidth),
                y: visibleBounds.minY,
                width: twoThirdsWidth, height: visibleBounds.height
            )
        case .topLeft:
            return CGRect(
                x: visibleBounds.minX, y: visibleBounds.minY,
                width: halfWidth, height: halfHeight
            )
        }
    }

    /// The glyph, chosen to match the shapes macOS itself uses in its Move & Resize menu so the row
    /// reads as the same set of choices rather than as this app's invention.
    var symbolName: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .fill: return "rectangle"
        case .leftTwoThirds: return "rectangle.split.2x1"
        case .rightTwoThirds: return "rectangle.split.1x2"
        case .topLeft: return "rectangle.split.2x2"
        }
    }

    var title: String {
        switch self {
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .topHalf: return "Top half"
        case .bottomHalf: return "Bottom half"
        case .fill: return "Fill"
        case .leftTwoThirds: return "Left two-thirds"
        case .rightTwoThirds: return "Right two-thirds"
        case .topLeft: return "Top left"
        }
    }
}

extension DisplayInfo {

    /// Where a window of `size` should sit when moved onto this display.
    ///
    /// Centered in the usable area, and shrunk to fit if it is larger than the screen it is
    /// arriving on — otherwise a window tiled across a big monitor would hang off a laptop.
    func frameForMovedWindow(size: CGSize) -> CGRect {
        let fitted = CGSize(
            width: min(size.width, visibleBounds.width),
            height: min(size.height, visibleBounds.height)
        )
        return CGRect(
            x: visibleBounds.minX + ((visibleBounds.width - fitted.width) / 2).rounded(),
            y: visibleBounds.minY + ((visibleBounds.height - fitted.height) / 2).rounded(),
            width: fitted.width,
            height: fitted.height
        )
    }
}
