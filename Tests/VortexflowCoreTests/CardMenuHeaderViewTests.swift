import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import VortexflowCore

/// Measurements of the context menu's header, which exists to be a fixed width.
///
/// This is the test that the over-wide menu is actually fixed. An `NSMenu` is as wide as its widest
/// item, and the heading used to be an ordinary menu item carrying the window title verbatim — so a
/// long title stretched the menu and padded every short action item out to match. Asserting that the
/// header reports the same width for a 3-character title and a 200-character one is the difference
/// between having fixed that and having only moved it.
@MainActor
struct CardMenuHeaderViewTests {

    private func header(
        title: String,
        rows: [CardDetails.Row] = [],
        thumbnail: CGImage? = nil,
        icon: NSImage? = nil,
        displayNumber: Int? = 1
    ) -> NSHostingView<CardMenuHeaderView> {
        let view = CardMenuHeaderView(
            details: CardDetails(
                title: title,
                source: "Google Chrome",
                rows: rows,
                displayNumber: displayNumber
            ),
            thumbnail: thumbnail,
            icon: icon
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    /// The point of the whole view.
    @Test func theHeaderIsTheSameWidthWhateverTheTitle() {
        let short = header(title: "Mail")
        let long = header(
            title: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5)
        )
        #expect(short.fittingSize.width == CardMenuHeaderView.width)
        #expect(long.fittingSize.width == CardMenuHeaderView.width)
    }

    /// A long title is allowed to cost a second line, and no more: the cap is what keeps a title from
    /// pushing the actions off the bottom of the screen.
    @Test func aLongTitleCostsAtMostOneExtraLine() {
        let short = header(title: "Mail")
        let long = header(
            title: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5)
        )
        let growth = long.fittingSize.height - short.fittingSize.height
        #expect(growth > 0, "a two-line title should be taller than a one-line title")
        #expect(growth < 24, "growth of \(growth)pt suggests the title is not capped at two lines")
    }

    /// Facts have to actually reach the layout; a grid that silently rendered nothing would still
    /// pass the width test.
    @Test func factsAddHeightWithoutAddingWidth() {
        let bare = header(title: "Mail")
        let detailed = header(
            title: "Mail",
            rows: [
                CardDetails.Row(label: "Desktop", value: "Another · 20m ago"),
                CardDetails.Row(label: "Screen", value: "DELL U2720Q"),
                CardDetails.Row(label: "Tabs", value: "23 tabs"),
            ]
        )
        #expect(detailed.fittingSize.height > bare.fittingSize.height)
        #expect(detailed.fittingSize.width == CardMenuHeaderView.width)
    }

    /// A value long enough to widen the column is truncated instead.
    @Test func anOverlongFactValueDoesNotWidenTheHeader() {
        let view = header(
            title: "Mail",
            rows: [
                CardDetails.Row(
                    label: "Screen",
                    value: String(repeating: "DELL U2720Q Ultrasharp ", count: 6)
                )
            ]
        )
        #expect(view.fittingSize.width == CardMenuHeaderView.width)
    }

    /// A ceiling on the whole header, because it is only half of what has to fit on screen. The
    /// action items sit below it, and a header that grew unchecked would push them off the bottom
    /// when the menu opens near it. Every row `CardDetails` can produce is present here.
    @Test func theFullyPopulatedHeaderStaysWithinItsBudget() {
        let view = header(
            title: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5),
            rows: [
                CardDetails.Row(label: "Desktop", value: "Another · 20m ago"),
                CardDetails.Row(label: "Screen", value: "DELL U2720Q"),
                CardDetails.Row(label: "State", value: "Minimized"),
                CardDetails.Row(label: "Tabs", value: "23 tabs"),
                CardDetails.Row(label: "Session", value: "Private window"),
                CardDetails.Row(label: "Audio", value: "Playing · microphone"),
                CardDetails.Row(label: "Window", value: "2 of 3"),
                CardDetails.Row(label: "Size", value: "1920 × 1080"),
            ]
        )
        #expect(
            view.fittingSize.height < 400,
            "header is \(view.fittingSize.height)pt tall; the actions still have to fit below it"
        )
    }

    /// The glyph rows are the other things in the menu that could widen it, so both are pinned to the
    /// header's width. A row that sized itself to its captions would have undone the fix.
    @Test func everyGlyphRowMatchesTheHeaderWidth() {
        let controls: [CardMenuItem] = [.minimizeWindow, .closeWindow]
            + WindowTile.allCases.map(CardMenuItem.tileWindow)
        let actions: [CardMenuItem] = [
            .searchWindowTabs(count: 23),
            .muteAudible,
        ]

        for count in 1...controls.count {
            let width = rowWidth(Array(controls.prefix(count)), caption: .shared("Window"))
            #expect(
                width == CardMenuHeaderView.width,
                "\(count) control(s) gave a width of \(width)"
            )
        }
        for count in 1...actions.count {
            let width = rowWidth(Array(actions.prefix(count)), caption: .perGlyph)
            #expect(
                width == CardMenuHeaderView.width,
                "\(count) action(s) gave a width of \(width)"
            )
        }
    }

    /// Six window controls cannot each carry a legible word in a fixed width, so only the hovered one
    /// is named — on a line that is always present, so nothing moves when the pointer arrives.
    @Test func theSharedCaptionRowDoesNotChangeHeightOnHover() {
        let controls: [CardMenuItem] = [.minimizeWindow, .closeWindow]
            + WindowTile.allCases.map(CardMenuItem.tileWindow)
        let hover = CardMenuHoverModel()
        let view = CardMenuGlyphRow(
            actions: controls, caption: .shared("Window"), hover: hover
        ) { _ in }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let resting = hosting.fittingSize

        hover.hoveredIndex = controls.count - 1
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize == resting, "naming the hovered glyph resized the row")
    }

    private func rowWidth(_ actions: [CardMenuItem], caption: CardMenuGlyphRow.Caption) -> CGFloat {
        let view = CardMenuGlyphRow(
            actions: actions, caption: caption, hover: CardMenuHoverModel()
        ) { _ in }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.width
    }

    // MARK: - The screen chip

    /// The colour is the point: two menus opened on two windows should answer "same screen or not"
    /// without either number being read, which only works if neighbouring screens differ.
    @Test func neighbouringScreensGetDifferentColours() {
        let tints = (1...6).map { CardMenuHeaderView.displayTint($0) }
        #expect(Set(tints.map(String.init(describing:))).count == tints.count)
    }

    /// The same screen must be the same colour every time the menu opens, or the colour says nothing.
    @Test func aScreenKeepsItsColour() {
        #expect(CardMenuHeaderView.displayTint(3) == CardMenuHeaderView.displayTint(3))
        #expect(CardMenuHeaderView.displayTint(1) != CardMenuHeaderView.displayTint(2))
    }

    /// More displays than colours wraps rather than trapping, and a zero or negative number — which
    /// should never arrive, but would index out of bounds if it did — is clamped.
    @Test func theTintSurvivesNumbersOutsideThePalette() {
        #expect(CardMenuHeaderView.displayTint(7) == CardMenuHeaderView.displayTint(1))
        #expect(CardMenuHeaderView.displayTint(0) == CardMenuHeaderView.displayTint(1))
        #expect(CardMenuHeaderView.displayTint(-4) == CardMenuHeaderView.displayTint(1))
    }

    /// The chip shares its line with the facts rather than taking one of its own.
    ///
    /// Against a single fact row the chip is the taller of the two and sets the line height, which is
    /// a few points and not a row. Against two or more it costs nothing at all, and that is the case
    /// worth pinning: the chip must never be what makes the footer grow.
    @Test func theChipSharesTheFactsLineRatherThanAddingOne() {
        let oneRow = [CardDetails.Row(label: "Tabs", value: "23 tabs")]
        let growth = header(title: "Mail", rows: oneRow, displayNumber: 4).fittingSize.height
            - header(title: "Mail", rows: oneRow, displayNumber: nil).fittingSize.height
        #expect(growth < 6, "the chip added \(growth)pt, which is a row rather than a line height")

        let twoRows = oneRow + [CardDetails.Row(label: "Audio", value: "Playing")]
        #expect(
            header(title: "Mail", rows: twoRows, displayNumber: 4).fittingSize.height
                == header(title: "Mail", rows: twoRows, displayNumber: nil).fittingSize.height
        )
        #expect(header(title: "Mail", rows: twoRows, displayNumber: 4).fittingSize.width
            == CardMenuHeaderView.width)
    }

    /// With no facts at all the chip is still shown, and is still the only thing on its line.
    @Test func theChipAppearsEvenWithNoFacts() {
        let bare = header(title: "Mail", displayNumber: nil)
        let chipOnly = header(title: "Mail", displayNumber: 2)
        #expect(chipOnly.fittingSize.height > bare.fittingSize.height)
        #expect(chipOnly.fittingSize.width == CardMenuHeaderView.width)
    }

    /// The preview well is reserved whether or not a capture has arrived, so the menu does not change
    /// height when one lands a moment later.
    @Test func theHeaderIsTheSameHeightWithAndWithoutAThumbnail() {
        let context = CGContext(
            data: nil, width: 400, height: 250, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let image = context?.makeImage()
        #expect(image != nil, "failed to build a test capture")

        let without = header(title: "Mail")
        let with = header(title: "Mail", thumbnail: image)
        #expect(with.fittingSize.height == without.fittingSize.height)
        #expect(with.fittingSize.width == CardMenuHeaderView.width)
    }
}
