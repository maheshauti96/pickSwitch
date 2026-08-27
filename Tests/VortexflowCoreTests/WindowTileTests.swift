import CoreGraphics
import Foundation
import Testing
@testable import VortexflowCore

/// The geometry of sending a window to half its screen.
///
/// Worth testing precisely because the mistake here is invisible: in Quartz global coordinates y
/// grows *downward*, so treating the rectangle as `NSScreen` space swaps top and bottom and every
/// other property of the result stays correct.
struct WindowTileTests {

    /// A screen that is not at the origin and has an odd width, so an off-by-one in the split shows
    /// up rather than cancelling out.
    private let screen = CGRect(x: 100, y: 37, width: 1513, height: 913)

    @Test func theTopHalfIsTheHalfWithTheSmallerY() {
        let top = WindowTile.topHalf.frame(in: screen)
        let bottom = WindowTile.bottomHalf.frame(in: screen)
        #expect(top.minY == screen.minY)
        #expect(top.minY < bottom.minY, "top and bottom are swapped")
        #expect(bottom.maxY == screen.maxY)
    }

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
        for pair in [(WindowTile.leftHalf, WindowTile.rightHalf), (.topHalf, .bottomHalf)] {
            let first = pair.0.frame(in: screen)
            let second = pair.1.frame(in: screen)
            #expect(first.union(second) == screen, "\(pair) does not cover the screen")
            #expect(
                first.intersection(second).isEmpty,
                "\(pair) overlap by \(first.intersection(second))"
            )
        }
    }

    /// Every half stays inside the usable area, which is what keeps a tiled window from sliding
    /// under the menu bar or the Dock.
    @Test func everyHalfStaysWithinTheVisibleBounds() {
        for tile in WindowTile.allCases {
            let frame = tile.frame(in: screen)
            #expect(screen.union(frame) == screen, "\(tile) escapes the screen: \(frame)")
        }
    }

    /// A horizontal half keeps the full height, a vertical half keeps the full width.
    @Test func eachHalfKeepsTheOtherDimensionWhole() {
        #expect(WindowTile.leftHalf.frame(in: screen).height == screen.height)
        #expect(WindowTile.rightHalf.frame(in: screen).height == screen.height)
        #expect(WindowTile.topHalf.frame(in: screen).width == screen.width)
        #expect(WindowTile.bottomHalf.frame(in: screen).width == screen.width)
    }

    /// A display to the left of, or above, the main one has negative coordinates, and the halves
    /// must be relative to that screen rather than to the origin.
    @Test func aScreenWithNegativeCoordinatesTilesRelativeToItself() {
        let secondary = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let left = WindowTile.leftHalf.frame(in: secondary)
        #expect(left.minX == -1920)
        #expect(left.width == 960)
        #expect(WindowTile.topHalf.frame(in: secondary).minY == -1080)
    }

    @Test func everyTileHasAGlyphAndAName() {
        for tile in WindowTile.allCases {
            #expect(!tile.symbolName.isEmpty)
            #expect(!tile.title.isEmpty)
        }
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
