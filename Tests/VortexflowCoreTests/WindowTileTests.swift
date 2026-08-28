import CoreGraphics
import Foundation
import Testing
@testable import VortexflowCore

/// The geometry of sending a window to a region of its screen.
///
/// Worth testing precisely because the mistake here is invisible: in Quartz global coordinates y
/// grows *downward*, so treating the rectangle as `NSScreen` space swaps top and bottom and every
/// other property of the result stays correct.
struct WindowTileTests {

    /// A screen that is not at the origin and has an odd width, so an off-by-one in the split shows
    /// up rather than cancelling out.
    private let screen = CGRect(x: 100, y: 37, width: 1513, height: 913)

    @Test func theLeftHalfIsTheHalfWithTheSmallerX() {
        let left = WindowTile.leftHalf.frame(in: screen)
        let right = WindowTile.rightHalf.frame(in: screen)
        #expect(left.minX == screen.minX)
        #expect(left.minX < right.minX)
        #expect(right.maxX == screen.maxX)
    }

    /// No seam and no overhang: an odd width split as `width / 2` twice leaves half a point
    /// somewhere, and the remainder has to go to one of the halves.
    @Test func theTwoHalvesCoverTheScreenExactly() {
        let left = WindowTile.leftHalf.frame(in: screen)
        let right = WindowTile.rightHalf.frame(in: screen)
        #expect(left.union(right) == screen, "the halves do not cover the screen")
        #expect(
            left.intersection(right).isEmpty,
            "the halves overlap by \(left.intersection(right))"
        )
    }

    /// Top is the half with the smaller y. Flipping the coordinate space would put it at the bottom
    /// and every other property of the rectangle would still look right.
    @Test func theTopHalfIsTheHalfWithTheSmallerY() {
        let top = WindowTile.topHalf.frame(in: screen)
        let bottom = WindowTile.bottomHalf.frame(in: screen)
        #expect(top.minY == screen.minY)
        #expect(top.maxY == bottom.minY)
        #expect(bottom.maxY == screen.maxY)
        #expect(top.union(bottom) == screen)
        #expect(top.intersection(bottom).isEmpty)
    }

    @Test func fillIsTheWholeUsableArea() {
        #expect(WindowTile.fill.frame(in: screen) == screen)
    }

    @Test func twoThirdsPanesKeepTheFullHeight() {
        let left = WindowTile.leftTwoThirds.frame(in: screen)
        let right = WindowTile.rightTwoThirds.frame(in: screen)
        #expect(left.height == screen.height)
        #expect(right.height == screen.height)
        #expect(left.minX == screen.minX)
        #expect(right.maxX == screen.maxX)
        #expect(left.width > right.width || left.width == (screen.width * 2 / 3).rounded())
    }

    @Test func theTopLeftQuarterSitsInTheOriginCorner() {
        let quarter = WindowTile.topLeft.frame(in: screen)
        #expect(quarter.minX == screen.minX)
        #expect(quarter.minY == screen.minY)
        #expect(quarter.maxX == screen.minX + (screen.width / 2).rounded())
        #expect(quarter.maxY == screen.minY + (screen.height / 2).rounded())
    }

    /// Every placement stays inside the usable area, which is what keeps a tiled window from sliding
    /// under the menu bar or the Dock.
    @Test func everyPlacementStaysWithinTheVisibleBounds() {
        for tile in WindowTile.allCases {
            let frame = tile.frame(in: screen)
            #expect(screen.union(frame) == screen, "\(tile) escapes the screen: \(frame)")
        }
    }

    /// A display to the left of, or above, the main one has negative coordinates, and the halves
    /// must be relative to that screen rather than to the origin.
    @Test func aScreenWithNegativeCoordinatesTilesRelativeToItself() {
        let secondary = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let left = WindowTile.leftHalf.frame(in: secondary)
        #expect(left.minX == -1920)
        #expect(left.width == 960)
        #expect(left.minY == -1080)
        #expect(WindowTile.rightHalf.frame(in: secondary).minX == -960)
        #expect(WindowTile.topHalf.frame(in: secondary).minY == -1080)
        #expect(WindowTile.bottomHalf.frame(in: secondary).minY == -540)
    }

    @Test func moveResizeAndFillArrangeAreTheTwoMacOSRows() {
        #expect(WindowTile.moveResize == [.leftHalf, .rightHalf, .topHalf, .bottomHalf])
        #expect(WindowTile.fillArrange == [.fill, .leftTwoThirds, .rightTwoThirds, .topLeft])
    }

    @Test func everyTileHasAGlyphAndAName() {
        for tile in WindowTile.allCases {
            #expect(!tile.symbolName.isEmpty)
            #expect(!tile.title.isEmpty)
        }
        #expect(Set(WindowTile.allCases.map(\.symbolName)).count == WindowTile.allCases.count)
        #expect(Set(WindowTile.allCases.map(\.title)).count == WindowTile.allCases.count)
    }

    @Test func aMovedWindowIsCentredOnTheTargetDisplay() {
        let display = DisplayInfo(
            number: 2,
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            isBuiltIn: false,
            name: "DELL U2720Q",
            visibleBounds: CGRect(x: 1920, y: 37, width: 1920, height: 1043)
        )
        let frame = display.frameForMovedWindow(size: CGSize(width: 800, height: 600))
        #expect(frame.width == 800)
        #expect(frame.height == 600)
        #expect(frame.minX == 1920 + ((1920 - 800) / 2).rounded())
        #expect(display.visibleBounds.contains(CGPoint(x: frame.midX, y: frame.midY)))
    }

    @Test func aWindowLargerThanTheTargetDisplayIsShrunkToFit() {
        let display = DisplayInfo(
            number: 1,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 500),
            isBuiltIn: true,
            name: "Built-in Retina Display",
            visibleBounds: CGRect(x: 0, y: 37, width: 800, height: 463)
        )
        let frame = display.frameForMovedWindow(size: CGSize(width: 1920, height: 1080))
        #expect(frame == display.visibleBounds)
    }
}

/// Crossing from `NSScreen`'s coordinate space into Quartz's.
///
/// Two spaces that disagree about which way is up, converted without being told which display is the
/// main one. These cases are the arrangements that are not reproducible on one test machine.
struct ScreenToQuartzConversionTests {

    private func convert(_ rect: CGRect, screenFrame: CGRect, quartzBounds: CGRect) -> CGRect {
        DisplayLayout.quartzRect(
            fromScreenRect: rect,
            screenFrame: screenFrame,
            quartzBounds: quartzBounds
        )
    }

    /// A single 1512×950 display with a menu bar and no Dock. The usable area starts 37pt from the
    /// top in Quartz space, where in `NSScreen` space it started at the bottom.
    @Test func theMenuBarInsetMovesToTheTop() {
        let result = convert(
            CGRect(x: 0, y: 0, width: 1512, height: 913),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            quartzBounds: CGRect(x: 0, y: 0, width: 1512, height: 950)
        )
        #expect(result == CGRect(x: 0, y: 37, width: 1512, height: 913))
    }

    /// A Dock at the bottom takes its inset from the bottom in both spaces, so the converted origin
    /// stays at the top of the display.
    @Test func aBottomDockLeavesTheTopAlone() {
        let result = convert(
            CGRect(x: 0, y: 70, width: 1512, height: 843),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            quartzBounds: CGRect(x: 0, y: 0, width: 1512, height: 950)
        )
        #expect(result == CGRect(x: 0, y: 37, width: 1512, height: 843))
    }

    /// An external display *above* the main one sits at a negative y in Quartz space and a positive
    /// one in `NSScreen` space. Getting the flip axis from this display's own pair of rectangles is
    /// what makes that work without knowing which display is primary.
    @Test func aDisplayAboveTheMainOneConvertsToNegativeY() {
        let result = convert(
            CGRect(x: 0, y: 950, width: 1920, height: 1080),
            screenFrame: CGRect(x: 0, y: 950, width: 1920, height: 1080),
            quartzBounds: CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        )
        #expect(result == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    /// A laptop to the *left* of the primary external monitor: negative x, and the primary is not
    /// first in the arrangement.
    @Test func aDisplayLeftOfTheMainOneKeepsItsNegativeX() {
        let result = convert(
            CGRect(x: -1512, y: -200, width: 1512, height: 950),
            screenFrame: CGRect(x: -1512, y: -200, width: 1512, height: 950),
            quartzBounds: CGRect(x: -1512, y: 130, width: 1512, height: 950)
        )
        #expect(result.minX == -1512)
        #expect(result.minY == 130)
    }

    /// The conversion is its own inverse: applying it to the full display rectangle returns the
    /// Quartz bounds it was given, which is the invariant that says the flip axis was right.
    @Test func convertingTheWholeScreenReturnsItsQuartzBounds() {
        let cases: [(screen: CGRect, quartz: CGRect)] = [
            (CGRect(x: 0, y: 0, width: 1512, height: 950), CGRect(x: 0, y: 0, width: 1512, height: 950)),
            (CGRect(x: 0, y: 950, width: 1920, height: 1080), CGRect(x: 0, y: -1080, width: 1920, height: 1080)),
            (CGRect(x: -1512, y: -200, width: 1512, height: 950), CGRect(x: -1512, y: 130, width: 1512, height: 950)),
        ]
        for pair in cases {
            let result = convert(pair.screen, screenFrame: pair.screen, quartzBounds: pair.quartz)
            #expect(result == pair.quartz, "\(pair.screen) converted to \(result), expected \(pair.quartz)")
        }
    }
}
