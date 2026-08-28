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
        applicationName: String = "Google Chrome",
        title: String = "A window",
        identifyingSource: String? = nil,
        rows: [CardDetails.Row] = [],
        thumbnail: CGImage? = nil,
        icon: NSImage? = nil,
        windowControls: [CardMenuItem] = [],
        media: [CardMenuItem] = [],
        contents: [CardMenuItem] = [],
        moveResize: [CardMenuItem] = [],
        fillArrange: [CardMenuItem] = [],
        placement: [CardMenuItem] = [],
        hover: CardMenuHoverModel = CardMenuHoverModel()
    ) -> NSHostingView<CardMenuHeaderView> {
        let view = CardMenuHeaderView(
            details: CardDetails(
                title: title,
                source: identifyingSource.map { "\($0) · \(applicationName)" } ?? applicationName,
                applicationName: applicationName,
                identifyingSource: identifyingSource,
                rows: rows
            ),
            thumbnail: thumbnail,
            icon: icon,
            windowControls: windowControls,
            media: media,
            contents: contents,
            moveResize: moveResize,
            fillArrange: fillArrange,
            placement: placement,
            hover: hover,
            onAction: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    /// A header with everything on it, which is the layout the corner placement is really about.
    private func fullHeader(hover: CardMenuHoverModel = CardMenuHoverModel())
        -> NSHostingView<CardMenuHeaderView> {
        header(
            applicationName: "Google Chrome",
            title: "YouTube Music",
            identifyingSource: "music.youtube.com",
            rows: [
                CardDetails.Row(label: "Desktop", value: "Another · just now"),
                CardDetails.Row(label: "Audio", value: "Playing"),
                CardDetails.Row(label: "Window", value: "1 of 3"),
            ],
            windowControls: [.minimizeWindow, .closeWindow],
            media: [.previousTrack, .pausePlayback, .nextTrack],
            contents: [.searchWindowTabs(count: 23)],
            moveResize: WindowTile.moveResize.map(CardMenuItem.tileWindow),
            fillArrange: WindowTile.fillArrange.map(CardMenuItem.tileWindow),
            placement: [.enterFullScreen],
            hover: hover
        )
    }

    /// The point of the whole view.
    @Test func theHeaderIsTheSameWidthWhateverTheApplicationName() {
        let short = header(applicationName: "Mail")
        let long = header(
            applicationName: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5)
        )
        #expect(short.fittingSize.width == CardMenuHeaderView.width)
        #expect(long.fittingSize.width == CardMenuHeaderView.width)
    }

    /// The application name is one line. The window title used to be allowed a second, and that is
    /// what pushed the grids down; the picture is the window now, so the name above it truncates.
    @Test func theApplicationNameStaysOnOneLine() {
        let short = header(applicationName: "Mail")
        let long = header(
            applicationName: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5)
        )
        #expect(long.fittingSize.height == short.fittingSize.height)
        #expect(long.fittingSize.width == CardMenuHeaderView.width)
    }

    /// The window title sits under the preview, the way the hub names this card. A title that is
    /// just the application name again is omitted, so Slack does not say "Slack" twice.
    @Test func theWindowTitleSitsUnderThePreview() {
        let named = header(applicationName: "Google Chrome", title: "YouTube Music")
        let sameAsApp = header(applicationName: "Slack", title: "Slack")
        #expect(named.fittingSize.height > sameAsApp.fittingSize.height)
        #expect(named.fittingSize.width == CardMenuHeaderView.width)
    }

    @Test func aLongWindowTitleCostsAtMostOneExtraLine() {
        let short = header(applicationName: "Chrome", title: "Mail")
        let long = header(
            applicationName: "Chrome",
            title: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5)
        )
        let growth = long.fittingSize.height - short.fittingSize.height
        #expect(growth > 0)
        #expect(growth < 24, "growth of \(growth)pt suggests the title is not capped at two lines")
    }

    @Test func theMediaRowDoesNotWidenTheHeader() {
        #expect(
            header(
                applicationName: "Google Chrome",
                media: [.previousTrack, .pausePlayback, .nextTrack]
            ).fittingSize.width == CardMenuHeaderView.width
        )
    }

    /// Chrome's transport is a tight cluster, not a captioned glyph row. Captions under
    /// Previous / Pause / Next would spend a line the Skip glyphs already say.
    @Test func theTransportClusterStaysCompact() {
        let without = header(applicationName: "Google Chrome")
        let with = header(
            applicationName: "Google Chrome",
            media: [.previousTrack, .pausePlayback, .nextTrack]
        )
        let growth = with.fittingSize.height - without.fittingSize.height
        #expect(growth > 0)
        #expect(growth < 56, "growth of \(growth)pt suggests the transport grew captions")
    }

    /// Facts have to actually reach the layout; a grid that silently rendered nothing would still
    /// pass the width test.
    @Test func factsAddHeightWithoutAddingWidth() {
        let bare = header(applicationName: "Mail")
        let detailed = header(
            applicationName: "Mail",
            rows: [
                CardDetails.Row(label: "Desktop", value: "Another · 20m ago"),
                CardDetails.Row(label: "Tabs", value: "23 tabs"),
            ]
        )
        #expect(detailed.fittingSize.height > bare.fittingSize.height)
        #expect(detailed.fittingSize.width == CardMenuHeaderView.width)
    }

    /// A value long enough to widen the column is truncated instead.
    @Test func anOverlongFactValueDoesNotWidenTheHeader() {
        let view = header(
            applicationName: "Mail",
            rows: [
                CardDetails.Row(
                    label: "Desktop",
                    value: String(repeating: "Another space a long time ago ", count: 6)
                )
            ]
        )
        #expect(view.fittingSize.width == CardMenuHeaderView.width)
    }

    /// A ceiling on the whole header, because the menu still has to fit on screen when it opens
    /// near the bottom edge. The two placement grids live inside this block, and so do the title
    /// under the preview, the facts, and the Chrome-style transport. Every row `CardDetails` can
    /// produce is present here.
    @Test func theFullyPopulatedHeaderStaysWithinItsBudget() {
        let view = header(
            applicationName: "Google Chrome",
            title: String(repeating: "Quarterly Planning Document — Shared Folder ", count: 5),
            identifyingSource: "github.com",
            rows: [
                CardDetails.Row(label: "Desktop", value: "Another · 20m ago"),
                CardDetails.Row(label: "State", value: "Minimized"),
                CardDetails.Row(label: "Tabs", value: "23 tabs"),
                CardDetails.Row(label: "Session", value: "Private window"),
                CardDetails.Row(label: "Audio", value: "Playing · microphone"),
                CardDetails.Row(label: "Window", value: "2 of 3"),
            ],
            windowControls: [.minimizeWindow, .closeWindow],
            media: [.previousTrack, .pausePlayback, .nextTrack],
            contents: [.searchWindowTabs(count: 23)],
            moveResize: WindowTile.moveResize.map(CardMenuItem.tileWindow),
            fillArrange: WindowTile.fillArrange.map(CardMenuItem.tileWindow),
            placement: [.enterFullScreen]
        )
        #expect(
            view.fittingSize.height < 600,
            "header is \(view.fittingSize.height)pt tall; the menu still has to fit on screen"
        )
    }

    /// The content row is the other thing in the menu that could widen it, so it is pinned to the
    /// header's width. A row that sized itself to its captions would have undone the fix.
    @Test func theContentRowMatchesTheHeaderWidth() {
        let actions: [CardMenuItem] = [.searchWindowTabs(count: 23), .muteAudible]
        for count in 1...actions.count {
            let width = rowWidth(Array(actions.prefix(count)))
            #expect(
                width == CardMenuHeaderView.width,
                "\(count) action(s) gave a width of \(width)"
            )
        }
    }

    /// The corner groups live inside the header now, so they are the other thing that could widen it.
    @Test func theCornerGroupsDoNotWidenTheHeader() {
        #expect(fullHeader().fittingSize.width == CardMenuHeaderView.width)
        #expect(
            header(applicationName: "Mail", windowControls: [.minimizeWindow, .closeWindow])
                .fittingSize.width == CardMenuHeaderView.width
        )
        #expect(
            header(
                applicationName: "Mail",
                contents: [.searchWindowTabs(count: nil)],
                moveResize: WindowTile.moveResize.map(CardMenuItem.tileWindow),
                fillArrange: WindowTile.fillArrange.map(CardMenuItem.tileWindow)
            )
                .fittingSize.width == CardMenuHeaderView.width
        )
    }

    /// The two grids and the Full Screen row have to actually land in the layout. A section that
    /// compiled but drew at zero height would still pass the width tests.
    @Test func theArrangementAddsHeightBelowThePreview() {
        let without = header(
            applicationName: "Mail",
            windowControls: [.minimizeWindow, .closeWindow]
        )
        let with = fullHeader()
        #expect(with.fittingSize.height > without.fittingSize.height)
        #expect(with.fittingSize.width == CardMenuHeaderView.width)
    }

    /// Highlighting a glyph must not move anything. The identity bar and the grids sit against the
    /// block's edges, so a hover that changed a button's size would shift the preview beside it.
    @Test func togglingPauseDoesNotResizeTheHeader() {
        let hover = CardMenuHoverModel()
        let view = fullHeader(hover: hover)
        let resting = view.fittingSize
        hover.togglePlaybackPaused()
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize == resting, "flipping play/pause resized the header")
    }

    @Test func hoveringAGlyphDoesNotResizeTheHeader() {
        let hover = CardMenuHoverModel()
        let view = fullHeader(hover: hover)
        let resting = view.fittingSize

        for action in [
            CardMenuItem.closeWindow,
            .minimizeWindow,
            .pausePlayback,
            .searchWindowTabs(count: 23),
            .tileWindow(.leftHalf),
            .tileWindow(.fill),
            .enterFullScreen,
        ] {
            hover.setHovered(action, true)
            view.layoutSubtreeIfNeeded()
            #expect(view.fittingSize == resting, "hovering \(action) resized the header")
            hover.setHovered(action, false)
        }
    }

    /// Hover is keyed on the action, not on a position, so one model serves every group. Two groups
    /// each believing their own first glyph was hovered is what an index would have allowed.
    @Test func onlyOneGlyphIsEverHovered() {
        let hover = CardMenuHoverModel()
        hover.setHovered(.minimizeWindow, true)
        #expect(hover.isHovered(.minimizeWindow))
        #expect(!hover.isHovered(.tileWindow(.leftHalf)))

        hover.setHovered(.tileWindow(.leftHalf), true)
        #expect(hover.isHovered(.tileWindow(.leftHalf)))
        #expect(!hover.isHovered(.minimizeWindow), "two glyphs both believe they are hovered")
    }

    /// Leaving a glyph that is no longer the hovered one must not clear the highlight from the one that
    /// is — the order `onHover` reports enter and exit in is not guaranteed.
    @Test func leavingAStaleGlyphDoesNotClearTheCurrentOne() {
        let hover = CardMenuHoverModel()
        hover.setHovered(.minimizeWindow, true)
        hover.setHovered(.closeWindow, true)
        hover.setHovered(.minimizeWindow, false)
        #expect(hover.isHovered(.closeWindow))
    }

    private func rowWidth(_ actions: [CardMenuItem]) -> CGFloat {
        let view = CardMenuGlyphRow(
            actions: actions, hover: CardMenuHoverModel(), onAction: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.width
    }

    /// Tab search is a labelled row under the preview, not a captioned glyph at the foot of the menu.
    @Test func tabSearchAddsHeightBelowThePreviewWithoutWidening() {
        let without = header(
            applicationName: "Google Chrome",
            windowControls: [.minimizeWindow, .closeWindow]
        )
        let with = header(
            applicationName: "Google Chrome",
            windowControls: [.minimizeWindow, .closeWindow],
            contents: [.searchWindowTabs(count: 23)]
        )
        #expect(with.fittingSize.height > without.fittingSize.height)
        #expect(with.fittingSize.width == CardMenuHeaderView.width)
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

        let without = header(applicationName: "Mail")
        let with = header(applicationName: "Mail", thumbnail: image)
        #expect(with.fittingSize.height == without.fittingSize.height)
        #expect(with.fittingSize.width == CardMenuHeaderView.width)
    }
}
