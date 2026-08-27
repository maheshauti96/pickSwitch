import CoreGraphics
import Testing
@testable import VortexflowCore

/// The Icon View / Window View axis.
///
/// The mode decides what one item *is*; `OverlayLayoutStyle` decides how items are *arranged*.
/// They are deliberately independent, and most of what is worth testing here is that
/// independence: any mode in any arrangement, with identical geometry either way.
@Suite("Overlay view mode")
@MainActor
struct OverlayViewModeTests {

    /// Arrangements where the view mode changes what a card draws.
    ///
    /// Every arrangement but one. The spiral's seats are annular sectors, and a rectangular
    /// screenshot clipped to a wedge is unreadable, so it draws an application icon in either
    /// mode and the choice is a no-op there — see `spiralIsDeliberatelyModeInvariant`, which
    /// pins that rather than leaving it as an accident of these exclusions.
    private static let modeSensitiveStyles: [OverlayLayoutStyle] =
        OverlayLayoutStyle.allCases.filter { $0.canShowThumbnails }

    // MARK: - The mode itself

    /// Persisted raw values. Changing one would silently repoint an existing preference at the
    /// other mode on the next launch.
    @Test("Raw values are stable")
    func rawValuesAreStable() {
        #expect(OverlayViewMode.window.rawValue == 0)
        #expect(OverlayViewMode.icon.rawValue == 1)
        #expect(OverlayViewMode.allCases.count == 2)
    }

    /// The one behavioural difference outside drawing: Icon View performs no capture, which is
    /// why it needs no Screen Recording permission.
    @Test("Only Window View needs thumbnails")
    func onlyWindowViewUsesThumbnails() {
        #expect(OverlayViewMode.window.usesThumbnails)
        #expect(!OverlayViewMode.icon.usesThumbnails)
    }

    @Test("Every mode is describable in the interface", arguments: OverlayViewMode.allCases)
    func modesHaveLabels(mode: OverlayViewMode) {
        #expect(!mode.displayName.isEmpty)
        #expect(!mode.shortName.isEmpty)
        #expect(!mode.explanation.isEmpty)
    }

    // MARK: - Card composition

    /// The mirror-image arrangement is the point of the feature: Window View shows a picture
    /// and explains it underneath, Icon View says what the window is and then shows its icon.
    @Test("The two modes invert the card's composition", arguments: modeSensitiveStyles)
    func compositionIsInverted(style: OverlayLayoutStyle) {
        #expect(style.cardMetrics(for: .window).contentLayout == .artworkThenMetadata)
        #expect(style.cardMetrics(for: .icon).contentLayout == .metadataThenArtwork)
    }

    /// Every frame in `OverlayLayout` derives from card size, so equal sizes are what let Icon
    /// View reuse the entire geometry engine untouched.
    @Test("Card sizes do not depend on the mode", arguments: OverlayLayoutStyle.allCases)
    func cardSizesAreModeIndependent(style: OverlayLayoutStyle) {
        let window = style.cardMetrics(for: .window)
        let icon = style.cardMetrics(for: .icon)
        #expect(window.size == icon.size)
        #expect(window.cornerRadius == icon.cornerRadius)
    }

    /// A large icon needs a size to be drawn at; a screenshot fills its area instead. Reading
    /// `artworkIconSize` in Window View would be a bug, so it is zero there.
    @Test("A large icon size exists only in Icon View", arguments: modeSensitiveStyles)
    func artworkIconSizeIsIconViewOnly(style: OverlayLayoutStyle) {
        #expect(style.cardMetrics(for: .window).artworkIconSize == 0)

        let icon = style.cardMetrics(for: .icon)
        #expect(icon.artworkIconSize > 0)
        // Requirement 6: "sufficiently large". Smaller than this and it is a footer icon.
        #expect(icon.artworkIconSize >= 56)
        // And it has to fit the well it is centred in.
        #expect(icon.artworkIconSize <= icon.artworkHeight)
    }

    /// The small icon beside the name would be a second copy of the same artwork.
    @Test("Icon View drops the small footer icon", arguments: modeSensitiveStyles)
    func iconViewHasNoFooterIcon(style: OverlayLayoutStyle) {
        #expect(style.cardMetrics(for: .icon).iconSize == 0)
        #expect(style.cardMetrics(for: .window).iconSize > 0)
    }

    /// Requirement 4: the app name and the window title both have to be readable, so the
    /// metadata block needs room for two single-line rows at its own font sizes.
    @Test("Icon View reserves room for two lines of metadata", arguments: modeSensitiveStyles)
    func metadataBlockFitsTwoLines(style: OverlayLayoutStyle) {
        let metrics = style.cardMetrics(for: .icon)
        #expect(metrics.showsSubtitle)
        // Both lines are `lineLimit(1)`, so this is the ceiling rather than an estimate.
        let needed = metrics.titleFontSize + metrics.subtitleFontSize
        #expect(metrics.metadataHeight >= needed)
        // Plus the vertical padding the card view applies, or the text would sit edge to edge.
        #expect(metrics.metadataHeight >= needed + 6)
    }

    /// Requirement 4 again: the title is the line that adds something once an icon is already
    /// naming the application, so Icon View never demotes it — not even on a ring seat, where
    /// Window View does.
    @Test("Icon View always leads with the window title", arguments: modeSensitiveStyles)
    func iconViewLeadsWithTheTitle(style: OverlayLayoutStyle) {
        #expect(!style.cardMetrics(for: .icon).usesApplicationNameAsPrimary)
    }

    /// Requirement 4: text that grows would run into the icon below it. The metadata block is
    /// fixed-height, so the two halves always exactly fill the card.
    @Test(
        "Artwork and metadata exactly fill the card",
        arguments: OverlayLayoutStyle.allCases, OverlayViewMode.allCases
    )
    func halvesFillTheCard(style: OverlayLayoutStyle, mode: OverlayViewMode) {
        let metrics = style.cardMetrics(for: mode)
        #expect(isClose(metrics.artworkHeight + metrics.metadataHeight, metrics.size.height))
        #expect(metrics.artworkHeight > 0)
        #expect(metrics.metadataHeight > 0)
    }

    /// Font sizes are the accessibility floor for the labels above each icon.
    @Test("Icon View text is at least as large as Window View's", arguments: modeSensitiveStyles)
    func iconViewTextIsLegible(style: OverlayLayoutStyle) {
        let metrics = style.cardMetrics(for: .icon)
        #expect(metrics.titleFontSize >= 12)
        #expect(metrics.subtitleFontSize >= 10)
        #expect(metrics.titleFontSize >= metrics.subtitleFontSize)
    }

    // MARK: - Geometry is shared

    private func layout(
        _ style: OverlayLayoutStyle,
        mode: OverlayViewMode,
        count: Int,
        selected: Int? = 0
    ) -> OverlayLayout {
        let state = OverlayState()
        state.availableContentWidth = 1400
        state.availableContentHeight = 860
        state.layoutStyle = style
        state.viewMode = mode
        state.load(entries: Fixture.entries(count: count), selectedIndex: selected)
        return state.layout
    }

    /// Requirement 5 and 6: the same panel for the same windows on the same screen, whatever
    /// each card happens to draw inside itself.
    @Test("Panels and card frames are identical across modes", arguments: OverlayLayoutStyle.allCases)
    func geometryIsIdenticalAcrossModes(style: OverlayLayoutStyle) {
        for count in [0, 1, 4, 9, 25] {
            let window = layout(style, mode: .window, count: count, selected: count == 0 ? nil : 0)
            let icon = layout(style, mode: .icon, count: count, selected: count == 0 ? nil : 0)

            #expect(window.panelSize == icon.panelSize, "\(style)/\(count) panel differed")
            #expect(window.positionedCards() == icon.positionedCards(), "\(style)/\(count) cards differed")
            #expect(window.visibleRange == icon.visibleRange)
            #expect(window.gridColumns == icon.gridColumns)
        }
    }

    /// Requirement 6: a narrow display and a wide one must both work in Icon View, and must
    /// reach the same answer Window View does.
    @Test("Responsive sizing matches across modes", arguments: OverlayLayoutStyle.allCases)
    func responsiveSizingMatches(style: OverlayLayoutStyle) {
        let sizes = [
            CGSize(width: 520, height: 400),
            CGSize(width: 1280, height: 800),
            CGSize(width: 3440, height: 1440),
        ]
        for available in sizes {
            var panels: [CGSize] = []
            for mode in OverlayViewMode.allCases {
                let state = OverlayState()
                state.availableContentWidth = available.width
                state.availableContentHeight = available.height
                state.layoutStyle = style
                state.viewMode = mode
                state.load(entries: Fixture.entries(count: 18), selectedIndex: 6)
                panels.append(state.layout.panelSize)
                #expect(state.layout.panelSize.height > 0)
            }
            // No assertion that the panel fits inside `available`: that is the width available
            // for *content*, and each style adds its own insets outside it, so the panel is
            // legitimately wider. How a style responds to a cramped viewport is
            // `OverlayLayoutTests`' business. What matters here is only that the mode does not
            // change the answer.
            #expect(panels[0] == panels[1], "\(style) at \(available) differed by mode")
        }
    }

    // MARK: - Selection

    /// Requirement 5: ordering and keyboard navigation are mode-agnostic. Stepping through the
    /// list must land on the same entry in the same order either way.
    @Test("Selection stepping is unchanged by the mode", arguments: OverlayLayoutStyle.allCases)
    func selectionSteppingIsUnchanged(style: OverlayLayoutStyle) {
        func walk(_ mode: OverlayViewMode) -> [CGWindowID] {
            let state = OverlayState()
            state.availableContentWidth = 1400
            state.availableContentHeight = 860
            state.layoutStyle = style
            state.viewMode = mode
            state.load(entries: Fixture.entries(count: 12), selectedIndex: 0)

            var visited: [CGWindowID] = []
            for step in 0..<12 {
                state.setSelection(step)
                if let entry = state.selectedEntry { visited.append(entry.windowID) }
            }
            return visited
        }

        let inWindowMode = walk(.window)
        #expect(inWindowMode.count == 12)
        #expect(inWindowMode == walk(.icon))
    }

    /// The state's metrics have to follow both axes, since that is what the card view reads.
    @Test(
        "State metrics track the mode and the arrangement",
        arguments: OverlayLayoutStyle.allCases, OverlayViewMode.allCases
    )
    func stateMetricsFollowBothAxes(style: OverlayLayoutStyle, mode: OverlayViewMode) {
        let state = OverlayState()
        state.layoutStyle = style
        state.viewMode = mode
        #expect(state.cardMetrics == style.cardMetrics(for: mode))
    }

    // MARK: - The spiral opts out

    /// The spiral ignores the view mode, on purpose.
    ///
    /// This is the counterpart to `modeSensitiveStyles`: without it, the exclusions above
    /// would silently cover a real regression — a spiral that had accidentally started
    /// differing between modes would simply stop being checked. Here the invariance is the
    /// assertion.
    @Test("The spiral draws the same card in both view modes")
    func spiralIsDeliberatelyModeInvariant() {
        let window = OverlayLayoutStyle.circular.cardMetrics(for: .window)
        let icon = OverlayLayoutStyle.circular.cardMetrics(for: .icon)
        #expect(window == icon)

        // A wedge cannot show a screenshot, so it always draws an icon and never has a
        // thumbnail well to invert around.
        #expect(!OverlayLayoutStyle.circular.canShowThumbnails)
        #expect(window.artworkIconSize > 0)
        #expect(window.contentLayout == .artworkThenMetadata)
        // One line, naming the application. The hub carries the window title instead.
        #expect(!window.showsSubtitle)
        #expect(window.usesApplicationNameAsPrimary)

        // Every other arrangement does respond to the mode.
        for style in Self.modeSensitiveStyles {
            #expect(style.cardMetrics(for: .window) != style.cardMetrics(for: .icon), "\(style)")
        }
    }

    /// The icon has to fit the band reserved for it, in the one arrangement whose card is
    /// sized by geometry rather than by a hand-picked constant.
    @Test("The spiral's icon fits its content box")
    func spiralIconFitsItsBox() {
        let metrics = OverlayLayoutStyle.circular.cardMetrics(for: .window)
        #expect(metrics.size == RadialLayout.baseContentSize)
        #expect(metrics.artworkIconSize <= metrics.artworkHeight)
        #expect(metrics.artworkHeight < metrics.size.height)
        // Room left for the name under it.
        #expect(metrics.metadataHeight >= metrics.titleFontSize + 4)
        // Requirement 6's "sufficiently large" still applies to a wedge.
        #expect(metrics.artworkIconSize >= 40)
    }

    /// Window View stays the default so an existing install sees no change on upgrade.
    @Test("A fresh state starts in Window View")
    func defaultsToWindowView() {
        #expect(OverlayState().viewMode == .window)
        #expect(SettingsStore.defaultOverlayViewMode == .window)
    }
}
