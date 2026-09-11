import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import VortexflowCore

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
        // Two displays, so every window resolves to one rather than being skipped the way it is
        // on a single-display machine.
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

    /// No arrangement draws a screen marker any more — the switch animation flies toward the
    /// display instead — but each window is still resolved to one, because VoiceOver says it.
    @Test("Every arrangement resolves each window to a display", arguments: OverlayLayoutStyle.allCases)
    func displaysResolveForEveryWindow(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 6)
        _ = render(subject)

        let resolved = subject.entries.compactMap { subject.display(for: $0) }
        #expect(resolved.count == subject.entries.count)
        #expect(Set(resolved.map(\.number)) == [1, 2])
        #expect(resolved.contains { $0.isBuiltIn })
        #expect(resolved.contains { !$0.isBuiltIn })
    }

    /// On one display there is nothing to tell apart, so no window resolves to one at all.
    @Test("A single display resolves no screens", arguments: OverlayLayoutStyle.allCases)
    func rendersWithoutResolvedDisplays(style: OverlayLayoutStyle) {
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
    /// The ring and coupling are visual-only. If they started moving seats, a click during the
    /// ignition would miss the wedge the pointer was on.
    @Test("Radial chrome does not move seats or the hub", arguments: [OverlayLayoutStyle.circular, .spiral])
    func radialChromeDoesNotMoveGeometry(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 12, selected: 1)
        let seats = subject.layout.radialSeats
        let hub = subject.layout.radialHubFrame
        _ = render(subject)
        #expect(subject.layout.radialSeats == seats)
        #expect(subject.layout.radialHubFrame == hub)
        #expect(subject.layout.commitsSelection(
            atPanelPoint: CGPoint(x: hub.midX, y: subject.layout.panelSize.height - hub.midY)
        ))
    }

    @Test("Both halves of the entrance render at the same size", arguments: OverlayLayoutStyle.allCases)
    func entranceRendersAtAConstantSize(style: OverlayLayoutStyle) {
        for count in [0, 1, 6, 25] {
            let subject = state(style: style, count: count, selected: count == 0 ? nil : 0)

            // Through the real entry points, so the test covers the sequence the controller
            // actually runs rather than a flag poked by hand.
            subject.beginPresentation()
            subject.isVisible = true
            let hidden = subject.layout.panelSize
            _ = render(subject)

            subject.reveal(token: subject.presentationID)
            let shown = subject.layout.panelSize
            _ = render(subject)
            #expect(subject.isRevealed)

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

        subject.isVisible = true
        subject.beginPresentation()
        let duringEntrance = subject.layout.positionedCards()
        subject.reveal(token: subject.presentationID)
        let after = subject.layout.positionedCards()

        #expect(duringEntrance == after)
    }

    @Test("Icon View renders mid-entrance", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersMidEntrance(style: OverlayLayoutStyle) {
        let subject = state(style: style, count: 9, viewMode: .icon)
        subject.beginPresentation()
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
        // one is badged so the selected-wedge chrome is exercised too.
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

    /// Both display arrangements have to render in Icon View, where the metadata block sits above
    /// the icon instead of below a screenshot and so has a different amount of room.
    @Test("Icon View renders with one and with two displays", arguments: OverlayLayoutStyle.allCases)
    func iconViewRendersWithEitherDisplayCount(style: OverlayLayoutStyle) {
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

    // MARK: - Glass and caption contrast

    /// The body intentionally transmits the desktop. Contrast is measured at
    /// the caption, not at an unrelated clear patch near the rim.
    @Test("Glass transmits the desktop while labels stay legible", arguments: [OverlayLayoutStyle.spiral, .circular])
    func wedgeColourSurvivesTheWallpaper(style: OverlayLayoutStyle) throws {
        for scheme in [ColorScheme.dark, .light] {
            let palette = OverlayPalette.forScheme(scheme)
            let appearance: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
            let subject = OverlayState()
            subject.availableContentWidth = 1400
            subject.availableContentHeight = 860
            subject.layoutStyle = style
            subject.load(entries: (0..<12).map { Fixture.entry(id: CGWindowID(4_100 + $0), app: "Glass", zOrder: $0) }, selectedIndex: 0)
            let geometry = try #require(subject.layout.radial)
            let size = subject.layout.panelSize
            let text = try #require(NSColor(palette.text).usingColorSpace(.sRGB))
            for selected in [false, true] {
                for hue in [0.0, 1.0 / 3, 2.0 / 3] {
                    let seat = geometry.seat(at: 2)
                    let tint = IconTint(hue: hue, vividness: 1)
                    // Two blank lines retain real caption geometry without ink
                    // contaminating the pixels sampled beneath the glyphs.
                    let entry = Fixture.entry(id: 4_101, app: "  \n  ")
                    var bodies: [Double] = []
                    for desktop in [Color.black, .white] {
                        let hosting = NSHostingView(rootView: ZStack {
                            desktop
                            WindowWedgeView(entry: entry, displayIcon: nil, seat: seat,
                                centre: subject.layout.radialCentre, panelSize: size,
                                isSelected: selected, isHovered: false, badgeCount: nil,
                                reduceMotion: true, metrics: subject.cardMetrics.scaled(by: subject.layout.radialScale),
                                tint: tint)
                        }
                        .environment(\.colorScheme, scheme)
                        .environment(\.overlayPalette, palette)
                        .frame(width: size.width, height: size.height))
                        hosting.appearance = NSAppearance(named: appearance)
                        hosting.frame = CGRect(origin: .zero, size: size)
                        hosting.layoutSubtreeIfNeeded()
                        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                        hosting.cacheDisplay(in: hosting.bounds, to: rep)
                        let sx = Double(rep.pixelsWide) / size.width
                        let sy = Double(rep.pixelsHigh) / size.height
                        func pixel(_ point: CGPoint) throws -> NSColor {
                            try #require(rep.colorAt(x: Int(point.x * sx), y: Int(point.y * sy))?.usingColorSpace(.sRGB))
                        }
                        // Clear of the icon and text; body should change with the
                        // wallpaper while caption protection remains local.
                        let angle = seat.startAngle + (seat.endAngle - seat.startAngle) * 0.18
                        let radius = seat.innerRadius + (seat.outerRadius - seat.innerRadius) * 0.55
                        let centre = subject.layout.radialCentre
                        let body = try pixel(CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle)))
                        bodies.append(0.2126 * body.redComponent + 0.7152 * body.greenComponent + 0.0722 * body.blueComponent)

                        let metrics = subject.cardMetrics.scaled(by: subject.layout.radialScale)
                        let captionY = seat.contentFrame.maxY - (metrics.titleFontSize * 2 + 4) / 2
                        for fraction in [-0.35, 0.0, 0.35] {
                            let background = try pixel(CGPoint(
                                x: seat.contentFrame.midX + seat.contentFrame.width * fraction, y: captionY))
                            let ratio = Self.rgbContrast(text: text, background: background)
                            #expect(ratio >= 4.5,
                                "\(style) \(scheme) selected=\(selected) hue=\(hue), caption \(fraction): \(ratio):1")
                        }
                    }
                    #expect(abs(bodies[0] - bodies[1]) > 0.05, "Glass body became opaque")
                    #expect(abs(bodies[0] - bodies[1]) < 0.50, "Glass lost its own tint/contrast floor")
                }
            }
        }
    }

    private static func rgbContrast(text: NSColor, background: NSColor) -> Double {
        func luminance(_ colour: NSColor) -> Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(colour.redComponent) + 0.7152 * linear(colour.greenComponent)
                + 0.0722 * linear(colour.blueComponent)
        }
        let alpha = text.alphaComponent
        let composed = NSColor(srgbRed: text.redComponent * alpha + background.redComponent * (1 - alpha),
            green: text.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: text.blueComponent * alpha + background.blueComponent * (1 - alpha), alpha: 1)
        let first = luminance(composed), second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// A dark wedge is a slab of glass lit on both arcs, brighter on the one facing the hub.
    ///
    /// Measured with one routine over both references — the peak of each card's inner arc against
    /// the darkest point of that same card's own body — the dark reference catches 6.8x on the inner
    /// arc and 4.0x on the outer, so the hub-facing face is decisively the brighter of the two. This
    /// overlay drew 3.8x and 3.6x: half the light inward, and the two arcs within one luminance of
    /// each other, which is what made the wedges read as evenly lit tiles rather than as volumes.
    ///
    /// Both halves of that are guarded, because both were wrong for different reasons. The level was
    /// wrong because a 6.5pt blur over a 3.2pt stroke throws most of a stroke's brightness into the
    /// haze either side of it — the same arithmetic that was costing the hub ring its peak. The
    /// *ordering* was wrong because opacity on a fixed-saturation hue cannot make one arc both
    /// brighter and paler than the other; that takes the white core inside the hued catch.
    @Test("A dark wedge is lit hardest on the arc facing the hub")
    func darkWedgeIsLitFromTheHub() throws {
        // One full turn, circular, so no seat has a radial neighbour. On a spiral the seat eight
        // places along sits directly outside this one, and its inner arc is a few points beyond this
        // one's outer arc — sampling out there measures the wrong card's light.
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = .circular
        subject.load(
            entries: (0..<8).map { index in
                WindowEntry(
                    windowID: CGWindowID(4_300 + index),
                    processID: pid_t(index + 1),
                    applicationName: "Lit \(index)",
                    applicationIcon: Self.solidIcon(
                        NSColor(hue: CGFloat(index) / 8, saturation: 1, brightness: 1, alpha: 1)
                    ),
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 0
        )

        let size = subject.layout.panelSize
        let hosting = NSHostingView(rootView: ZStack {
            Color.black
            OverlayView(state: subject, hoveredIndex: nil)
        }.frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let geometry = try #require(subject.layout.radial)
        let centre = subject.layout.radialCentre
        let scaleX = Double(rep.pixelsWide) / Double(size.width)
        let scaleY = Double(rep.pixelsHigh) / Double(size.height)

        func luminance(radius: CGFloat, angle: Double) throws -> Double {
            let colour = try #require(
                rep.colorAt(
                    x: Int(Double(centre.x + radius * CGFloat(cos(angle))) * scaleX),
                    y: Int(Double(centre.y + radius * CGFloat(sin(angle))) * scaleY)
                )?.usingColorSpace(.sRGB)
            )
            return 0.2126 * Double(colour.redComponent) * 255
                + 0.7152 * Double(colour.greenComponent) * 255
                + 0.0722 * Double(colour.blueComponent) * 255
        }

        // Skips seat 0, which is the selection and carries extra chrome of its own.
        for offset in 1..<geometry.seats {
            let seat = geometry.seat(at: offset)
            let sweep = seat.endAngle - seat.startAngle
            let depth = seat.outerRadius - seat.innerRadius

            // The arcs are blurred catches rather than strokes at a known radius, so each is the
            // peak over the band it occupies. Sampled a quarter and three quarters of the way round
            // the sweep: clear of the icon and label at the middle, and clear of the corner radius
            // at the ends, where there is no arc to measure.
            var innerArc = 0.0
            var outerArc = 0.0
            var body = Double.greatestFiniteMagnitude
            for fraction in [0.25, 0.75] {
                let angle = seat.startAngle + sweep * fraction
                for step in 0...12 {
                    let t = CGFloat(step) / 12
                    innerArc = max(innerArc, try luminance(
                        radius: seat.innerRadius - depth * 0.03 + t * depth * 0.15,
                        angle: angle
                    ))
                    outerArc = max(outerArc, try luminance(
                        radius: seat.outerRadius + depth * 0.03 - t * depth * 0.15,
                        angle: angle
                    ))
                }
                for step in 0...8 {
                    let t = 0.36 + CGFloat(step) / 8 * 0.28
                    body = min(body, try luminance(
                        radius: seat.innerRadius + t * depth,
                        angle: angle
                    ))
                }
            }

            #expect(
                innerArc > body * 2.5,
                "seat \(offset): inner arc \(Int(innerArc)) is only \(innerArc / body)x its body"
            )
            #expect(
                outerArc > body * 2.0,
                "seat \(offset): outer arc \(Int(outerArc)) is only \(outerArc / body)x its body"
            )
            #expect(
                innerArc > outerArc,
                "seat \(offset): outer arc \(Int(outerArc)) out-lights the inner \(Int(innerArc))"
            )
        }
    }

    private static func contrast(text: NSColor, againstLuminanceOf255 luminance: Double) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let background = channel(luminance / 255)
        let foreground = 0.2126 * channel(Double(text.redComponent))
            + 0.7152 * channel(Double(text.greenComponent))
            + 0.0722 * channel(Double(text.blueComponent))
        return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
    }

    /// The selected wedge's own label, across every hue the selected window might have.
    ///
    /// `wedgeColourSurvivesTheWallpaper` deliberately skips seat 0 — "the selection and deliberately
    /// a stronger colour" — so for as long as the selected body was the brand cyan, nothing measured
    /// it and nothing needed to. It is now the window's hue at the cyan's luminance, which makes it a
    /// surface that varies, and this is the sweep that covers it.
    ///
    /// Holding luminance is what should keep this safe, but "should" is the reason to render it: the
    /// wedge washes its glass over a frosted substrate and lights both arcs, so what the label
    /// actually sits on is the composite and not the palette colour. Cool hues are the case to watch,
    /// because they cannot reach the reference luminance by brightness alone and are pushed to full
    /// brightness with saturation spent instead — the palest result the treatment can produce.
    @Test("The selected wedge's label survives whatever hue its window has")
    func selectedWedgeLabelSurvivesItsHue() throws {
        for (appearance, scheme) in [
            (NSAppearance.Name.darkAqua, ColorScheme.dark),
            (.aqua, .light),
        ] {
            for (desktopName, desktop) in [("black", Color.black), ("white", Color.white)] {
                // Step 12 is the control: a greyscale icon yields no hue, so the selected wedge
                // falls back to the brand cyan and renders exactly what shipped before this. Every
                // hue is measured against it.
                var brandRatio: Double?
                // Control first, so there is a baseline to compare the hues against.
                for step in [12] + Array(0..<12) {
                    let selectedHue = Double(step) / 12
                    let isControl = step == 12
                    let subject = OverlayState()
                    subject.availableContentWidth = 1400
                    subject.availableContentHeight = 860
                    subject.layoutStyle = .spiral
                    let windowIDBase: UInt32 = 6_200 + UInt32(step) * 100
                    subject.load(
                        entries: Self.huedRing(
                            count: 8,
                            selectedHue: isControl ? nil : selectedHue,
                            windowIDBase: windowIDBase,
                            namePrefix: "Sel \(step)"
                        ),
                        // Seat 0 is the selection, which is what makes it the sample below.
                        selectedIndex: 0
                    )

                    let size = subject.layout.panelSize
                    let hosting = NSHostingView(rootView: ZStack {
                        desktop
                        OverlayView(state: subject, hoveredIndex: nil)
                    }.frame(width: size.width, height: size.height))
                    hosting.appearance = NSAppearance(named: appearance)
                    hosting.frame = CGRect(origin: .zero, size: size)
                    hosting.layoutSubtreeIfNeeded()
                    let rep = try #require(
                        hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
                    )
                    hosting.cacheDisplay(in: hosting.bounds, to: rep)

                    let geometry = try #require(subject.layout.radial)
                    let centre = subject.layout.radialCentre
                    let scaleX = Double(rep.pixelsWide) / Double(size.width)
                    let scaleY = Double(rep.pixelsHigh) / Double(size.height)

                    // Same off-centre body sample the sibling test takes, so the two are measuring
                    // the same kind of pixel: clear of the content box, both rim lights and the icon.
                    let seat = geometry.seat(at: 0)
                    let angle = seat.startAngle + (seat.endAngle - seat.startAngle) * 0.14
                    let radius = seat.innerRadius
                        + (seat.outerRadius - seat.innerRadius) * 0.55
                    let colour = try #require(
                        rep.colorAt(
                            x: Int(Double(centre.x + radius * CGFloat(cos(angle))) * scaleX),
                            y: Int(Double(centre.y + radius * CGFloat(sin(angle))) * scaleY)
                        )?.usingColorSpace(.sRGB)
                    )
                    let red = Double(colour.redComponent) * 255
                    let green = Double(colour.greenComponent) * 255
                    let blue = Double(colour.blueComponent) * 255
                    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

                    let text = try #require(
                        NSColor(OverlayPalette.forScheme(scheme).text).usingColorSpace(.sRGB)
                    )
                    let ratio = Self.contrast(text: text, againstLuminanceOf255: luminance)

                    guard !isControl else {
                        brandRatio = ratio
                        continue
                    }
                    // Measured against the brand, not against 4.5:1, and the control is what settles
                    // that. The selected wedge is deliberately the brightest body on the ring — which
                    // is why `wedgeColourSurvivesTheWallpaper` skips seat 0 — and it already sat below
                    // 4.5 before any of this: rendered, the control measures 3.52:1 in Dark Mode over
                    // a black desktop and 3.22:1 over a white one. Requiring 4.5 here would not be
                    // guarding this change, it would be quietly redesigning the selection's
                    // brightness. What is guarded is that no hue reads worse than the cyan it
                    // replaced.
                    //
                    // 4% is measured. Across the wheel the hues land between 3.41 and 4.20 against
                    // the brand's 3.52 — most of them *better*, because cyan sits near the bright end
                    // of what the treatment produces — and the worst case is yellow, 3.1% under it.
                    let baseline = try #require(brandRatio)
                    #expect(
                        ratio >= baseline * 0.96,
                        """
                        \(scheme) over \(desktopName): selected wedge at hue \(selectedHue) \
                        label is \(String(format: "%.2f", ratio)):1 on a body of \(Int(luminance)), \
                        against the brand's \(String(format: "%.2f", baseline)):1
                        """
                    )
                }
            }
        }
    }

    /// A ring of solid-icon windows where only seat 0's hue varies.
    ///
    /// - Parameter namePrefix: application names are cached against a sampled hue for the session,
    ///   so each sweep step needs its own or the first step's hue would be pinned to all of them.
    /// - Parameter selectedHue: `nil` gives seat 0 a greyscale icon, so it yields no tint and the
    ///   selection falls back to the brand — the control for what shipped before hues were used.
    private static func huedRing(
        count: Int,
        selectedHue: Double?,
        windowIDBase: UInt32,
        namePrefix: String
    ) -> [WindowEntry] {
        (0..<count).map { index -> WindowEntry in
            let icon: NSImage
            if index == 0 {
                icon = selectedHue.map { solidIcon(hue: $0) }
                    ?? solidIcon(NSColor(white: 0.32, alpha: 1))
            } else {
                icon = solidIcon(hue: Double(index) / Double(count))
            }
            return WindowEntry(
                windowID: CGWindowID(windowIDBase + UInt32(index)),
                processID: pid_t(index + 1),
                applicationName: "\(namePrefix) Seat \(index)",
                applicationIcon: icon,
                title: "Window \(index)",
                frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                isMinimized: false,
                zOrder: index,
                axElement: nil
            )
        }
    }

    private static func solidIcon(hue: Double) -> NSImage {
        solidIcon(NSColor(hue: CGFloat(hue), saturation: 1, brightness: 1, alpha: 1))
    }

    private static func solidIcon(_ colour: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        colour.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return image
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
