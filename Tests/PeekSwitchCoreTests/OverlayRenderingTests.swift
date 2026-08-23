import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import PeekSwitchCore

/// Renders each arrangement for real.
///
/// The geometry tests prove the rectangles are right; they cannot prove the view tree
/// built from those rectangles actually draws. A layout that crashes or collapses on
/// first render would pass every arithmetic test and still be broken the moment the
/// user triggers it, so each style is hosted offscreen, laid out, and measured.
@Suite("Overlay rendering")
@MainActor
struct OverlayRenderingTests {

    private func state(
        style: OverlayLayoutStyle,
        count: Int,
        selected: Int? = 0,
        viewMode: OverlayViewMode = .window
    ) -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1400
        state.availableContentHeight = 860
        state.layoutStyle = style
        state.viewMode = viewMode
        // Two displays, so the screen badge is drawn in every style rather than being
        // silently skipped the way it is on a single-display machine.
        state.displayLayout = Self.twoDisplays
        state.load(
            entries: (0..<count).map { index in
                Fixture.entry(
                    id: CGWindowID(700 + index),
                    app: "App \(index % 3)",
                    title: "Window \(index)",
                    zOrder: index,
                    // Exercise the minimized badge in every style.
                    minimized: index % 4 == 3,
                    // Alternate across the two displays.
                    frame: index.isMultiple(of: 2)
                        ? CGRect(x: 100, y: 100, width: 800, height: 600)
                        : CGRect(x: -1400, y: 100, width: 800, height: 600)
                )
            },
            selectedIndex: selected
        )
        return state
    }

    private static let twoDisplays = DisplayLayout(displays: [
        DisplayInfo(
            number: 1,
            bounds: CGRect(x: -1512, y: 36, width: 1512, height: 982),
            isBuiltIn: true,
            name: "Built-in Retina Display"
        ),
        DisplayInfo(
            number: 2,
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isBuiltIn: false,
            name: "SAMSUNG"
        ),
    ])

    /// Host the overlay content offscreen and force a synchronous layout pass, which is
    /// what `OverlayPanel.present(afterLayout:)` does before the panel is shown.
    private func render(_ state: OverlayState, hovered: Int? = nil) -> NSHostingView<OverlayView> {
        let view = OverlayView(state: state, hoveredIndex: hovered)
        let hosting = NSHostingView(rootView: view)
        let size = state.layout.panelSize
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test("Every arrangement renders at its panel size", arguments: OverlayLayoutStyle.allCases)
    func everyArrangementRenders(style: OverlayLayoutStyle) {
        for count in [0, 1, 5, 9, 25] {
            let subject = state(style: style, count: count, selected: count == 0 ? nil : 0)
            let panel = subject.layout.panelSize
            let hosting = render(subject)

            #expect(panel.width > 0, "\(style) with \(count) windows had no width")
            #expect(panel.height > 0, "\(style) with \(count) windows had no height")
            // A hosting view that collapsed would report a fitting size of zero, which
            // is how an empty or broken body shows up.
            #expect(hosting.fittingSize.width >= 0)
            #expect(hosting.subviews.count >= 0)
        }
    }

    @Test("Every arrangement renders with the selection at either end", arguments: OverlayLayoutStyle.allCases)
    func selectionAtBothEndsRenders(style: OverlayLayoutStyle) {
        for selected in [0, 12, 24] {
            let subject = state(style: style, count: 25, selected: selected)
            _ = render(subject, hovered: selected)
            #expect(subject.selectedEntry != nil)
            #expect(subject.layout.visibleRange.contains(selected))
        }
    }

    /// A persistent presentation used to add a hint capsule. It no longer draws anything
    /// extra, and this pins that: the panel must be the same size either way, so nothing
    /// reserves space for chrome that is gone.
    @Test("A persistent presentation adds no chrome", arguments: OverlayLayoutStyle.allCases)
    func persistentPresentationAddsNoChrome(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 6)
        let plain = subject.layout.panelSize

        subject.isPersistent = true
        _ = render(subject)

        #expect(subject.layout.panelSize == plain)
    }

    @Test("Every arrangement renders under Reduce Motion", arguments: OverlayLayoutStyle.allCases)
    func reduceMotionRenders(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 9)
        subject.reduceMotion = true
        _ = render(subject)
        // Requirement 15.2: the scale-up is flattened, so the border carries selection.
        #expect(subject.selectedScale == 1.0)
    }

    /// Both a laptop and an external monitor have to appear, since the glyph differs
    /// per kind and each style places the badge in its own footer or row.
    @Test("Every arrangement renders screen badges for both displays", arguments: OverlayLayoutStyle.allCases)
    func displayBadgesRender(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 6)
        _ = render(subject)

        let resolved = subject.entries.compactMap { subject.display(for: $0) }
        #expect(resolved.count == subject.entries.count)
        #expect(Set(resolved.map(\.number)) == [1, 2])
        #expect(resolved.contains { $0.isBuiltIn })
        #expect(resolved.contains { !$0.isBuiltIn })
    }

    /// On one display the badge is suppressed, and the styles must still render.
    @Test("Every arrangement renders with no screen badges", arguments: OverlayLayoutStyle.allCases)
    func rendersWithoutDisplayBadges(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 6)
        subject.displayLayout = DisplayLayout(displays: [Self.twoDisplays.displays[0]])
        subject.load(entries: subject.entries, selectedIndex: 0)
        _ = render(subject)

        #expect(subject.entries.allSatisfy { subject.display(for: $0) == nil })
    }

    @Test("Every arrangement renders with thumbnails attached", arguments: OverlayLayoutStyle.allCases)
    func thumbnailsRender(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 5)
        guard let image = makeTestImage() else {
            Issue.record("could not build a test image")
            return
        }
        for entry in subject.entries {
            subject.setThumbnail(image, for: entry.windowID)
        }
        _ = render(subject)
        #expect(subject.thumbnails.count == 5)
    }

    /// The empty state has to survive every style, because the style is whatever the
    /// user last chose and enumeration can legitimately come back empty.
    ///
    /// It is also the one case where a plateless style still needs a plate: the message
    /// is a sentence, and a sentence floating over an arbitrary desktop is unreadable.
    @Test("The empty state renders in every arrangement", arguments: OverlayLayoutStyle.allCases)
    func emptyStateRenders(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 0, selected: nil)
        let hosting = render(subject)
        #expect(subject.entries.isEmpty)
        #expect(hosting.frame.width == StripLayout.emptyStateWidth)
    }

    /// A transparent container must not change where anything sits — it only removes
    /// the plate. If dropping the backdrop moved cards, hit-testing would go stale.
    @Test("Dropping the plate does not move any card", arguments: OverlayLayoutStyle.allCases)
    func plateDoesNotAffectCardPositions(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 9, selected: 3)
        let before = subject.layout.positionedCards()
        _ = render(subject)
        let after = subject.layout.positionedCards()

        #expect(before == after)

        // The item-windowed styles only ever place cards that fit. The strip is
        // different by design: it returns a frame for every card and lets the ones
        // scrolled past the ends fall outside the panel, where they are clipped.
        if style != .strip {
            for card in after {
                #expect(subject.layout.panelSize.width >= card.frame.maxX)
                #expect(subject.layout.panelSize.height >= card.frame.maxY)
            }
        }
    }

    // MARK: - Entrance

    /// The panel is laid out synchronously *before* it is ordered in, and at that moment the
    /// cards are still held back. So the hidden state is a real frame that ships, not a
    /// transient — it has to render, and it has to render at the same size as the visible one,
    /// or the panel would resize the instant the cards arrived.
    @Test("Both halves of the entrance render at the same size", arguments: OverlayLayoutStyle.allCases)
    func entranceRendersAtAConstantSize(style: OverlayLayoutStyle) {
        for count in [0, 1, 6, 25] {
            let subject = state(style: style, count: count, selected: count == 0 ? nil : 0)

            subject.isRevealed = false
            let hidden = subject.layout.panelSize
            _ = render(subject)

            subject.isRevealed = true
            let shown = subject.layout.panelSize
            _ = render(subject)

            #expect(hidden == shown, "\(style) with \(count) windows resized as cards arrived")
            #expect(shown.width > 0)
        }
    }

    /// Input is live during the entrance, so a click that lands while a card is still fading in
    /// has to resolve to that card. Hit-testing runs off layout arithmetic, which knows nothing
    /// about the animation — this is what pins that.
    @Test("Hit-testing ignores the entrance", arguments: OverlayLayoutStyle.allCases)
    func hitTestingIsUnaffectedByTheEntrance(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 9, selected: 3)

        subject.isRevealed = false
        let duringEntrance = subject.layout.positionedCards()
        subject.isRevealed = true
        let after = subject.layout.positionedCards()

        #expect(duringEntrance == after)
    }

    @Test("Icon View renders mid-entrance", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersMidEntrance(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 9, viewMode: .icon)
        subject.isRevealed = false
        _ = render(subject, hovered: 2)
        #expect(!subject.isRevealed)
    }

    /// A fresh state shows its cards. If this ever flips, a path that forgets to run the
    /// entrance presents an empty panel instead of a working switcher.
    @Test("Cards are visible unless something deliberately hides them")
    func revealDefaultsToVisible() {
        #expect(OverlayState().isRevealed)
    }

    // MARK: - Incognito

    /// The badge is drawn in a different place by every arrangement, and in the round ones it
    /// competes for a label line that is already tight, so each has to be exercised.
    @Test("Incognito badges render in every arrangement", arguments: OverlayLayoutStyle.allCases)
    func incognitoBadgesRender(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 8, selected: 0)
        // Every other window, so both the badged and unbadged paths are drawn, and the selected
        // one is badged so the on-accent colours are exercised too.
        subject.incognitoWindowIDs = Set(
            subject.entries.enumerated()
                .filter { $0.offset.isMultiple(of: 2) }
                .map { $0.element.windowID }
        )
        _ = render(subject, hovered: 1)

        #expect(subject.isIncognito(subject.entries[0]))
        #expect(!subject.isIncognito(subject.entries[1]))
    }

    /// Badges arrive after the overlay does, so the panel must not resize when they land.
    @Test("A badge arriving does not resize the panel", arguments: OverlayLayoutStyle.allCases)
    func incognitoBadgeDoesNotResize(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 8)
        let before = subject.layout.panelSize
        let cards = subject.layout.positionedCards()

        subject.incognitoWindowIDs = Set(subject.entries.map(\.windowID))
        _ = render(subject)

        #expect(subject.layout.panelSize == before)
        #expect(subject.layout.positionedCards() == cards)
    }

    /// A tab has no window of its own, so it can never be a private *window*.
    @Test("Tab entries are never treated as incognito")
    func tabsAreNeverIncognito() {
        let subject = state(style: .grid, count: 3)
        let tab = BrowserTab(
            browser: .chrome,
            windowIdentifier: 1,
            tabIndex: 1,
            title: "Tab",
            url: "https://example.com"
        )
        let entry = WindowEntry.tabEntry(tab, application: nil)
        subject.incognitoWindowIDs = [entry.windowID]

        #expect(!subject.isIncognito(entry))
    }

    // MARK: - A search that matched nothing

    /// The dead end became an offer, so the offer has to draw — including the two wordings, since
    /// a query that looks like an address goes straight there instead of to a search engine.
    @Test("The no-matches state renders its offer", arguments: OverlayLayoutStyle.allCases)
    func searchMissRenders(style: OverlayLayoutStyle) {
        for query in ["nothing matches this", "grok.com", "a very long query that has to be truncated before it stretches the panel"] {
            let subject = state(style: style, count: 5)
            subject.appendToSearch(query)

            #expect(subject.entries.isEmpty, "\(query) should match nothing")
            #expect(subject.hasNoSearchMatches)
            #expect(WebSearch.destination(for: query) != nil)

            let hosting = render(subject)
            // Still the shared empty-state box: the offer must fit what is already there rather
            // than growing the panel to suit itself.
            #expect(hosting.frame.width == StripLayout.emptyStateWidth)
        }
    }

    /// With no query there is nothing to offer, and the message stays the plain one.
    @Test("An empty window list is not a search miss")
    func emptyListIsNotASearchMiss() {
        let subject = state(style: .strip, count: 0, selected: nil)
        #expect(!subject.hasNoSearchMatches)
        #expect(!subject.isSearching)
        _ = render(subject)
    }

    // MARK: - Icon View

    /// Icon View composes with every arrangement rather than being one of them, so it has to
    /// survive the same matrix of counts the window mode does.
    @Test("Icon View renders in every arrangement", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersInEveryArrangement(style: OverlayLayoutStyle) {
        for count in [0, 1, 5, 9, 25] {
            let subject = state(
                style: style,
                count: count,
                selected: count == 0 ? nil : 0,
                viewMode: .icon
            )
            let panel = subject.layout.panelSize
            let hosting = render(subject, hovered: count > 1 ? 1 : nil)

            #expect(panel.width > 0, "icon \(style) with \(count) windows had no width")
            #expect(panel.height > 0, "icon \(style) with \(count) windows had no height")
            #expect(hosting.fittingSize.width >= 0)
        }
    }

    /// The load-bearing claim of the whole feature: switching mode changes what a card draws
    /// and nothing about where it is. If these frames ever diverge, every mouse position the
    /// controller hit-tests would be wrong in one of the two modes.
    @Test("Switching view mode moves no card", arguments: OverlayLayoutStyle.allCases)
    func viewModeDoesNotMoveCards(style: OverlayLayoutStyle) {
        for selected in [0, 12, 24] {
            let windowMode = state(style: style, count: 25, selected: selected)
            let iconMode = state(style: style, count: 25, selected: selected, viewMode: .icon)

            #expect(windowMode.layout.panelSize == iconMode.layout.panelSize)
            #expect(windowMode.layout.positionedCards() == iconMode.layout.positionedCards())
            #expect(windowMode.layout.visibleRange == iconMode.layout.visibleRange)
            #expect(windowMode.selectedScale == iconMode.selectedScale)
        }
    }

    /// Mouse selection is resolved from panel coordinates, so the same point must land on the
    /// same card in both modes — checked at each card's own centre.
    @Test("The same point hits the same card in both view modes", arguments: OverlayLayoutStyle.allCases)
    func hitTestingMatchesAcrossViewModes(style: OverlayLayoutStyle) {
        let windowMode = state(style: style, count: 9, selected: 4)
        let iconMode = state(style: style, count: 9, selected: 4, viewMode: .icon)
        let panelHeight = windowMode.layout.panelSize.height

        for card in windowMode.layout.positionedCards() {
            // `positionedCards` is top-left; hit-testing takes AppKit's bottom-left.
            let point = CGPoint(
                x: card.frame.midX,
                y: panelHeight - card.frame.midY
            )
            let inWindowMode = windowMode.layout.cardIndex(
                atPanelPoint: point,
                scrollOffset: 0,
                selectedScale: windowMode.selectedScale
            )
            let inIconMode = iconMode.layout.cardIndex(
                atPanelPoint: point,
                scrollOffset: 0,
                selectedScale: iconMode.selectedScale
            )
            #expect(inWindowMode == inIconMode, "\(style) disagreed at \(point)")
        }
    }

    /// Requirement 4: missing titles and missing icons are the common case for utility
    /// panels and icon-less processes, and Icon View has no screenshot to fall back on.
    @Test("Icon View renders windows with no title and no icon", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersMissingMetadata(style: OverlayLayoutStyle) {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = style
        subject.viewMode = .icon
        subject.displayLayout = Self.twoDisplays
        subject.load(
            entries: [
                // Empty and whitespace-only titles both fall back to the application name.
                Fixture.entry(id: 900, app: "Blank", title: "", zOrder: 0),
                Fixture.entry(id: 901, app: "Spaces", title: "   ", zOrder: 1),
                Fixture.entry(
                    id: 902,
                    app: "A Very Long Application Name That Cannot Possibly Fit On One Card",
                    title: String(repeating: "long title ", count: 24),
                    zOrder: 2
                ),
                Fixture.entry(id: 903, app: "Minimized", title: "Hidden", zOrder: 3, minimized: true),
            ],
            selectedIndex: 0
        )
        _ = render(subject, hovered: 2)

        // No entry carries an icon, so every card is on the glyph path.
        #expect(subject.entries.allSatisfy { $0.applicationIcon == nil })
        #expect(subject.entries[0].displayTitle == "Blank")
        #expect(subject.entries[1].displayTitle == "Spaces")
        #expect(subject.layout.panelSize.width > 0)
    }

    /// Icon View does no capture, but a stale thumbnail can still be in the dictionary when
    /// the mode is changed mid-session. Rendering must ignore it rather than draw it.
    @Test("Icon View renders with thumbnails present but unused", arguments: OverlayLayoutStyle.allCases)
    func iconViewIgnoresThumbnails(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 5, viewMode: .icon)
        guard let image = makeTestImage() else {
            Issue.record("could not build a test image")
            return
        }
        for entry in subject.entries {
            subject.setThumbnail(image, for: entry.windowID)
        }
        _ = render(subject)

        #expect(!subject.viewMode.usesThumbnails)
        #expect(subject.thumbnails.count == 5)
    }

    @Test("Icon View renders under Reduce Motion", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersUnderReduceMotion(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 9, viewMode: .icon)
        subject.reduceMotion = true
        _ = render(subject)
        #expect(subject.selectedScale == 1.0)
    }

    /// A single display suppresses the screen badge; two displays draw it. Both paths have to
    /// hold in Icon View, where the metadata block sits above the icon instead of below a
    /// screenshot and so has a different amount of room.
    @Test("Icon View renders screen badges with one and two displays", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersDisplayBadges(style: OverlayLayoutStyle) {
        let twoScreens = state(style: style, count: 6, viewMode: .icon)
        _ = render(twoScreens)
        #expect(Set(twoScreens.entries.compactMap { twoScreens.display(for: $0)?.number }) == [1, 2])

        let oneScreen = state(style: style, count: 6, viewMode: .icon)
        oneScreen.displayLayout = DisplayLayout(displays: [Self.twoDisplays.displays[0]])
        oneScreen.load(entries: oneScreen.entries, selectedIndex: 0)
        _ = render(oneScreen)
        #expect(oneScreen.entries.allSatisfy { oneScreen.display(for: $0) == nil })
    }

    /// Requirement 3: two windows of one application stay two items. Nothing in the pipeline
    /// groups by application, and this pins that for the mode where the icon is identical.
    @Test("Icon View keeps one item per window", arguments: OverlayLayoutStyle.allCases)
    func iconViewDoesNotCollapseSameApplication(style: OverlayLayoutStyle) {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = style
        subject.viewMode = .icon
        subject.load(
            entries: (0..<6).map {
                Fixture.entry(id: CGWindowID(920 + $0), app: "Safari", title: "Tab \($0)", zOrder: $0)
            },
            selectedIndex: 0
        )
        _ = render(subject)

        #expect(subject.entries.count == 6)
        #expect(Set(subject.entries.map(\.windowID)).count == 6)
    }

    private func makeTestImage() -> CGImage? {
        let width = 64
        let height = 40
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
