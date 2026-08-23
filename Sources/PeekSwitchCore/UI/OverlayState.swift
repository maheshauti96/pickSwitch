import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// How the current presentation was started, which decides how it ends.
enum PresentationMode {
    /// Opened by holding the trigger button; releasing it commits
    /// (Requirement 5.9, 5.10).
    case hold
    /// Opened by the global hotkey; stays up until a click, Return or Escape
    /// (Requirement 6.2).
    case toggle
}

/// Observable state behind the strip. Owns nothing but display state — every
/// decision lives in `SwitcherController`.
@MainActor
final class OverlayState: ObservableObject {

    /// The windows currently on screen, after any search filter.
    @Published var entries: [WindowEntry] = []

    /// Everything enumerated this presentation, before filtering. Kept so clearing the
    /// query restores the full list without re-enumerating.
    private var allEntries: [WindowEntry] = []

    /// Browser tabs, searched but never listed by default.
    ///
    /// Held separately because they are not part of the window list: a browser with forty
    /// tabs would otherwise bury every actual window, and listing them costs an Apple Event
    /// round trip that the trigger path cannot afford. They join the results only once a
    /// query narrows things down.
    private var tabEntries: [WindowEntry] = []

    /// True once tabs have been fetched for this presentation.
    private(set) var hasLoadedTabs = false

    /// What the user has typed. Empty means no filtering.
    @Published private(set) var searchQuery: String = ""

    var isSearching: Bool { !searchQuery.isEmpty }

    /// True when a query is active but matches nothing, so the overlay can say so rather
    /// than showing an empty box that looks like a failure to enumerate.
    var hasNoSearchMatches: Bool { isSearching && entries.isEmpty }
    @Published var selectedIndex: Int?
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    /// The strip's pixel scroll offset.
    @Published var scrollOffset: CGFloat = 0
    /// First card on screen for the styles that page by whole items.
    ///
    /// Persisted across selection changes so the arrangement only moves when it has to.
    /// See `OverlayLayout.visibleStart` for why deriving it from the selection instead
    /// made the overlay shake under the pointer.
    @Published var visibleStart: Int = 0
    @Published var availableContentWidth: CGFloat = 900
    @Published var availableContentHeight: CGFloat = 700
    @Published var reduceMotion: Bool = false
    @Published var isVisible: Bool = false

    /// Which arrangement the overlay is drawing. Read from settings once per
    /// presentation so changing it in Settings takes effect on the next trigger.
    @Published var layoutStyle: OverlayLayoutStyle = .strip

    /// Whether items are drawn as window previews or as large application icons.
    @Published var viewMode: OverlayViewMode = .window

    /// Whether the cards have been let in yet.
    ///
    /// Defaults to `true`, and that direction matters: any path that forgets to run the
    /// entrance shows the cards immediately, rather than presenting an empty panel. Only
    /// `SwitcherController` clears it, and only for a fresh presentation — a re-fit while the
    /// overlay is already open must not replay the entrance.
    @Published var isRevealed: Bool = true

    /// Metrics for one card, given the current arrangement and view mode.
    var cardMetrics: OverlayCardMetrics { layoutStyle.cardMetrics(for: viewMode) }

    /// Whether closing windows is possible at all, i.e. Accessibility is granted.
    @Published var canCloseWindows: Bool = false

    /// True while the cursor is on the selected card's close affordance, so it can
    /// respond to the pointer.
    ///
    /// Published, unlike the hover index, because it changes only when the cursor
    /// crosses the button's edge — a handful of times per presentation rather than at
    /// the 60 Hz the hover sampler runs at.
    @Published var isCloseButtonHovered: Bool = false

    /// True once the strip is staying open on its own rather than tracking a held
    /// button. Drives a hint line, because "it vanished the moment I let go" was the
    /// first thing a real user hit — the mode is invisible otherwise.
    @Published var isPersistent: Bool = false

    /// Per-application window counts, for the multi-window badge
    /// (Requirement 3.6). Recomputed once per presentation rather than per card
    /// render.
    @Published var windowCountsByApplication: [String: Int] = [:]

    /// The display arrangement at the moment the overlay was presented.
    @Published var displayLayout: DisplayLayout = .empty

    /// Which display each window is on, resolved once per presentation.
    ///
    /// Precomputed rather than looked up per card: the geometry is cheap but the strip
    /// re-renders on every hover sample, and doing it there would repeat the same
    /// rectangle intersections sixty times a second for no gain.
    @Published private(set) var displaysByWindowID: [CGWindowID: DisplayInfo] = [:]

    var layout: OverlayLayout {
        OverlayLayout(
            style: layoutStyle,
            cardCount: entries.count,
            selectedIndex: selectedIndex,
            availableContentWidth: availableContentWidth,
            availableContentHeight: availableContentHeight,
            visibleStart: visibleStart,
            isSearching: isSearching
        )
    }

    var selectedEntry: WindowEntry? {
        guard let selectedIndex, entries.indices.contains(selectedIndex) else { return nil }
        return entries[selectedIndex]
    }

    /// Effective scale for the selected card. Requirement 15.2 flattens this to 1.0
    /// under Reduce Motion, leaning on border and brightness to show selection
    /// instead.
    var selectedScale: CGFloat {
        reduceMotion ? 1.0 : layoutStyle.selectedScale
    }

    /// Extend the query, and re-filter.
    ///
    /// - Returns: `true` if the visible list changed, so the caller knows whether the
    ///   panel needs re-fitting.
    @discardableResult
    func appendToSearch(_ characters: String) -> Bool {
        applySearch(searchQuery + characters)
    }

    /// Drop the last character of the query.
    @discardableResult
    func backspaceSearch() -> Bool {
        guard !searchQuery.isEmpty else { return false }
        return applySearch(String(searchQuery.dropLast()))
    }

    @discardableResult
    func clearSearch() -> Bool {
        guard !searchQuery.isEmpty else { return false }
        return applySearch("")
    }

    /// Add the tabs found for this presentation, and fold them into any active query.
    ///
    /// - Returns: `true` when the visible list changed, so the panel can be re-fitted.
    @discardableResult
    func setTabs(_ tabs: [WindowEntry]) -> Bool {
        tabEntries = tabs
        hasLoadedTabs = true
        guard isSearching else { return false }
        return applySearch(searchQuery, force: true)
    }

    @discardableResult
    private func applySearch(_ query: String, force: Bool = false) -> Bool {
        searchQuery = query

        // Windows first, then tabs, so a real window always outranks a tab that scored the
        // same — switching to a window is the primary job, and a tab is the deeper cut.
        let searchable = query.isEmpty ? allEntries : allEntries + tabEntries
        let matches = WindowSearch.filter(searchable, query: query)

        guard force || matches.map(\.id) != entries.map(\.id) else { return false }

        // The previous selection may have been filtered out, and after typing the best
        // match is what the user means — so selection returns to the top of the results.
        reload(entries: matches, selectedIndex: matches.isEmpty ? nil : 0)
        return true
    }

    func load(entries: [WindowEntry], selectedIndex: Int?) {
        allEntries = entries
        tabEntries = []
        hasLoadedTabs = false
        searchQuery = ""
        reload(entries: entries, selectedIndex: selectedIndex)
    }

    /// Rebuild the derived state for a given visible list.
    private func reload(entries: [WindowEntry], selectedIndex: Int?) {
        self.entries = entries
        self.selectedIndex = selectedIndex
        var counts: [String: Int] = [:]
        var displays: [CGWindowID: DisplayInfo] = [:]
        for entry in entries {
            counts[entry.applicationName, default: 0] += 1
            if let display = displayLayout.display(for: entry.frame) {
                displays[entry.windowID] = display
            }
        }
        windowCountsByApplication = counts
        displaysByWindowID = displays
        // A fresh presentation starts at the top rather than wherever the last one left
        // off, then pages forward if the initial selection is somehow past the first page.
        visibleStart = 0
        visibleStart = layout.visibleStart(keepingSelectionVisible: 0)
        scrollOffset = layout.scrollOffset(keepingSelectionVisible: 0)
    }

    func setSelection(_ index: Int?) {
        guard index != selectedIndex else { return }
        selectedIndex = SelectionMath.clamp(index, count: entries.count)
        // Both are minimal-movement: a selection that is already on screen leaves the
        // arrangement exactly where it is.
        visibleStart = layout.visibleStart(keepingSelectionVisible: visibleStart)
        scrollOffset = layout.scrollOffset(keepingSelectionVisible: scrollOffset)
    }

    func setThumbnail(_ image: CGImage, for windowID: CGWindowID) {
        thumbnails[windowID] = image
    }

    /// Drop a window that has just been closed, keeping the overlay usable.
    ///
    /// The selection stays where it was in the list rather than following the removed
    /// window's neighbour, so closing several windows in a row means clicking the same
    /// spot repeatedly — the next card slides under the cursor. When the last card goes,
    /// the selection becomes nil and the empty state takes over.
    ///
    /// - Returns: `false` when the window was not in the list to begin with.
    @discardableResult
    func remove(windowID: CGWindowID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.windowID == windowID }) else {
            return false
        }

        var remaining = entries
        remaining.remove(at: index)
        // Also drop it from the unfiltered list, or clearing the search would bring the
        // closed window back.
        allEntries.removeAll { $0.windowID == windowID }

        let nextSelection: Int?
        if remaining.isEmpty {
            nextSelection = nil
        } else {
            nextSelection = min(selectedIndex ?? index, remaining.count - 1)
        }

        thumbnails.removeValue(forKey: windowID)
        // Reload so the per-application counts, display badges and scroll offset all
        // reflect the shorter list rather than going stale. Deliberately not `load`,
        // which would also clear an active search.
        reload(entries: remaining, selectedIndex: nextSelection)
        return true
    }

    /// Release the captured images after a presentation (Requirement 8.6).
    ///
    /// Deliberately keeps `entries`. Clearing them re-rendered the strip as the "no
    /// switchable windows are open" empty state, and because SwiftUI applies that
    /// re-render on a later pass, the *next* presentation ordered the panel on screen
    /// while it was still showing that empty message — a visible flash of "nothing is
    /// open" every time the user reopened the switcher right after switching.
    ///
    /// The entries are replaced wholesale by `load(entries:selectedIndex:)` before the
    /// panel is shown again, so keeping them costs a dozen small structs and buys a
    /// correct first frame. Thumbnails are the memory that actually matters, and those
    /// still go.
    func releaseThumbnails() {
        thumbnails.removeAll(keepingCapacity: false)
    }

    /// Whether to offer a close affordance for this window.
    ///
    /// Without Accessibility there is no way to press a window's close button, and
    /// without an AX element there is no button to press — in both cases drawing the
    /// glyph would promise something that cannot happen.
    func canClose(_ entry: WindowEntry) -> Bool {
        canCloseWindows && entry.axElement != nil
    }

    /// Which display to label a window with, or `nil` when labelling would tell the
    /// user nothing — a single-display setup, or a window whose position matches no
    /// active display.
    func display(for entry: WindowEntry) -> DisplayInfo? {
        guard displayLayout.isMultiDisplay else { return nil }
        return displaysByWindowID[entry.windowID]
    }

    func badgeCount(for entry: WindowEntry) -> Int? {
        guard let count = windowCountsByApplication[entry.applicationName], count > 1 else {
            return nil
        }
        return count
    }
}
