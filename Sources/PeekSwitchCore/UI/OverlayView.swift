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
                // Rebuilt per presentation, which is what makes the entrance reliable rather
                // than intermittent. A fresh subtree reads `isRevealed` as it stands — already
                // false — instead of depending on a published change having been applied before
                // the forced layout pass. See `OverlayState.presentationID`.
                //
                // Deliberately not keyed on the entry list: filtering a search must not replay
                // the entrance, only a new presentation may.
                arrangement
                    .id(state.presentationID)
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
        case .circular, .spiral: radial
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
            displayIcon: state.displayIcon(for: entry),
            thumbnail: state.thumbnails[entry.windowID],
            isSelected: isSelected,
            isHovered: card.index == hoveredIndex && !isSelected,
            badgeCount: state.badgeCount(for: entry),
            reduceMotion: state.reduceMotion,
            metrics: state.cardMetrics,
            display: state.display(for: entry),
            isIncognito: state.isIncognito(entry),
            tint: state.tint(for: entry)
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
            displayIcon: state.displayIcon(for: entry),
            isSelected: isSelected,
            isHovered: card.index == hoveredIndex && !isSelected,
            badgeCount: state.badgeCount(for: entry),
            display: state.display(for: entry),
            isIncognito: state.isIncognito(entry),
            tint: state.tint(for: entry)
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
                displayIcon: selectedDisplayIcon,
                thumbnail: selectedThumbnail,
                overlaysCaption: false,
                showsLiveBadge: state.viewMode.usesThumbnails,
                showsIconInsteadOfThumbnail: !state.viewMode.usesThumbnails
                    || state.selectedEntry?.isApplication == true,
                display: selectedDisplay,
                isIncognito: state.selectedEntry.map(state.isIncognito) ?? false
            )
            .frame(width: layout.listDetailFrame.width, height: layout.listDetailFrame.height)
            .position(x: layout.listDetailFrame.midX, y: layout.listDetailFrame.midY)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
    }

    // MARK: - Circular and spiral

    private var radial: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.radialSeats, id: \.index) { positioned in
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
            displayIcon: state.displayIcon(for: entry),
            seat: positioned.seat,
            centre: layout.radialCentre,
            panelSize: layout.panelSize,
            isSelected: isSelected,
            isHovered: positioned.index == hoveredIndex && !isSelected,
            badgeCount: state.badgeCount(for: entry),
            reduceMotion: state.reduceMotion,
            metrics: state.cardMetrics.scaled(by: layout.radialScale),
            display: state.display(for: entry),
            isIncognito: state.isIncognito(entry),
            tint: state.tint(for: entry),
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
            let frame = layout.radialHubFrame

            // Scaled with the arrangement, since the hub shrinks along with everything else.
            // Floored at 10pt, and the title gives up lines rather than shrinking past that:
            // four lines of illegible type says less than two lines of readable type.
            let scale = layout.radialScale
            let titleSize = max(10, 15 * scale)
            let titleLines = scale > 0.8 ? 4 : 3

            VStack(spacing: 4 * scale) {
                // The application name deliberately is not repeated here. The wedge under the
                // pointer is already tinted, outlined, labelled with that name and showing its
                // icon, and most titles end in it as well — it appeared four times in one glance.
                // The title is the one thing a wedge has no room for, so the hub spends everything
                // it has on that.
                Text(entry.displayTitle)
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(titleLines)
                    .multilineTextAlignment(.center)
                    // Cross-faded rather than replaced. Without this the title hard-cuts on every
                    // selection change, and unlike the entrance that happens continuously — once
                    // per wedge as the pointer crosses the ring.
                    .contentTransition(.opacity)
                    // A window with no title of its own falls back to its application name, so
                    // dropping the line above can never leave the middle blank.
                    .foregroundStyle(palette.text)

                if entry.isApplication || entry.isMinimized || state.isIncognito(entry) {
                    HStack(spacing: 4) {
                        if entry.isApplication {
                            ApplicationBadge()
                        }
                        if state.isIncognito(entry) {
                            IncognitoBadge(size: max(14, 15 * scale))
                        }
                        if entry.isMinimized {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
            // Scoped to the selected window's identity rather than to the index: a search that
            // filters the list can leave the same index pointing at a different window, and that is
            // a change of caption like any other.
            //
            // Placed here so it governs the contents only. The disc's own entrance is animated
            // below against `isRevealed`, and the two must not drive each other — a caption change
            // is not a reason to replay the entrance.
            .animation(captionChangeAnimation, value: entry.id)
            .padding(.horizontal, 18 * scale)
            .frame(width: frame.width, height: frame.height)
            // A disc rather than nothing: the caption sits over whatever desktop happens to
            // be behind the panel, and text alone there is unreadable half the time.
            //
            // Tinted with the selected window's own hue, and animated separately from the caption
            // above so a colour change cannot replay the disc's entrance.
            .background(
                Circle()
                    .fill(palette.selectedCardFill(tintedBy: state.tint(for: entry)))
                    .animation(captionChangeAnimation, value: entry.id)
            )
            .overlay(Circle().strokeBorder(palette.border, lineWidth: 1))
            .opacity(state.isRevealed ? 1 : 0)
            .animation(hubRevealAnimation, value: state.isRevealed)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    // MARK: - Selected window

    private var selectedDisplayIcon: NSImage? {
        guard let entry = state.selectedEntry else { return nil }
        return state.displayIcon(for: entry)
    }

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

    /// The hub swapping one window's caption for another.
    ///
    /// `easeInOut` rather than `easeOut`: this is a change of contents with no direction to it, so
    /// there is nothing for a decelerating curve to describe. Requirement 15.1 — under Reduce Motion
    /// the caption simply changes.
    private var captionChangeAnimation: Animation? {
        state.reduceMotion ? nil : .easeInOut(duration: OverlayReveal.captionChange)
    }

    /// The hub, as a fraction of the panel. The spiral's wedges scale about this.
    private var revealAnchor: UnitPoint {
        let panel = layout.panelSize
        guard panel.width > 0, panel.height > 0 else { return .center }
        let centre = layout.radialCentre
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
            if state.isSearching {
                searchMissView
            } else {
                Image(systemName: "macwindow.badge.plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(palette.secondaryText)
                Text("No switchable windows are open")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.text)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        // Clear of the search field when one is showing.
        .padding(.top, layout.searchChrome)
    }

    /// What an unresolved or final search miss says.
    ///
    /// Browser tabs and the application catalog arrive asynchronously. Until both have settled,
    /// this must read as progress rather than a dead end and must not advertise Return: the
    /// controller intentionally ignores Return during the same interval. Once local sources have
    /// all missed, the existing web fallback becomes the final offer.
    @ViewBuilder
    private var searchMissView: some View {
        if state.isResolvingSearch {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.secondaryText)

            Text("Looking for matches…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)

            Text("Checking browser tabs and installed applications")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)

            Text("Esc to clear")
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
        } else {
            let destination = WebSearch.destination(for: state.searchQuery)

            Image(systemName: destination == nil ? "magnifyingglass" : "arrow.up.forward.app")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.secondaryText)

            Text("No windows or applications match")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)

            if let destination {
                // Stacked rather than one line, and wrapping: the empty-state panel is 320pt wide
                // and a query plus its preamble does not fit beside the key chip.
                VStack(spacing: 4) {
                    Text("Return")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(palette.accentFill)
                        )
                        .foregroundStyle(palette.onAccentText)

                    Text(promptText(for: destination))
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.top, 2)
            }

            Text("Esc to clear")
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
        }
    }

    private func promptText(for destination: WebSearch.Destination) -> String {
        // Truncated here rather than by the layout: the panel is sized for a short message, and
        // a pasted paragraph would otherwise stretch it off the screen.
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = query.count > 28 ? query.prefix(28) + "…" : query[...]

        switch destination {
        case .address: return "to open \(shown)"
        case .search: return "to search the web for \(shown)"
        }
    }
}
