import AppKit
import SwiftUI

/// The switcher overlay in whichever arrangement the user picked (Requirement 3.1).
///
/// ## Why absolute positioning
///
/// Every card is placed at a rectangle that `OverlayLayout` computed, and those are the
/// same rectangles it hit-tests clicks against.
///
/// That is not a stylistic preference. The panel is non-activating and never key, so
/// clicks and hover are resolved by hit-testing a point against layout arithmetic
/// rather than by AppKit's view tree. Anything drawn at coordinates the layout does
/// not know about is, in practice, unclickable — which is exactly the class of bug
/// that made the drawer feel stuck, and exactly why the close affordance is drawn from
/// `closeButtonFrame(for:)` rather than as a `Button` inside the card.
///
/// ## No captions
///
/// There is deliberately no header, no counter and no keyboard hint. They described the
/// overlay instead of showing it, and on an overlay this short-lived that is noise.
struct OverlayView: View {

    @ObservedObject var state: OverlayState
    /// Card the cursor is over, when it differs from the selection.
    var hoveredIndex: Int?

    /// Requirement 3.10: the theme follows the system appearance. Resolved once here
    /// and pushed into the environment so every card and caption agrees.
    @Environment(\.colorScheme) private var colorScheme

    private var palette: OverlayPalette { OverlayPalette.forScheme(colorScheme) }
    private var layout: OverlayLayout { state.layout }

    /// Cards, positioned. The strip is the only style with a non-zero scroll offset.
    private var cards: [OverlayLayout.PositionedCard] {
        layout.positionedCards(scrollOffset: state.scrollOffset)
    }

    var body: some View {
        ZStack {
            backdrop

            if state.entries.isEmpty {
                emptyState
            } else {
                arrangement
            }

            if state.isSearching {
                searchField
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .environment(\.overlayPalette, palette)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PeekSwitch window switcher")
    }

    @ViewBuilder
    private var arrangement: some View {
        switch state.layoutStyle {
        case .strip: strip
        case .grid: grid
        case .list: list
        case .spiral: spiral
        }
    }

    /// Whether anything is drawn behind the cards.
    ///
    /// The empty state always gets a plate whatever the style: "no switchable windows
    /// are open" is a sentence, and a sentence with nothing behind it is unreadable
    /// over an arbitrary desktop.
    private var showsBackdrop: Bool {
        state.entries.isEmpty || state.layoutStyle.drawsBackdrop
    }

    // MARK: - Search

    /// What has been typed so far.
    ///
    /// This is the one caption that earns its place: it exists only while a query is
    /// active, and without it there is no way to tell a filtered list from a short one, or
    /// to see that a stray keystroke was captured.
    private var searchField: some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                Text(state.searchQuery)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                // A caret, so an empty-looking field still reads as one being typed into.
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 1.5, height: 13)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(palette.chipFill))
            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
            .shadow(color: .black.opacity(showsBackdrop ? 0 : 0.25), radius: 4, y: 2)
            .frame(height: OverlayLayout.searchFieldHeight)

            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backdrop: some View {
        if showsBackdrop {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                )
        }
    }

    /// Lift the cards off whatever is behind them.
    ///
    /// With no plate, a card can land on a same-coloured window and lose its edge, so
    /// each one casts its own shadow instead of borrowing the panel's.
    private var cardShadowRadius: CGFloat { showsBackdrop ? 0 : 9 }
    private var cardShadowOpacity: Double { showsBackdrop ? 0 : 0.34 }

    // MARK: - Cards

    private func card(_ card: OverlayLayout.PositionedCard) -> some View {
        let entry = state.entries[card.index]
        let isSelected = card.index == state.selectedIndex

        return WindowCardView(
            entry: entry,
            thumbnail: state.thumbnails[entry.windowID],
            isSelected: isSelected,
            isHovered: card.index == hoveredIndex && !isSelected,
            badgeCount: state.badgeCount(for: entry),
            reduceMotion: state.reduceMotion,
            metrics: state.cardMetrics,
            display: state.display(for: entry)
        )
        .scaleEffect(isSelected ? state.selectedScale : 1.0)
        .shadow(
            color: .black.opacity(cardShadowOpacity),
            radius: cardShadowRadius,
            y: cardShadowRadius / 2
        )
        // Keep the enlarged card above its neighbours instead of clipped by them.
        .zIndex(isSelected ? 1 : 0)
        .animation(selectionAnimation, value: isSelected)
        .opacity(state.isRevealed ? 1 : 0)
        .scaleEffect(state.isRevealed ? 1 : OverlayReveal.initialScale)
        .animation(revealAnimation(forCardIndex: card.index), value: state.isRevealed)
        .position(x: card.frame.midX, y: card.frame.midY)
    }

    private func row(_ card: OverlayLayout.PositionedCard) -> some View {
        let entry = state.entries[card.index]
        let isSelected = card.index == state.selectedIndex

        return WindowRowView(
            entry: entry,
            isSelected: isSelected,
            isHovered: card.index == hoveredIndex && !isSelected,
            badgeCount: state.badgeCount(for: entry),
            display: state.display(for: entry)
        )
        .frame(width: card.frame.width, height: card.frame.height)
        .opacity(state.isRevealed ? 1 : 0)
        // Rows arrive by sliding down the column rather than scaling; a list row growing
        // from its centre reads as a glitch in a stack of identical rows.
        .offset(y: state.isRevealed ? 0 : -6)
        .animation(revealAnimation(forCardIndex: card.index), value: state.isRevealed)
        .position(x: card.frame.midX, y: card.frame.midY)
    }

    /// The close affordance, on the selected card only.
    ///
    /// Drawn from the layout's rectangle rather than as an overlay inside the card, so
    /// that what is on screen and what the click handler tests are the same geometry.
    /// Restricting it to the selected card is what keeps those two in step: hover drives
    /// selection, so the selected card is the one under the cursor.
    @ViewBuilder
    private func closeButton(for positioned: OverlayLayout.PositionedCard) -> some View {
        let entry = state.entries[positioned.index]

        if positioned.index == state.selectedIndex, state.canClose(entry) {
            let frame = layout.closeButtonFrame(for: positioned, selectedScale: state.selectedScale)

            CloseButtonView(isActive: state.isCloseButtonHovered)
                .zIndex(2)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private var positionedCards: some View {
        ForEach(cards, id: \.index) { positioned in
            card(positioned)
            closeButton(for: positioned)
        }
    }

    // MARK: - Strip

    private var strip: some View {
        ZStack(alignment: .topLeading) {
            positionedCards
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        // Cards scrolled past the ends must not spill outside the panel.
        .clipped()
        .animation(scrollAnimation, value: state.scrollOffset)
    }

    // MARK: - Grid

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            positionedCards
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }

    // MARK: - List

    private var list: some View {
        ZStack(alignment: .topLeading) {
            // Sidebar plate, so the row column reads as separate from the preview. Starts
            // below the search field when one is showing.
            let sidebarHeight = layout.panelSize.height - layout.searchChrome

            Rectangle()
                .fill(palette.strongBorder.opacity(0.18))
                .frame(width: OverlayLayout.List.sidebarWidth, height: sidebarHeight)
                .offset(y: layout.searchChrome)

            Rectangle()
                .fill(palette.border)
                .frame(width: 1, height: sidebarHeight)
                .offset(x: OverlayLayout.List.sidebarWidth, y: layout.searchChrome)

            ForEach(cards, id: \.index) { positioned in
                row(positioned)
                closeButton(for: positioned)
            }

            WindowPreviewView(
                entry: state.selectedEntry,
                thumbnail: selectedThumbnail,
                overlaysCaption: false,
                showsLiveBadge: state.viewMode.usesThumbnails,
                showsIconInsteadOfThumbnail: !state.viewMode.usesThumbnails,
                display: selectedDisplay
            )
            .frame(width: layout.listDetailFrame.width, height: layout.listDetailFrame.height)
            .position(x: layout.listDetailFrame.midX, y: layout.listDetailFrame.midY)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }

    // MARK: - Spiral

    private var spiral: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.spiralSeats, id: \.index) { positioned in
                wedge(positioned)
            }

            hubCaption

            // Drawn last so it sits above the wedge it belongs to.
            ForEach(cards, id: \.index) { positioned in
                closeButton(for: positioned)
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }

    private func wedge(_ positioned: OverlayLayout.PositionedSeat) -> some View {
        let entry = state.entries[positioned.index]
        let isSelected = positioned.index == state.selectedIndex

        return WindowWedgeView(
            entry: entry,
            seat: positioned.seat,
            centre: layout.spiralCentre,
            panelSize: layout.panelSize,
            isSelected: isSelected,
            isHovered: positioned.index == hoveredIndex && !isSelected,
            badgeCount: state.badgeCount(for: entry),
            reduceMotion: state.reduceMotion,
            metrics: state.cardMetrics,
            display: state.display(for: entry),
            shadowRadius: cardShadowRadius,
            shadowOpacity: cardShadowOpacity
        )
        // Wedges are painted in seat order, so without this the selected one's glow would
        // be overpainted by whichever wedge happens to come after it.
        .zIndex(isSelected ? 1 : 0)
        .animation(selectionAnimation, value: isSelected)
        .opacity(state.isRevealed ? 1 : 0)
        // Anchored on the hub, so the ring blooms outward from the pointer instead of each
        // wedge inflating where it stands.
        .scaleEffect(state.isRevealed ? 1 : OverlayReveal.initialScale, anchor: revealAnchor)
        .animation(
            revealAnimation(forVisibleOffset: positioned.seat.offset),
            value: state.isRevealed
        )
    }

    /// What the hollow middle says.
    ///
    /// The middle is not a preview — the arrangement exists because a large picture of the
    /// window you have already found is the least useful thing on screen. It is a caption,
    /// and it is load-bearing rather than decorative: a wedge has room for an application
    /// name and no more, so three Chrome windows are three identical icons until something
    /// spells out which one is under the pointer. That is what this does.
    ///
    /// With nothing selected it disappears entirely and the middle really is a hole.
    @ViewBuilder
    private var hubCaption: some View {
        if let entry = state.selectedEntry {
            let frame = layout.spiralHubFrame

            VStack(spacing: 4) {
                Text(entry.applicationName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(palette.secondaryText)

                Text(entry.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.text)

                if selectedDisplay != nil || entry.isMinimized {
                    HStack(spacing: 4) {
                        if let selectedDisplay {
                            DisplayBadge(display: selectedDisplay)
                        }
                        if entry.isMinimized {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(width: frame.width, height: frame.height)
            // A disc rather than nothing: the caption sits over whatever desktop happens to
            // be behind the panel, and text alone there is unreadable half the time.
            .background(Circle().fill(palette.chipFill))
            .overlay(Circle().strokeBorder(palette.border, lineWidth: 1))
            .opacity(state.isRevealed ? 1 : 0)
            .animation(hubRevealAnimation, value: state.isRevealed)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    // MARK: - Selected window

    private var selectedThumbnail: CGImage? {
        guard let entry = state.selectedEntry else { return nil }
        return state.thumbnails[entry.windowID]
    }

    private var selectedDisplay: DisplayInfo? {
        guard let entry = state.selectedEntry else { return nil }
        return state.display(for: entry)
    }

    /// Requirement 15.1 / 15.2: no scale animation under Reduce Motion.
    private var selectionAnimation: Animation? {
        state.reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78)
    }

    /// Requirement 15.3: jump the scroll position instead of animating it.
    private var scrollAnimation: Animation? {
        state.reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    // MARK: - Entrance

    /// The cards' entrance, staggered so they arrive one after another.
    ///
    /// Ordered by position in the visible run rather than by entry index, so the run always
    /// starts at the first card on screen — otherwise a grid paged to entries 12–20 would sit
    /// through twelve cards' worth of delay before drawing anything.
    private func revealAnimation(forCardIndex index: Int) -> Animation? {
        revealAnimation(forVisibleOffset: max(0, index - layout.visibleRange.lowerBound))
    }

    private func revealAnimation(forVisibleOffset offset: Int) -> Animation? {
        // Requirement 15.1: no entrance under Reduce Motion. The cards are simply there.
        guard !state.reduceMotion else { return nil }
        return .easeOut(duration: OverlayReveal.duration).delay(
            OverlayReveal.delay(
                forOffset: offset,
                count: max(1, cards.count),
                reduceMotion: false
            )
        )
    }

    private var hubRevealAnimation: Animation? {
        guard !state.reduceMotion else { return nil }
        return .easeOut(duration: OverlayReveal.duration).delay(OverlayReveal.hubDelay)
    }

    /// The hub, as a fraction of the panel. The spiral's wedges scale about this.
    private var revealAnchor: UnitPoint {
        let panel = layout.panelSize
        guard panel.width > 0, panel.height > 0 else { return .center }
        let centre = layout.spiralCentre
        return UnitPoint(x: centre.x / panel.width, y: centre.y / panel.height)
    }

    // MARK: - Empty state

    /// Requirement 1.8, and the no-matches case.
    ///
    /// The two are distinguished on purpose: "nothing is open" and "nothing matches what
    /// you typed" call for different reactions, and showing the first when the second is
    /// true reads as a bug.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: state.isSearching ? "magnifyingglass" : "macwindow.badge.plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.secondaryText)
            Text(state.isSearching ? "No windows match" : "No switchable windows are open")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)
            if state.isSearching {
                Text("Esc to clear")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        // Clear of the search field when one is showing.
        .padding(.top, layout.searchChrome)
    }
}
