import CoreGraphics
import Foundation
import Testing
@testable import PeekSwitchCore

/// How far the hub's text may shrink before it gives up and truncates.
///
/// The point of every test here is the *floor*. Letting text shrink to fit is what stopped ordinary
/// window titles arriving with their ends cut off, and it is also the change most able to go wrong
/// quietly: nothing crashes, nothing overflows, the type just gets smaller than anyone can read at
/// some arrangement sizes and not others. A sweep is the only way that shows up, since it is invisible
/// in a diff and invisible in a screenshot of whichever size you happened to look at.
@Suite("Hub typography")
struct HubTypographyTests {

    /// Every scale the arrangement realistically produces, plus the degenerate ends.
    private static let scales: [CGFloat] = [0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.647, 0.7, 0.8, 0.816, 0.9, 1.0]

    /// The guarantee that makes shrinking safe at all: shrinking to the stated minimum lands exactly
    /// on the floor, never below it, at any size the arrangement can be drawn.
    @Test("no line can shrink below its legibility floor", arguments: HubTypographyTests.scales)
    func nothingShrinksBelowItsFloor(scale: CGFloat) {
        let type = HubTypography(radialScale: scale)

        let shrunkTitle = Double(type.titleSize) * type.titleMinimumScale
        let shrunkSource = Double(type.sourceSize) * type.sourceMinimumScale
        let shrunkStatus = Double(type.statusSize) * type.statusMinimumScale

        // A hair of tolerance for binary floating point, not for a real shortfall.
        let epsilon = 0.0001
        #expect(
            shrunkTitle >= Double(HubTypography.primaryFloor) - epsilon,
            "title at scale \(scale) can reach \(shrunkTitle)pt"
        )
        #expect(
            shrunkSource >= Double(HubTypography.secondaryFloor) - epsilon,
            "source at scale \(scale) can reach \(shrunkSource)pt"
        )
        #expect(
            shrunkStatus >= Double(HubTypography.secondaryFloor) - epsilon,
            "status at scale \(scale) can reach \(shrunkStatus)pt"
        )
    }

    /// The sizes themselves never start below the floor either, whatever the arrangement does.
    @Test("no line starts below its floor", arguments: HubTypographyTests.scales)
    func nothingStartsBelowItsFloor(scale: CGFloat) {
        let type = HubTypography(radialScale: scale)
        #expect(type.titleSize >= HubTypography.primaryFloor)
        #expect(type.sourceSize >= HubTypography.secondaryFloor)
        #expect(type.statusSize >= HubTypography.secondaryFloor)
    }

    /// A scale factor above 1 would ask SwiftUI to *grow* the text, which is not what any of this is
    /// for. It comes up wherever the size has already been clamped to the floor.
    @Test("a line already at its floor is not asked to grow", arguments: HubTypographyTests.scales)
    func minimumScaleNeverExceedsOne(scale: CGFloat) {
        let type = HubTypography(radialScale: scale)
        #expect(type.titleMinimumScale <= 1)
        #expect(type.sourceMinimumScale <= 1)
        #expect(type.statusMinimumScale <= 1)
        #expect(type.titleMinimumScale > 0)
        #expect(type.sourceMinimumScale > 0)
        #expect(type.statusMinimumScale > 0)
    }

    /// At full size there is real headroom, so a long title genuinely does shrink rather than clip.
    /// Without this the floor could be satisfied by never shrinking at all.
    @Test("at full size the title has room to shrink")
    func titleCanActuallyShrink() {
        let type = HubTypography(radialScale: 1)
        #expect(type.titleSize == 15)
        #expect(type.titleMinimumScale < 0.7, "no useful shrink range: \(type.titleMinimumScale)")
    }

    /// A scaled-down arrangement has already been clamped to the floor, so there is nothing left to
    /// give and the line truncates instead. That is the honest outcome, not a bug.
    @Test("a scaled-down title is at its floor and cannot shrink further")
    func smallTitleCannotShrink() {
        let type = HubTypography(radialScale: 0.5)
        #expect(type.titleSize == HubTypography.primaryFloor)
        #expect(type.titleMinimumScale == 1)
    }

    /// Three lines at every size. This dropped to two on small arrangements when the font shrank
    /// without a stated limit, and the line count was standing in for the legibility rule the floor
    /// now states outright. Taking a line away only discarded information, and a small arrangement is
    /// exactly where the title is most likely to be clipped.
    @Test("the title keeps three lines at every size", arguments: HubTypographyTests.scales)
    func titleKeepsItsLines(scale: CGFloat) {
        #expect(HubTypography(radialScale: scale).titleLines == 3)
    }

    /// `isRoomy` still gates the one thing that is genuinely optional — the age beside the
    /// desktop warning — and must not follow the line count.
    @Test("roominess tracks the arrangement rather than the line count")
    func roominessTracksScale() {
        #expect(HubTypography(radialScale: 1).isRoomy)
        #expect(HubTypography(radialScale: 0.9).isRoomy)
        #expect(!HubTypography(radialScale: 0.8).isRoomy)
        #expect(!HubTypography(radialScale: 0.647).isRoomy)
    }

    /// A zero or negative scale is not a size the arrangement should produce, but arithmetic upstream
    /// could hand one over, and the answer must still be drawable rather than a divide-by-zero.
    @Test("a degenerate scale still produces drawable type", arguments: [CGFloat(0), -1, -100])
    func degenerateScaleIsSafe(scale: CGFloat) {
        let type = HubTypography(radialScale: scale)
        #expect(type.titleSize == HubTypography.primaryFloor)
        #expect(type.titleMinimumScale == 1)
        #expect(type.titleLines == 3)
    }
}
