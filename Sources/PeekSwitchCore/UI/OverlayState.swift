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
    @Published private(set) var hasLoadedTabs = false

    /// Installed applications, searched only as a fallback after windows and tabs miss.
    ///
    /// This catalog is session-wide rather than presentation-wide, so it remains populated
    /// when `load` replaces the current window list.
    private var applicationEntries: [WindowEntry] = []
    @Published private(set) var hasLoadedApplications = false

    /// What the user has typed. Empty means no filtering.
    @Published private(set) var searchQuery: String = ""

    var isSearching: Bool { !searchQuery.isEmpty }

    /// True whenever a query is active but no selectable result is currently visible.
    /// This intentionally includes the brief period while secondary sources are resolving;
    /// callers deciding whether web search is safe must use `canOfferWebSearch` instead.
    var hasNoSearchMatches: Bool { isSearching && entries.isEmpty }

    /// Whether tabs or the installed-application catalog could still replace an apparent miss.
    var isResolvingSearch: Bool {
        hasNoSearchMatches && (!hasLoadedTabs || !hasLoadedApplications)
    }

    /// Web search is the final fallback, only after every local source has settled empty.
    var canOfferWebSearch: Bool { hasNoSearchMatches && !isResolvingSearch }
    @Published var selectedIndex: Int?
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    /// Site icons that arrived after presentation, associated with native browser windows.
    /// `WindowEntry.applicationIcon` remains the immutable fallback and is always used for
    /// incognito windows and non-window search targets.
    @Published private(set) var browserIconsByWindowID: [CGWindowID: NSImage] = [:]
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

    /// Whether containers are tinted by their window's icon (Requirement 3.12).
    @Published var tintsWindowsByIcon: Bool = true

    /// Increase Contrast, sampled per presentation like `reduceMotion`.
    ///
    /// A user who has asked the system for more contrast has asked for the opposite of a
    /// decorative tint, so the tint is dropped entirely rather than merely reduced.
    @Published var increaseContrast: Bool = false

    /// Dominant hues already sampled this session, keyed by application identity.
    ///
    /// Not published: sampling is a pure function of an icon that never changes, so a cache hit
    /// must not invalidate any view. Bounded implicitly by the number of applications installed.
    private var applicationTints: [String: IconTint?] = [:]

    /// Hues taken from a browser window's active site icon, which say more than the browser's own
    /// icon: three Chrome windows share one application icon but rarely one site.
    private var siteTintsByWindowID: [CGWindowID: IconTint] = [:]

    /// The tint each entry actually draws with, after clustered hues have been spread apart.
    ///
    /// Resolved for the whole presentation rather than per card, because separation is a property
    /// of the set: a hue can only be moved once it is known what it collides with.
    private var resolvedTints: [String: IconTint] = [:]

    /// Windows that are private browsing windows.
    ///
    /// Arrives shortly after the overlay appears rather than with it — the browser has to be
    /// asked over Apple Events, which costs more than the whole budget for presenting. Held as a
    /// set of ids rather than a flag on `WindowEntry` because the entries come from the window
    /// server, which knows nothing about browsing modes.
    @Published var incognitoWindowIDs: Set<CGWindowID> = []

    /// Whether this entry is a private browsing window.
    func isIncognito(_ entry: WindowEntry) -> Bool {
        entry.isWindow && incognitoWindowIDs.contains(entry.windowID)
    }

    /// Whether the cards have been let in yet.
    ///
    /// Defaults to `true`, and that direction matters: any path that forgets to run the
    /// entrance shows the cards immediately, rather than presenting an empty panel. Only
    /// `SwitcherController` clears it, and only for a fresh presentation — a re-fit while the
    /// overlay is already open must not replay the entrance.
    @Published var isRevealed: Bool = true

    /// Counts presentations, and identifies the current one.
    ///
    /// Two jobs, both about the entrance.
    ///
    /// It is the view identity of the arrangement, which is what makes the entrance reliable.
    /// Animating a card in requires SwiftUI to have rendered the hidden state *before* the
    /// revealed one, and simply setting a published flag does not guarantee that: `@Published`
    /// notifies subscribers before the value changes, so whether a forced layout pass picks up
    /// the new value is a matter of internal scheduling. Changing the identity sidesteps the
    /// question — the subtree is rebuilt from scratch and reads whatever `isRevealed` says at
    /// that moment, which the controller has already set to `false`.
    ///
    /// It also stamps the deferred reveal, so a reveal scheduled by one presentation cannot fire
    /// during the next. That was a real defect: trigger twice in quick succession and the first
    /// presentation's pending reveal would land on the second, which had just set itself hidden,
    /// and the second's cards would snap in with no entrance at all.
    @Published private(set) var presentationID: Int = 0

    /// Start a fresh presentation: new identity, cards held back.
    func beginPresentation() {
        presentationID &+= 1
        isRevealed = false
    }

    /// Let the cards in, if `token` is still the current presentation.
    ///
    /// - Returns: `false` when the token is stale, so a caller can tell its work was dropped.
    @discardableResult
    func reveal(token: Int) -> Bool {
        guard token == presentationID, isVisible else { return false }
        isRevealed = true
        return true
    }

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
        return applySearch(searchQuery)
    }

    /// Supply the process-wide installed-application catalog.
    ///
    /// Applications are never listed without a query and never compete with a matching window
    /// or tab. Once this source and tabs have both settled, they become the local fallback.
    @discardableResult
    func setApplications(_ applications: [WindowEntry]) -> Bool {
        applicationEntries = applications
        hasLoadedApplications = true
        guard isSearching else { return false }
        return applySearch(searchQuery)
    }

    /// Forget an application whose bundle disappeared or failed to launch.
    func removeApplication(id: String) {
        applicationEntries.removeAll { $0.launchableApplication?.id == id }
        guard isSearching else { return }
        _ = applySearch(searchQuery)
    }

    @discardableResult
    private func applySearch(_ query: String) -> Bool {
        searchQuery = query

        let matches: [WindowEntry]
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            matches = allEntries
        } else {
            // Switching remains primary. Apps are offered only after both the real-window list
            // and the asynchronously fetched browser tabs have definitely missed.
            let primaryMatches = WindowSearch.filter(allEntries + tabEntries, query: query)
            if !primaryMatches.isEmpty {
                matches = primaryMatches
            } else if hasLoadedTabs, hasLoadedApplications {
                matches = WindowSearch.filter(applicationEntries, query: query)
            } else {
                matches = []
            }
        }

        guard matches.map(\.id) != entries.map(\.id) else { return false }

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
        // A native window id can be reused, and its active tab can change between invocations.
        // Never carry a per-window favicon, or the tint taken from it, across presentations
        // without rematching it.
        browserIconsByWindowID.removeAll(keepingCapacity: true)
        siteTintsByWindowID.removeAll(keepingCapacity: true)
        reload(entries: entries, selectedIndex: selectedIndex)
    }

    /// Real windows from the unfiltered presentation, used for browser matching after a search
    /// may have narrowed `entries` to only a subset.
    var allWindowEntries: [WindowEntry] {
        allEntries.filter(\.isWindow)
    }

    /// Rebuild the derived state for a given visible list.
    private func reload(entries: [WindowEntry], selectedIndex: Int?) {
        self.entries = entries
        self.selectedIndex = selectedIndex
        var counts: [String: Int] = [:]
        var displays: [CGWindowID: DisplayInfo] = [:]
        for entry in entries where entry.isWindow {
            counts[entry.applicationName, default: 0] += 1
            if let display = displayLayout.display(for: entry.frame) {
                displays[entry.windowID] = display
            }
        }
        windowCountsByApplication = counts
        displaysByWindowID = displays
        recomputeTints()
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

    /// The one icon policy used by every layout.
    ///
    /// Private windows deliberately retain the browser icon: even a cookie-free favicon request
    /// would create network traffic for a private destination. Tabs and installed applications
    /// have no native window id and likewise keep their own supplied icon.
    func displayIcon(for entry: WindowEntry) -> NSImage? {
        guard entry.isWindow, !isIncognito(entry) else { return entry.applicationIcon }
        return browserIconsByWindowID[entry.windowID] ?? entry.applicationIcon
    }

    /// The tint for an entry's container, or `nil` when it should keep the flat palette fill.
    func tint(for entry: WindowEntry) -> IconTint? {
        guard tintsWindowsByIcon, !increaseContrast else { return nil }
        if let resolved = resolvedTints[entry.id] { return resolved }
        // A tab or installed application surfaced by a search is not part of the window list the
        // separation was computed over, so it takes its icon's own hue.
        return tintSource(for: entry)?.tint
    }

    /// What an entry's tint is taken from, and the identity it shares that source with.
    ///
    /// Two windows of one application deliberately share an owner, so they are never pushed apart
    /// from each other: they are the same application, and for browsers the site icon already
    /// distinguishes them.
    ///
    /// A private window is excluded from the site source: its icon is never fetched, so tinting it
    /// by the browser's own icon would only make two Chrome windows look like one.
    private func tintSource(for entry: WindowEntry) -> (owner: String, tint: IconTint)? {
        if entry.isWindow, !isIncognito(entry), let site = siteTintsByWindowID[entry.windowID] {
            return ("site:\(entry.windowID)", site)
        }

        let key = entry.bundleIdentifier ?? entry.applicationName
        if let cached = applicationTints[key] {
            return cached.map { (key, $0) }
        }

        // Sampled once per application per session. An icon does not change while the app runs.
        let sampled = entry.applicationIcon.flatMap(IconTint.sampled(from:))
        applicationTints[key] = sampled
        return sampled.map { (key, $0) }
    }

    /// Re-resolve every entry's tint, spreading hues that would otherwise be indistinguishable.
    ///
    /// Computed over the unfiltered list rather than the visible one, so typing a search query
    /// narrows the list without recolouring what stays on screen.
    private func recomputeTints() {
        guard tintsWindowsByIcon, !increaseContrast else {
            resolvedTints = [:]
            return
        }

        var ownerByEntry: [String: String] = [:]
        var tintByOwner: [String: IconTint] = [:]
        for entry in allEntries {
            guard let source = tintSource(for: entry) else { continue }
            ownerByEntry[entry.id] = source.owner
            tintByOwner[source.owner] = source.tint
        }

        let separated = IconTint.separated(tintByOwner)
        resolvedTints = ownerByEntry.compactMapValues { separated[$0] }
    }

    /// Publish a browser-window icon only if it still belongs to the visible presentation and
    /// window.
    ///
    /// - Parameter isComposed: `true` when the caller supplies an icon that already carries both
    ///   identities, which is the case for one restored from an earlier verification. A freshly
    ///   downloaded favicon is composed here instead.
    /// - Parameter siteTint: the hue of the active site's icon, which tints the container.
    /// - Returns: the icon actually published, so a caller can remember exactly what was shown, or
    ///   `nil` when the update was rejected as stale.
    @discardableResult
    func setBrowserIcon(
        _ image: NSImage,
        for windowID: CGWindowID,
        presentationID expectedPresentationID: Int,
        isComposed: Bool = false,
        siteTint: IconTint? = nil
    ) -> NSImage? {
        guard isVisible,
              presentationID == expectedPresentationID,
              let entry = allEntries.first(where: {
                  $0.isWindow && $0.windowID == windowID
              }),
              !incognitoWindowIDs.contains(windowID)
        else { return nil }

        // A browser window has two useful identities: the application that owns it and the active
        // site. Keep both visible as one scalable composition, browser in front, instead of
        // replacing the browser icon with the favicon. When AppKit could not supply the browser
        // icon, the verified site icon alone still beats an empty placeholder.
        let published: NSImage
        if isComposed {
            published = image
        } else if let applicationIcon = entry.applicationIcon {
            published = BrowserWindowIcon.layered(
                siteIcon: image,
                browserIcon: applicationIcon
            )
        } else {
            published = image
        }

        browserIconsByWindowID[windowID] = published
        if let siteTint, siteTintsByWindowID[windowID] != siteTint {
            siteTintsByWindowID[windowID] = siteTint
            // A site hue replaces the browser's, which can change what it collides with.
            recomputeTints()
        }
        return published
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
        browserIconsByWindowID.removeValue(forKey: windowID)
        siteTintsByWindowID.removeValue(forKey: windowID)
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
        browserIconsByWindowID.removeAll(keepingCapacity: false)
        siteTintsByWindowID.removeAll(keepingCapacity: false)
        // `applicationTints` deliberately survives: an application icon does not change, and
        // re-sampling every icon on the next presentation would be pure waste.
    }

    /// Whether to offer a close affordance for this window.
    ///
    /// Without Accessibility there is no way to press a window's close button, and
    /// without an AX element there is no button to press — in both cases drawing the
    /// glyph would promise something that cannot happen.
    func canClose(_ entry: WindowEntry) -> Bool {
        entry.isWindow && canCloseWindows && entry.axElement != nil
    }

    /// Which display to label a window with, or `nil` when labelling would tell the
    /// user nothing — a single-display setup, a non-window target, or a window whose
    /// position matches no active display.
    func display(for entry: WindowEntry) -> DisplayInfo? {
        guard entry.isWindow, displayLayout.isMultiDisplay else { return nil }
        return displaysByWindowID[entry.windowID]
    }

    func badgeCount(for entry: WindowEntry) -> Int? {
        guard entry.isWindow,
              let count = windowCountsByApplication[entry.applicationName],
              count > 1 else {
            return nil
        }
        return count
    }
}
