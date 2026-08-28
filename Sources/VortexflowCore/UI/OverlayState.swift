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
    /// Every window the presentation found, ranked. What search looks through.
    private var allEntries: [WindowEntry] = []

    /// What is drawn with no query: `allEntries` less whatever the history depth trimmed.
    ///
    /// Held separately rather than derived, because clearing a search has to return to *this* list.
    /// Reading `allEntries` back for an empty query — which is what the code did when the two were the
    /// same array — would quietly ignore the depth the moment a search was cleared.
    private var restingEntries: [WindowEntry] = []

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

    /// Whether the whole query is selected, so the next edit replaces it.
    ///
    /// The overlay has no text field, no caret and no selection range — the query is one string —
    /// so select-all cannot be a range here. It is this flag, and the next edit consumes it. That
    /// is enough for the two gestures people actually reach for: Command-A then delete wipes the
    /// query, and Command-A then typing replaces it, both matching every other text field on the
    /// system. Anything more would mean a caret model in here and a caret drawn in the pill, for
    /// a field that only ever grows at one end.
    @Published private(set) var isQuerySelected = false

    /// The visible results that are somewhere on this machine.
    ///
    /// Distinguished from `entries` because a query also offers the web, and the web is never a
    /// match — it is the fallback that is always available. Anything asking "did the query find
    /// anything?" has to ask about these, or the answer is trivially yes for every query ever typed.
    var localEntries: [WindowEntry] { entries.filter { !$0.isWebSearch } }

    /// True whenever a query is active but nothing on this machine matched it.
    /// This intentionally includes the brief period while secondary sources are resolving;
    /// callers deciding whether web search is safe must use `canOfferWebSearch` instead.
    var hasNoSearchMatches: Bool { isSearching && localEntries.isEmpty }

    /// Whether tabs or the installed-application catalog could still replace an apparent miss.
    var isResolvingSearch: Bool {
        hasNoSearchMatches && (!hasLoadedTabs || !hasLoadedApplications)
    }

    /// Web search is the final fallback, only after every local source has settled empty.
    var canOfferWebSearch: Bool { hasNoSearchMatches && !isResolvingSearch }
    @Published var selectedIndex: Int?

    /// Hub-ring hotspot angle, unwrapped so a spring travels the short arc.
    ///
    /// A raw seat `midAngle` jumps across the branch cut when the pointer crosses the top of
    /// the ring. Interpolating that jump would send the glow the long way around. Held here
    /// rather than in the view so Command Line Tools can build it — `@State` is a SwiftUI
    /// macro that this toolchain does not load — and so a test can snap and follow it.
    @Published var radialRingAngle: Double = RadialLayout.startAngle
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    /// Site icons that arrived after presentation, associated with native browser windows.
    /// `WindowEntry.applicationIcon` remains the immutable fallback and is always used for
    /// incognito windows and non-window search targets.
    @Published private(set) var browserIconsByWindowID: [CGWindowID: NSImage] = [:]
    /// The active site of each browser window, as a readable host.
    ///
    /// Only ever set for windows whose browser reported the documented `normal` mode, so a private
    /// window's destination is never held here — the same rule that decides whether a favicon may be
    /// fetched at all, for the same reason.
    @Published private(set) var siteHostsByWindowID: [CGWindowID: String] = [:]
    /// Private-window icons with their badge already composited, keyed by application.
    ///
    /// Not `@Published`: it is a cache derived from `incognitoWindowIDs` and the application's own
    /// icon, and publishing it would announce a change to every observer each time a new browser's
    /// badge is first drawn, in the middle of the render that asked for it.
    private var badgedPrivateIcons: [String: NSImage] = [:]
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

    /// Icons and hues for tab results, keyed by entry id because a tab has no `CGWindowID`.
    ///
    /// Tabs need this more than windows do, not less. A window list rarely holds more than a
    /// handful from one browser; a search across tabs routinely returns a dozen, and without the
    /// site's own icon they are a dozen identical browser icons stacked up.
    @Published private(set) var siteIconsByEntryID: [String: NSImage] = [:]
    private var siteTintsByEntryID: [String: IconTint] = [:]

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

    /// Which applications are on the speakers or the microphone.
    ///
    /// Sampled after the panel is up rather than with it, like `incognitoWindowIDs` — see
    /// `AudioActivityService` for the measurement that decided that.
    @Published var audioActivity: AudioActivity = .silent

    /// What each alerting tab is doing, keyed by entry id.
    ///
    /// Separate from `audioActivity` because it comes from somewhere else entirely and says something
    /// stronger. CoreAudio names a process; a browser's tab strip names the individual tab, which is
    /// the only place that distinction exists. See `TabMediaAlert`.
    @Published var tabMediaAlerts: [String: TabMediaAlert] = [:]

    /// What each browser *window* is doing, read from that window's own tab strip.
    @Published var windowMediaAlerts: [CGWindowID: TabMediaAlert] = [:]

    /// Browser processes whose tab strip produced an alert this presentation.
    ///
    /// The point of keeping this is that it licenses a negative. For these processes the strip has
    /// demonstrably been understood, so a window that is absent from it is genuinely quiet. For any
    /// other process there is nothing finer than CoreAudio and its per-process answer stands — which
    /// is what keeps a browser whose alert wording we cannot read from losing the badge altogether
    /// rather than merely keeping a coarse one. See `TabMediaAlert.Survey.narrowedProcesses`.
    @Published var narrowedBrowserProcesses: Set<pid_t> = []

    /// What a window's media state is read from: its own tab strip where that is possible, and
    /// CoreAudio otherwise.
    ///
    /// Reported as microphone and speaker glyphs on an incognito Chrome window with nothing running
    /// in it. CoreAudio's unit is the process, so one Grok tab in voice mode marked every Chrome
    /// window including that one — correct about the browser, wrong about the window, and the badge
    /// is drawn on windows.
    ///
    /// A tab strip belongs to one window, so it answers the question that was actually being asked.
    /// It is only trusted where it was read: an un-inspectable browser falls back to CoreAudio and
    /// is coarse again, which is the old behaviour rather than a missing badge.
    private func windowAlert(_ entry: WindowEntry) -> TabMediaAlert? {
        guard narrowedBrowserProcesses.contains(entry.processID) else { return nil }
        return windowMediaAlerts[entry.windowID]
    }

    /// Whether this entry is playing audio.
    ///
    /// Three sources, in descending order of precision, and each is the finest thing available for
    /// its kind of entry: a tab is named outright by its browser's tab strip, a browser window is
    /// narrowed to its own strip, and anything else has only CoreAudio's per-process reading.
    func isPlayingAudio(_ entry: WindowEntry) -> Bool {
        if entry.isTab { return tabMediaAlerts[entry.id] == .playingAudio }
        guard entry.isWindow else { return false }
        if narrowedBrowserProcesses.contains(entry.processID) {
            return windowAlert(entry) == .playingAudio
        }
        return audioActivity.isPlaying(entry.processID)
    }

    /// Whether this entry is capturing from the microphone or camera. Sourced as above.
    func isUsingMicrophone(_ entry: WindowEntry) -> Bool {
        if entry.isTab { return tabMediaAlerts[entry.id] == .recording }
        guard entry.isWindow else { return false }
        if narrowedBrowserProcesses.contains(entry.processID) {
            return windowAlert(entry) == .recording
        }
        return audioActivity.isRecording(entry.processID)
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
        // Typing over a selection replaces it, which is what every other text field does.
        guard !isQuerySelected else { return applySearch(characters) }
        return applySearch(searchQuery + characters)
    }

    /// Drop the last character of the query, or all of it when it is selected.
    @discardableResult
    func backspaceSearch() -> Bool {
        guard !searchQuery.isEmpty else { return false }
        guard !isQuerySelected else { return applySearch("") }
        return applySearch(String(searchQuery.dropLast()))
    }

    @discardableResult
    func clearSearch() -> Bool {
        // The scope goes with the query. Clearing the text while still restricted to one window's
        // tabs would leave the user looking at a filtered list with nothing on screen explaining why,
        // and no obvious way back to their windows.
        guard !searchQuery.isEmpty || tabScope != nil else { return false }
        tabScope = nil
        return applySearch("")
    }

    /// Select the whole query, so the next edit replaces it.
    ///
    /// - Returns: `true` when this changed anything, so the caller knows whether to redraw. Note
    ///   this is the *only* search mutation whose return value is not about the result list: there
    ///   is no filtering to redo, because selecting text does not change what matched.
    @discardableResult
    func selectAllSearch() -> Bool {
        guard isSearching, !isQuerySelected else { return false }
        isQuerySelected = true
        return true
    }

    /// Add the tabs found for this presentation, and fold them into any active query.
    ///
    /// - Returns: `true` when the visible list changed, so the panel can be re-fitted.
    @discardableResult
    func setTabs(_ tabs: [WindowEntry]) -> Bool {
        tabEntries = tabs
        hasLoadedTabs = true
        // A scope with no query typed is the case `isSearching` alone would miss: choosing "search
        // this window's tabs" fetches the tabs, and this is the arrival that has to fill the list.
        guard isSearching || tabScope != nil else { return false }
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

    /// When set, results are restricted to the tabs of one browser window.
    ///
    /// The browser's own window identifier, not a `CGWindowID` — it is matched against
    /// `BrowserTab.windowIdentifier`, which is the only id the tab list is numbered by.
    ///
    /// Published so the search pill can say what it is scoped to. A scope with no visible sign would
    /// look like the switcher had lost most of its results.
    @Published private(set) var tabScope: Int?

    /// How many fetched tabs belong to one browser window. `0` before the tabs have been fetched,
    /// which callers distinguish with `hasLoadedTabs`.
    func tabCount(forWindowIdentifier identifier: Int) -> Int {
        tabEntries.reduce(0) { $0 + ($1.tab?.windowIdentifier == identifier ? 1 : 0) }
    }

    /// Restrict results to one browser window's tabs, or clear the restriction with `nil`.
    @discardableResult
    func setTabScope(_ identifier: Int?) -> Bool {
        guard tabScope != identifier else { return false }
        tabScope = identifier
        return applySearch(searchQuery)
    }

    @discardableResult
    private func applySearch(_ query: String) -> Bool {
        searchQuery = query
        // Every edit consumes the selection, including the ones that arrive from elsewhere —
        // tabs landing, the application catalogue settling, a result being removed. A selection
        // that outlived the string it referred to would make the next keystroke wipe a query the
        // user had since retyped.
        isQuerySelected = false

        let matches: [WindowEntry]
        if let tabScope {
            // Scoped to one window's tabs: an empty query lists them all, which is what makes this
            // both "see all tabs" and "search them" without being two separate features. Windows,
            // installed applications and the web offers are all withheld — the user asked about the
            // inside of one window, and answering with anything else would be answering a different
            // question.
            let scoped = tabEntries.filter { $0.tab?.windowIdentifier == tabScope }
            matches = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? scoped
                : WindowSearch.filter(scoped, query: query)
            guard matches.map(\.id) != entries.map(\.id) else { return false }
            reload(entries: matches, selectedIndex: matches.isEmpty ? nil : 0)
            return true
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The resting list, not everything: the history depth governs what is shown unasked.
            matches = restingEntries
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

        let results = matches + webSearchResults(for: query, alongside: matches)
        guard results.map(\.id) != entries.map(\.id) else { return false }

        // The previous selection may have been filtered out, and after typing the best
        // match is what the user means — so selection returns to the top of the results.
        reload(entries: results, selectedIndex: results.isEmpty ? nil : 0)
        return true
    }

    /// The web results to offer after the local ones.
    ///
    /// One per destination the query could plausibly reach, so an address gets two: go there, or
    /// search for it. The conservative address test cannot tell "grok.com, take me there" from
    /// "grok.com, tell me about it", and since these are results the user picks from, it does not
    /// have to — the order carries the guess and both remain reachable.
    ///
    /// Last, never first. Switching is what the switcher is for, so a local window or application
    /// always holds the default selection and Return keeps meaning "go to the thing I found".
    ///
    /// Withheld while the local sources are still answering, but only when nothing has matched yet.
    /// Tabs and the installed-application catalogue arrive asynchronously, and offering the web
    /// before they land would put a web result under the default selection during the moment before
    /// the application that actually matched appears — so Return pressed quickly would open a browser
    /// instead of the app.
    private func webSearchResults(
        for query: String,
        alongside matches: [WindowEntry]
    ) -> [WindowEntry] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let localSourcesSettled = hasLoadedTabs && hasLoadedApplications
        guard !matches.isEmpty || localSourcesSettled else { return [] }

        return WebSearch.destinations(for: query).map { destination in
            .webSearchEntry(WebSearchTarget(query: query, destination: destination))
        }
    }

    /// - Parameters:
    ///   - entries: what is drawn before the user types, already trimmed to the history depth.
    ///   - searchable: every window the presentation found. Defaults to `entries` for the callers that
    ///     have no wider list, but when the depth trimmed anything this is the untrimmed one — a window
    ///     the depth removed from the resting view must still be findable by name, or the switcher is
    ///     claiming a running application does not exist.
    func load(entries: [WindowEntry], searchable: [WindowEntry]? = nil, selectedIndex: Int?) {
        allEntries = searchable ?? entries
        restingEntries = entries
        tabEntries = []
        hasLoadedTabs = false
        searchQuery = ""
        // A scope belongs to the presentation that asked for it. Carried across, the next trigger
        // would open showing one window's tabs and none of the user's windows.
        tabScope = nil
        isQuerySelected = false
        // A native window id can be reused, and its active tab can change between invocations.
        // Never carry a per-window favicon, or the tint taken from it, across presentations
        // without rematching it.
        browserIconsByWindowID.removeAll(keepingCapacity: true)
        siteHostsByWindowID.removeAll(keepingCapacity: true)
        siteTintsByWindowID.removeAll(keepingCapacity: true)
        siteIconsByEntryID.removeAll(keepingCapacity: true)
        siteTintsByEntryID.removeAll(keepingCapacity: true)
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
        syncRingAngle(snap: true)
    }

    func setSelection(_ index: Int?) {
        guard index != selectedIndex else { return }
        selectedIndex = SelectionMath.clamp(index, count: entries.count)
        // Both are minimal-movement: a selection that is already on screen leaves the
        // arrangement exactly where it is.
        visibleStart = layout.visibleStart(keepingSelectionVisible: visibleStart)
        scrollOffset = layout.scrollOffset(keepingSelectionVisible: scrollOffset)
        syncRingAngle(snap: false)
    }

    /// Keep the ring hotspot on the selected seat.
    ///
    /// - Parameter snap: `true` for a new list (load, search), where the previous angle is
    ///   not a motion the pointer made. `false` for a selection change, which unwraps so
    ///   the hotspot follows the short arc.
    private func syncRingAngle(snap: Bool) {
        guard layoutStyle.radialWinding != nil,
              let index = selectedIndex,
              let positioned = layout.radialSeats.first(where: { $0.index == index })
        else { return }
        let target = positioned.seat.midAngle
        if snap || reduceMotion {
            radialRingAngle = target
        } else {
            radialRingAngle = AngleMath.unwrap(target, relativeTo: radialRingAngle)
        }
    }

    func setThumbnail(_ image: CGImage, for windowID: CGWindowID) {
        thumbnails[windowID] = image
    }

    /// The one icon policy used by every layout.
    ///
    /// Private windows deliberately retain the browser icon: even a cookie-free favicon request
    /// would create network traffic for a private destination. They are badged here instead, which
    /// is what gives every arrangement the same marker without each one having to place it — and
    /// the corner it uses is free precisely because these windows have no site icon. Tabs and
    /// installed applications have no native window id and likewise keep their own supplied icon.
    func displayIcon(for entry: WindowEntry) -> NSImage? {
        // Tabs and assistant prompts both borrow the same store: an icon fetched from the network
        // after the entry already existed, falling back to whatever the entry was built with.
        if entry.isTab || entry.isWebSearch {
            return siteIconsByEntryID[entry.id] ?? entry.applicationIcon
        }
        guard entry.isWindow else { return entry.applicationIcon }
        guard !isIncognito(entry) else {
            guard let applicationIcon = entry.applicationIcon else { return nil }
            // Keyed by application rather than by window: the composite depends only on the
            // browser's icon, so every private window of one browser shares it, and nothing about
            // it goes stale within a session. Cached because this is called from a view body, and
            // returning a freshly built `NSImage` each time would defeat AppKit's own caching.
            let key = entry.bundleIdentifier ?? entry.applicationName
            if let cached = badgedPrivateIcons[key] { return cached }
            let badged = PrivateWindowIcon.badged(applicationIcon)
            badgedPrivateIcons[key] = badged
            return badged
        }
        return browserIconsByWindowID[entry.windowID] ?? entry.applicationIcon
    }

    /// The active site of an entry, or `nil` when there is none worth naming.
    ///
    /// Guarded against private windows here rather than only where the host is recorded, for the
    /// same reason `displayIcon` is: a `CGWindowID` can be reclassified part-way through a
    /// presentation, and reading through a single accessor means a host written a moment earlier
    /// cannot outlive that reclassification.
    func siteHost(for entry: WindowEntry) -> String? {
        if let tab = entry.tab {
            return tab.host.isEmpty ? nil : tab.host
        }
        guard entry.isWindow, !isIncognito(entry) else { return nil }
        return siteHostsByWindowID[entry.windowID]
    }

    /// Whether this tab already has a resolved icon, so the controller does not ask twice.
    func hasSiteIcon(for entry: WindowEntry) -> Bool {
        siteIconsByEntryID[entry.id] != nil
    }

    /// Publish a tab's composed icon, if it still belongs to the visible presentation.
    ///
    /// - Parameter image: already composed, since the caller holds both halves.
    @discardableResult
    func setTabIcon(
        _ image: NSImage,
        tint: IconTint?,
        for entryID: String,
        presentationID expectedPresentationID: Int
    ) -> Bool {
        guard isVisible,
              presentationID == expectedPresentationID,
              tabEntries.contains(where: { $0.id == entryID })
        else { return false }

        siteIconsByEntryID[entryID] = image
        if let tint, siteTintsByEntryID[entryID] != tint {
            siteTintsByEntryID[entryID] = tint
            recomputeTints()
        }
        return true
    }

    /// Publish an assistant's logo, if it still belongs to the visible presentation.
    ///
    /// Separate from `setTabIcon` only because of the guard: that one requires the entry to be one
    /// of `tabEntries`, and a web result is not — it is synthesised per query and lives only in
    /// `entries`. Same store underneath, since from `displayIcon`'s point of view both are "an icon
    /// that arrived from the network after the entry was built".
    @discardableResult
    func setWebResultIcon(
        _ image: NSImage,
        tint: IconTint?,
        for entryID: String,
        presentationID expectedPresentationID: Int
    ) -> Bool {
        guard isVisible,
              presentationID == expectedPresentationID,
              entries.contains(where: { $0.id == entryID && $0.isWebSearch })
        else { return false }
        siteIconsByEntryID[entryID] = image
        if let tint, siteTintsByEntryID[entryID] != tint {
            siteTintsByEntryID[entryID] = tint
            recomputeTints()
        }
        return true
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

        // A tab's own site, for the same reason: its browser's hue is shared with every other tab
        // in the list and so separates none of them.
        if entry.isTab, let site = siteTintsByEntryID[entry.id] {
            return ("site:\(entry.id)", site)
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

    /// Record the active site of a browser window, for the hub to name.
    ///
    /// Separate from `setBrowserIcon` and called earlier, because the two facts fail independently:
    /// the host is known as soon as the window is paired with its browser record, while the icon
    /// needs a network round trip that often does not finish and sometimes cannot succeed at all.
    /// Tying the name to the icon would mean a site the switcher knows about staying unnamed
    /// because its favicon happened to 404.
    func setSiteHost(
        _ host: String,
        for windowID: CGWindowID,
        presentationID expectedPresentationID: Int
    ) {
        guard presentationID == expectedPresentationID,
              !incognitoWindowIDs.contains(windowID),
              !host.isEmpty
        else { return }
        siteHostsByWindowID[windowID] = host
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
    /// Record a window's new geometry after the overlay itself moved it.
    ///
    /// Both lists, because clearing a search would otherwise bring back the pre-tiling frame from
    /// `allEntries`. The display mapping is re-derived for that one window rather than for all of
    /// them: tiling cannot move a window to another screen, but the same call is what would keep the
    /// mapping right if a future action did.
    func setFrame(_ frame: CGRect, forWindowID windowID: CGWindowID) {
        for index in entries.indices where entries[index].windowID == windowID {
            entries[index].frame = frame
        }
        for index in allEntries.indices where allEntries[index].windowID == windowID {
            allEntries[index].frame = frame
        }
        if let display = displayLayout.display(for: frame) {
            displaysByWindowID[windowID] = display
        }
    }

    /// - Returns: `false` when the window was not in the list to begin with.
    @discardableResult
    func remove(windowID: CGWindowID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.windowID == windowID }) else {
            return false
        }

        var remaining = entries
        remaining.remove(at: index)
        // Also drop it from both unfiltered lists, or clearing the search would bring the closed
        // window back — from whichever of the two the empty query happens to read.
        allEntries.removeAll { $0.windowID == windowID }
        restingEntries.removeAll { $0.windowID == windowID }

        let nextSelection: Int?
        if remaining.isEmpty {
            nextSelection = nil
        } else {
            nextSelection = min(selectedIndex ?? index, remaining.count - 1)
        }

        thumbnails.removeValue(forKey: windowID)
        browserIconsByWindowID.removeValue(forKey: windowID)
        siteHostsByWindowID.removeValue(forKey: windowID)
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
        siteHostsByWindowID.removeAll(keepingCapacity: false)
        siteTintsByWindowID.removeAll(keepingCapacity: false)
        siteIconsByEntryID.removeAll(keepingCapacity: false)
        siteTintsByEntryID.removeAll(keepingCapacity: false)
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

    /// Which of its application's windows this is, 1-based, and how many there are.
    ///
    /// Counted over `allEntries` rather than the filtered `entries`, so the phrase does not
    /// change while the user types: "2 of 3" turning into "1 of 1" mid-search would describe the
    /// search rather than the window.
    func windowPosition(for entry: WindowEntry) -> (index: Int, count: Int)? {
        guard entry.isWindow else { return nil }
        let siblings = allEntries.filter {
            $0.isWindow && $0.applicationName == entry.applicationName
        }
        guard siblings.count > 1,
              let offset = siblings.firstIndex(where: { $0.windowID == entry.windowID })
        else { return nil }
        return (index: offset + 1, count: siblings.count)
    }

    /// Everything the hub says about an entry.
    func hubSummary(for entry: WindowEntry) -> HubSummary {
        let position = windowPosition(for: entry)
        return HubSummary.make(
            entry: entry,
            siteHost: siteHost(for: entry),
            windowIndex: position?.index,
            windowCount: position?.count,
            now: Date().timeIntervalSinceReferenceDate
        )
    }
}
