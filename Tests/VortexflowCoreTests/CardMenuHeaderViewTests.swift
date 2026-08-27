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
        icon: NSImage? = nil
    ) -> NSHostingView<CardMenuHeaderView> {
        let view = CardMenuHeaderView(
            details: CardDetails(title: title, source: "Google Chrome", rows: rows),
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

    /// The actions row is the second thing in the menu that could widen it, so it is pinned to the
    /// same width as the header. A row that sized itself to its captions would have undone the fix.
    @Test func theActionsRowMatchesTheHeaderWidthAtEveryCount() {
        let all: [CardMenuItem] = [
            .searchWindowTabs(count: 23),
            .muteAudible,
            .minimizeWindow,
            .closeWindow,
            .pinApplication(name: "Google Chrome"),
        ]
        for count in 1...all.count {
            let view = CardMenuActionsView(
                actions: Array(all.prefix(count)),
                hover: CardMenuHoverModel()
            ) { _ in }
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            #expect(
                hosting.fittingSize.width == CardMenuHeaderView.width,
                "\(count) action(s) gave a width of \(hosting.fittingSize.width)"
            )
        }
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
