import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Coordinates a single switch: trigger in, window activated out.
///
/// Everything stateful about a presentation lives here so the services stay
/// independently testable and the requirement traceability stays legible.
///
/// ## The latency path
///
/// Requirement 14.1 gives 150 ms from button press to a visible overlay. The budget
/// is spent like this:
///
/// 1. Event tap callback: reads one integer, hops to main. Microseconds.
/// 2. Window enumeration on a utility queue: the real cost, budgeted at 50 ms by
///    Requirement 1.2 and bounded by `AXBridge.messagingTimeout`.
/// 3. Back on main: order by MRU, load state, position and show the pre-built panel.
///
/// Thumbnails are explicitly *not* on this path. The panel goes up showing app icons
/// and captures land underneath as they complete (Requirement 9.2, 9.3). The panel
/// and its hosting view are built once at launch, because constructing them is tens
/// of milliseconds that the budget cannot absorb.
///
/// ## Why hover is polled
///
/// The panel is non-activating and never key, which makes AppKit's mouse-tracking
/// delivery unreliable for it — particularly while another button is physically held
/// down, as it always is in hold mode. Rather than fight that, the controller samples
/// `NSEvent.mouseLocation` at 60 Hz while the overlay is up and hit-tests with the
/// same `StripLayout` used to draw. The timer exists only during a presentation, so
/// Requirement 14.3's idle CPU budget is untouched.
@MainActor
public final class SwitcherController {

    // MARK: - Collaborators

    private let settings: SettingsStore
    private let permissions: PermissionsManager
    private let registry: WindowRegistry
    private let mruTracker: MRUTracker
    private let thumbnails: ThumbnailService
    private let activation: ActivationService
    private let browserTabs = BrowserTabService()
    private let browserFavicons = BrowserFaviconService()
    private let applicationCatalog = ApplicationCatalog()

    /// Private browsing windows identified during this session.
    ///
    /// Usually stable for a window's lifetime. An explicitly normal browser result may remove an
    /// id because the window server can recycle `CGWindowID`s after a window closes.
    private var knownIncognitoWindowIDs: Set<CGWindowID> = []

    /// Windows whose mode has been settled either way, so a browser is not re-interrogated every
    /// time the overlay closes just because none of its windows turned out to be private.
    private var incognitoResolvedWindowIDs: Set<CGWindowID> = []

    /// A verified browser-window icon, remembered with the window title it was verified against.
    ///
    /// Asking a browser for its windows costs an Apple Event, and a busy browser can take seconds
    /// to answer — far longer than a switch. Without this, a favicon only ever appeared when the
    /// user happened to hold the overlay open long enough for that round trip plus a network
    /// request, so the composed icon looked intermittent.
    ///
    /// The title is the revalidation key, and it is exact rather than heuristic: a Chromium window
    /// takes its title from its active tab, so an identical title means the same tab is still in
    /// front and the previously verified site icon still describes it. A changed title means the
    /// tab moved on, and the entry is ignored until fresh metadata arrives. Nothing here is
    /// persisted, and private windows are never entered.
    private struct CachedBrowserIcon {
        let title: String
        let icon: NSImage
        /// Hue of the site icon, remembered with it so a restored icon also restores the tint the
        /// container had when it was verified.
        let tint: IconTint?
    }

    private var browserIconsByWindowID: [CGWindowID: CachedBrowserIcon] = [:]
    private var browserIconOrder: [CGWindowID] = []
    private static let maximumRememberedBrowserIcons = 64

    /// How many tab results may have their site icon resolved for one visible list.
    ///
    /// Generous enough to cover a screenful in any arrangement, low enough that a query matching
    /// most of a forty-tab browser does not fan out a request per tab for a list that is about to
    /// change with the next keystroke.
    private static let maximumVisibleTabIconRequests = 16
    private let triggerMonitor: TriggerMonitor
    private let hotKeyMonitor: HotKeyMonitor

    private let state = OverlayState()
    private var panel: OverlayPanel?

    /// Window enumeration happens here, never on main.
    private let workQueue = DispatchQueue(
        label: "dev.peekswitch.enumeration",
        qos: .userInteractive
    )

    /// Installed-app discovery walks the file system and must never queue ahead of a trigger.
    private let applicationCatalogQueue = DispatchQueue(
        label: "dev.peekswitch.application-catalog",
        qos: .utility
    )

    // MARK: - Presentation state

    private var presentationMode: PresentationMode = .hold
    private var isPresenting = false
    /// Set when the trigger comes up before enumeration finished, so a fast flick
    /// still switches instead of being swallowed.
    private var activateAsSoonAsReady = false
    private var hoveredIndex: Int?
    private var scrollAccumulator = SelectionMath.ScrollAccumulator()
    private var captureToken: UInt64 = 0

    private var onButtonCaptured: ((TriggerButton?) -> Void)?
    private var isLoadingBrowserTabs = false
    private var browserTabRequestID: UInt64 = 0
    private static let browserTabSearchTimeoutNanoseconds: UInt64 = 750_000_000

    /// Supersedes browser-window inspections before they can mutate mode caches or publish icons.
    private var browserInspectionGeneration: UInt64 = 0
    /// The only inspection allowed to request first-time Automation access. It waits briefly after
    /// dismissal so a rapid reopen can cancel it before an Apple Event is sent.
    private var browserAuthorizationTask: Task<Void, Never>?
    private var isBrowserAuthorizationInFlight = false
    private static let browserAuthorizationDelayNanoseconds: UInt64 = 250_000_000

    private enum ConfirmationIntent {
        case selection
        case returnKey
    }

    private struct PendingSearchConfirmation {
        let presentationID: Int
        let query: String
        let intent: ConfirmationIntent
    }

    /// Confirmation pressed while tabs/apps are resolving. Consumed once the same query settles.
    private var pendingSearchConfirmation: PendingSearchConfirmation?

    /// Held only while the switch animation is on screen, so the panel outlives the call that
    /// started it.
    private var activeTransition: TransitionPanel?

    private var hoverTimer: Timer?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        settings: SettingsStore,
        permissions: PermissionsManager,
        registry: WindowRegistry = WindowRegistry(),
        mruTracker: MRUTracker = MRUTracker(),
        thumbnails: ThumbnailService = ThumbnailService(),
        triggerMonitor: TriggerMonitor = TriggerMonitor(),
        hotKeyMonitor: HotKeyMonitor = HotKeyMonitor()
    ) {
        self.settings = settings
        self.permissions = permissions
        self.registry = registry
        self.mruTracker = mruTracker
        self.thumbnails = thumbnails
        self.activation = ActivationService(registry: registry, tabs: browserTabs)
        self.triggerMonitor = triggerMonitor
        self.hotKeyMonitor = hotKeyMonitor
        self.activation.onApplicationLaunchFailure = { [weak self] application, error in
            self?.handleApplicationLaunchFailure(application, error: error)
        }
    }

    // MARK: - Lifecycle

    func start() {
        triggerMonitor.delegate = self
        triggerMonitor.triggerButton = settings.triggerButton
        // So the overlay's tap never swallows the shortcut and leaves it unable to close what it
        // opened.
        triggerMonitor.keyboardShortcut = settings.hotKeyShortcut
        triggerMonitor.logsAllHIDInput = settings.logsAllHIDInput

        // Requirement 5.14 / 10.9: no tap means hotkey-only, not a dead app.
        let tapInstalled = triggerMonitor.install()
        if !tapInstalled {
            Log.app.info("running with the global hotkey as the only trigger")
        }

        // Requirement 6.1, 6.5.
        registerHotKey(settings.hotKeyShortcut)

        mruTracker.startObserving()
        buildPanel()

        // Pre-warm off the main thread. Loading application icons touches the disk and
        // costs roughly 100 ms across a dozen apps; paying it here means the first
        // trigger of the session is as fast as every later one (Requirement 14.1).
        let registry = self.registry
        workQueue.async {
            registry.warmCaches()
            // Learn the Space the app launched on. Without this, the first trigger is the
            // first time anything is remembered, and a user who switches Space before
            // ever opening the switcher would find that Space's windows missing.
            registry.learnCurrentSpace()
        }

        // Discover installed applications in parallel with the window pre-warm, but on its
        // own utility queue. A file-system walk must never sit ahead of a user-triggered window
        // enumeration on the latency-critical serial queue.
        let applicationCatalog = self.applicationCatalog
        applicationCatalogQueue.async { [weak self] in
            let applications = applicationCatalog.applications().map(WindowEntry.applicationEntry)

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Log.registry.info("indexed \(applications.count) installed applications")
                    let changed = self.state.setApplications(applications)
                    if changed, self.state.isVisible {
                        self.afterSearchChanged()
                    }
                    self.resolvePendingSearchConfirmationIfReady()
                }
            }
        }

        // Drop cached state for applications that quit, so a recycled pid can never
        // inherit the wrong name or icon.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                else { return }
                self?.registry.invalidateCache(for: app.processIdentifier)
            }
        }

        // Accessibility only ever reports the windows on the Space that is currently in
        // front, so the only way to know about the others is to look while each one is
        // active. A Space switch is precisely that opportunity, and taking it is what
        // makes windows on other desktops appear in the switcher at all.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                // An overlay belongs to the Space it was opened on. The panel joins every Space, so
                // without this it followed the user to the next desktop still listing the windows
                // enumerated on the previous one, and still placed where their cursor had been.
                //
                // Worse than looking stale, it broke the trigger. The overlay counted as visible, so
                // the next press of the shortcut meant "close this" rather than "open here" — which
                // read as the shortcut simply not working on the new desktop. Dismissing here is
                // what makes the next press open a fresh overlay for the Space the user is actually
                // on, and it matches how a display change is already handled.
                if self.state.isVisible {
                    Log.overlay.info("active Space changed; dismissing so the next trigger opens here")
                    self.dismiss(activating: nil)
                }

                self.learnCurrentSpace()
            }
        }

        // Requirement 8.4.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isVisible else { return }
                Log.overlay.debug("display configuration changed; dismissing")
                self.dismiss(activating: nil)
            }
        }
    }

    /// Requirement 11.4.
    func stop() {
        dismiss(activating: nil)
        triggerMonitor.uninstall()
        hotKeyMonitor.unregister()
        mruTracker.stopObserving()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil

        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
        terminationObserver = nil

        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
    }

    /// Enumerate off the main thread purely to populate the registry's memory of which
    /// windows exist, discarding the result.
    ///
    /// Deliberately not on the presentation path: this runs when the user changes Space,
    /// where a few milliseconds of background work costs nothing, so that the next
    /// trigger already knows about the windows over there.
    private func learnCurrentSpace() {
        let registry = self.registry
        workQueue.async {
            registry.learnCurrentSpace()
        }
    }

    /// Requirement 12.3: takes effect without a restart.
    func applySettingsChange() {
        triggerMonitor.triggerButton = settings.triggerButton
        triggerMonitor.keyboardShortcut = settings.hotKeyShortcut

        // Re-register only on an actual change; re-registering needlessly would reset
        // `hasEverFired`, which is the signal used to tell a swallowed shortcut from a
        // broken handler.
        let desired = settings.hotKeyShortcut
        if hotKeyMonitor.registeredShortcut != desired {
            registerHotKey(desired)
        }
    }

    private func registerHotKey(_ shortcut: HotKeyShortcut) {
        let registered = hotKeyMonitor.register(
            shortcut: shortcut,
            onPress: { [weak self] in self?.handleHotKeyPressed() },
            onRelease: { [weak self] held in self?.handleHotKeyReleased(heldFor: held) }
        )
        // Requirement 6.5.
        permissions.setWarning(.hotkeyUnavailable, active: !registered)
    }

    /// Whether the configured shortcut has ever actually fired. Surfaced in Settings,
    /// because `RegisterEventHotKey` reports success even when another app owns the
    /// combination and silently keeps the keystroke.
    var hotKeyHasFired: Bool { hotKeyMonitor.hasEverFired }

    /// Begin capturing the next mouse button press. The callback receives the captured
    /// button, or `nil` if the press was rejected.
    func beginButtonCapture(_ completion: @escaping (TriggerButton?) -> Void) {
        guard triggerMonitor.isInstalled else {
            // No event tap means no button events at all, so capture cannot work.
            completion(nil)
            return
        }
        onButtonCaptured = completion
        triggerMonitor.isCapturingButton = true
    }

    func cancelButtonCapture() {
        triggerMonitor.isCapturingButton = false
        onButtonCaptured = nil
    }

    // MARK: - Panel construction

    private func buildPanel() {
        // `hoveredIndexProvider` lets the SwiftUI tree read hover state without the
        // controller having to publish it through the observable object (hover
        // changes at 60 Hz; selection is what actually needs to be published).
        let view = OverlayHostView(state: state, controller: self)
        panel = OverlayPanel(content: view)
    }

    fileprivate var currentHoveredIndex: Int? { hoveredIndex }

    // MARK: - Presentation

    private func beginPresentation(mode: PresentationMode) {
        guard !isPresenting else { return }

        // A press arriving while the overlay is up never reaches here: `TriggerResponse` has
        // already turned it into a commit, a dismissal or nothing at all.
        guard !state.isVisible else { return }

        // Cancel a dismissal-time request that is still in its grace period. Once its synchronous
        // Apple Event has begun it cannot be cancelled safely; in that short interval, do not put
        // the overlay underneath a possible Automation sheet.
        invalidateBrowserInspections()
        guard !isBrowserAuthorizationInFlight else {
            Log.registry.debug("browser authorization is in flight; deferring overlay presentation")
            return
        }

        isPresenting = true
        invalidateBrowserTabLoad()
        pendingSearchConfirmation = nil
        presentationMode = mode
        // The hotkey path is persistent from the outset. The button path starts as a
        // hold and is promoted on release if it turns out to have been a tap.
        state.isPersistent = (mode == .toggle)
        activateAsSoonAsReady = false
        scrollAccumulator.reset()
        hoveredIndex = nil

        let stopwatch = Stopwatch("overlay presentation", logger: Log.overlay)

        // Screen geometry must be read on main.
        let cursor = NSEvent.mouseLocation
        let screen = Self.screen(containing: cursor)
        let visibleFrame = screen?.visibleFrame ?? .zero
        let backingScale = screen?.backingScaleFactor ?? 2
        let contentWidth = OverlayPlacement.availableContentWidth(visibleFrame: visibleFrame)
        let contentHeight = OverlayPlacement.availableContentHeight(visibleFrame: visibleFrame)
        // Captured here because it reads `NSScreen` for display names, and sampled per
        // presentation so plugging in or unplugging a monitor is picked up on the next
        // trigger rather than needing a restart.
        let displayLayout = DisplayLayout.current()
        // Read once per presentation, so changing the style in Settings takes effect on
        // the next trigger without a restart (Requirement 12.3).
        let layoutStyle = settings.overlayLayoutStyle
        let viewMode = settings.overlayViewMode
        let pinned = settings.pinnedApplications
        let depth = settings.historyDepth
        // Requirement 15.4: sampled per presentation.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Same treatment for the tint: read per presentation so toggling either the setting or the
        // system's Increase Contrast takes effect on the next trigger rather than needing a restart.
        let tintWindows = settings.tintWindowsByIcon
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        // Hoisted out of the closure: `self` is main-actor isolated, so reaching
        // through it for `registry` on the work queue would be an isolation
        // violation. `WindowRegistry` is internally locked and Sendable.
        let registry = self.registry
        // Captured here, on the main thread, on purpose. See
        // `switchableApplicationsSnapshot()` for why reading the running-application
        // list from the work queue can come back empty right after a switch.
        let applications = registry.switchableApplicationsSnapshot()

        workQueue.async { [weak self] in
            // No retry here on an empty result. `WindowRegistry.enumerate` now
            // cross-checks an empty Accessibility result against CGWindowList and falls
            // back to window-list data, which cannot time out. A retry on top of that
            // only added latency, and invalidating caches to force it made the stall
            // worse by requiring every AX element to be recreated.
            let enumerated = registry.enumerate(applications: applications)

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finishPresentation(
                        enumerated: enumerated,
                        cursor: cursor,
                        visibleFrame: visibleFrame,
                        backingScale: backingScale,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        layoutStyle: layoutStyle,
                        viewMode: viewMode,
                        displayLayout: displayLayout,
                        pinnedApplications: pinned,
                        historyDepth: depth,
                        reduceMotion: reduceMotion,
                        tintWindows: tintWindows,
                        increaseContrast: increaseContrast,
                        stopwatch: stopwatch
                    )
                }
            }
        }
    }

    private func finishPresentation(
        enumerated: [WindowEntry],
        cursor: CGPoint,
        visibleFrame: CGRect,
        backingScale: CGFloat,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        layoutStyle: OverlayLayoutStyle,
        viewMode: OverlayViewMode,
        displayLayout: DisplayLayout,
        pinnedApplications: Set<String>,
        historyDepth: Int,
        reduceMotion: Bool,
        tintWindows: Bool,
        increaseContrast: Bool,
        stopwatch: Stopwatch
    ) {
        defer { isPresenting = false }
        guard let panel else { return }

        mruTracker.prune(livingWindowIDs: Set(enumerated.map(\.windowID)))
        let ordered = mruTracker.ordered(
            enumerated,
            historyDepth: historyDepth,
            pinnedApplications: pinnedApplications
        )

        state.reduceMotion = reduceMotion
        state.tintsWindowsByIcon = tintWindows
        state.increaseContrast = increaseContrast
        state.availableContentWidth = contentWidth
        state.availableContentHeight = contentHeight
        // Set before `load`, because the layout the state derives — including the
        // initial scroll offset — depends on the style, and `load` resolves each
        // window's display against this arrangement.
        state.layoutStyle = layoutStyle
        state.viewMode = viewMode
        state.displayLayout = displayLayout
        state.canCloseWindows = permissions.accessibilityGranted
        state.isCloseButtonHovered = false
        state.load(
            entries: ordered,
            selectedIndex: SelectionMath.initialSelection(count: ordered.count)
        )

        let size = state.layout.panelSize
        let origin = OverlayPlacement.origin(
            panelSize: size,
            cursor: cursor,
            visibleFrame: visibleFrame,
            anchor: layoutStyle.placementAnchor
        )
        // Force the hosting view to reflect the state set a moment ago before the panel
        // becomes visible. SwiftUI would otherwise apply that update on a later pass,
        // and the first frame on screen would show whatever the strip contained last.
        // The empty-state message always gets a plate, whatever the style, so it also
        // always gets the panel shadow that goes with one.
        let hasPlate = ordered.isEmpty || layoutStyle.drawsBackdrop
        // Read per presentation rather than at launch, so toggling it takes effect on the next
        // trigger instead of needing a restart.
        panel.setIncludedInScreenshots(settings.includeOverlayInScreenshots)
        // Hold the cards back, and give the arrangement a new identity, so the synchronous layout
        // pass below rebuilds it and reads the hidden state rather than relying on change
        // notification to have landed. The first visible frame is then an empty panel for the
        // cards to arrive into.
        state.beginPresentation()
        let revealToken = state.presentationID
        panel.present(at: origin, size: size, afterLayout: true, castsShadow: hasPlate)
        state.isVisible = true
        Log.overlay.info("presenting \(ordered.count) cards")
        stopwatch.log()

        // Requirement 5.6: scroll, keys, and reliable primary-card clicks become
        // interesting only now. Passing the panel frame lets the HID-level tap consume
        // clicks on the overlay while preserving normal click-through outside it.
        triggerMonitor.setOverlayTapEnabled(true, clickRegion: panel.frame)
        startHoverTracking()
        installClickMonitors()

        // Let the cards in, on the next run loop pass so the hidden frame the layout above drew
        // has been composited before they start arriving.
        //
        // Stamped with the presentation it belongs to. Without that, triggering twice quickly
        // meant the first presentation's pending reveal fired during the second — which had just
        // set itself hidden — and the second got no entrance at all.
        //
        // Input is already live at this point — hit-testing is arithmetic and does not care
        // whether a card has finished fading in — so the entrance costs no responsiveness.
        DispatchQueue.main.async { [weak self] in
            self?.state.reveal(token: revealToken)
        }

        applyKnownIncognitoWindows(to: ordered)
        // Costs nothing and needs no browser: any window still showing the tab its icon was
        // verified against gets that icon in the first frame instead of waiting for an Apple
        // Event that may take seconds.
        applyRememberedBrowserIcons(to: ordered, presentationID: revealToken)
        // This starts only after the panel is on screen. It is restricted to browsers that have
        // already answered an Apple Event this session, so no Automation prompt can steal focus.
        refreshBrowserWindows(for: ordered, presentationID: revealToken)

        guard !ordered.isEmpty else { return }
        startCaptures(for: ordered, backingScale: backingScale)

        // A release that beat enumeration to the finish line.
        if activateAsSoonAsReady {
            activateAsSoonAsReady = false
            commitSelection()
        }
    }

    /// Badge the private browsing windows already known, without asking anyone.
    ///
    /// Purely a cache read, so it costs nothing and can sit on the presentation path. Restricted
    /// to the windows on screen, so a stale id from a closed window cannot badge a reused one.
    private func applyKnownIncognitoWindows(to entries: [WindowEntry]) {
        let onScreen = Set(entries.map(\.windowID))
        let resolved = knownIncognitoWindowIDs.intersection(onScreen)
        guard resolved != state.incognitoWindowIDs else { return }
        state.incognitoWindowIDs = resolved
    }

    /// Restore already-verified browser icons for windows whose active tab has not changed.
    ///
    /// A cache read only, so it is safe on the presentation path: no Apple Event, no network, and
    /// no consent dialog. The title check is what keeps it honest — see `CachedBrowserIcon`.
    private func applyRememberedBrowserIcons(to entries: [WindowEntry], presentationID: Int) {
        guard !browserIconsByWindowID.isEmpty else { return }

        var restored = 0
        for entry in browserWindowCandidates(in: entries) {
            guard let remembered = browserIconsByWindowID[entry.windowID],
                  remembered.title == entry.title,
                  !knownIncognitoWindowIDs.contains(entry.windowID)
            else { continue }

            if state.setBrowserIcon(
                remembered.icon,
                for: entry.windowID,
                presentationID: presentationID,
                isComposed: true,
                siteTint: remembered.tint
            ) != nil {
                restored += 1
            }
        }

        if restored > 0 {
            Log.registry.info("restored \(restored) verified browser icons without asking a browser")
        }
    }

    private func rememberBrowserIcon(
        _ icon: NSImage,
        for windowID: CGWindowID,
        title: String,
        tint: IconTint?
    ) {
        browserIconsByWindowID[windowID] = CachedBrowserIcon(
            title: title,
            icon: icon,
            tint: tint
        )
        browserIconOrder.removeAll { $0 == windowID }
        browserIconOrder.append(windowID)

        while browserIconsByWindowID.count > Self.maximumRememberedBrowserIcons,
              let oldest = browserIconOrder.first {
            browserIconOrder.removeFirst()
            browserIconsByWindowID.removeValue(forKey: oldest)
        }
    }

    private func forgetBrowserIcon(for windowID: CGWindowID) {
        browserIconsByWindowID.removeValue(forKey: windowID)
        browserIconOrder.removeAll { $0 == windowID }
    }

    /// Refresh active-tab URLs for browsers whose Automation access has already succeeded.
    ///
    /// Called only after the panel is visible. `allowPermissionPrompt: false` makes this a no-op
    /// for a browser that has not been inspected before, so a consent dialog can never interrupt
    /// the presentation. Favicons arrive as fixed-size image replacements and do not relayout it.
    private func refreshBrowserWindows(for entries: [WindowEntry], presentationID: Int) {
        inspectBrowserWindows(
            entries,
            allowPermissionPrompt: false,
            presentationID: presentationID
        )
    }

    /// Ask newly encountered browsers about their windows after the overlay has gone away.
    ///
    /// The first Apple Event to a browser may show macOS's Automation consent dialog. A short
    /// grace period lets a rapid reopen cancel this task before that event is sent. Successful
    /// normal-window favicon requests also prewarm the memory cache for the next presentation;
    /// private and unknown browser modes are never sent to the favicon service.
    private func learnBrowserWindows(for entries: [WindowEntry]) {
        let candidates = browserWindowCandidates(in: entries)
        guard !candidates.isEmpty else { return }

        // Browsing mode never changes for a window. Once every candidate has been settled, the
        // post-presentation refresh owns dynamic URL updates and this prompt-capable path can stop.
        guard candidates.contains(where: {
            !incognitoResolvedWindowIDs.contains($0.windowID)
        }) else { return }

        inspectBrowserWindows(
            candidates,
            allowPermissionPrompt: true,
            presentationID: nil
        )
    }

    private func browserWindowCandidates(in entries: [WindowEntry]) -> [WindowEntry] {
        let browsers = Set(
            BrowserTab.Browser.allCases.filter(\.reportsWindowMode).map(\.bundleIdentifier)
        )
        return entries.filter { entry in
            entry.isWindow && entry.bundleIdentifier.map(browsers.contains) == true
        }
    }

    private func invalidateBrowserInspections() {
        browserInspectionGeneration &+= 1
        browserAuthorizationTask?.cancel()
        browserAuthorizationTask = nil
    }

    /// Match the browser and window-server descriptions once, then derive both static private
    /// mode and dynamic favicon work from those exact pairs.
    private func inspectBrowserWindows(
        _ entries: [WindowEntry],
        allowPermissionPrompt: Bool,
        presentationID: Int?
    ) {
        let candidates = browserWindowCandidates(in: entries)
        guard !candidates.isEmpty else { return }

        browserInspectionGeneration &+= 1
        let generation = browserInspectionGeneration
        let delay = allowPermissionPrompt ? Self.browserAuthorizationDelayNanoseconds : 0
        // Visible refreshes are allowed two short retries. They repair transient AppleScript,
        // title/frame matching and active-URL misses without carrying an unverified favicon from
        // an earlier presentation. The prompt-capable dismissal path remains single-shot.
        let retryDelays: [UInt64] = allowPermissionPrompt
            ? []
            : [180_000_000, 420_000_000]

        let task = Task { [weak self, browserTabs, browserFavicons] in
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }

            guard let self,
                  self.browserInspectionGeneration == generation,
                  !allowPermissionPrompt || !self.state.isVisible
            else { return }

            var pending = candidates

            for attempt in 0...retryDelays.count {
                guard self.browserInspectionGeneration == generation,
                      !allowPermissionPrompt || !self.state.isVisible
                else { return }

                if allowPermissionPrompt {
                    self.isBrowserAuthorizationInFlight = true
                }
                let scripted = await browserTabs.windows(
                    allowPermissionPrompt: allowPermissionPrompt
                )
                if allowPermissionPrompt {
                    self.isBrowserAuthorizationInFlight = false
                    if self.browserInspectionGeneration == generation {
                        self.browserAuthorizationTask = nil
                    }
                }

                // NSAppleScript is synchronous once it starts, so cancellation is enforced here,
                // before stale work can alter mode caches or launch network requests.
                guard self.browserInspectionGeneration == generation else { return }

                let currentWindowIDs = Set(self.state.allWindowEntries.map(\.windowID))
                let paired = IncognitoMatcher.matchedWindows(
                    entries: pending,
                    scripted: scripted
                )
                let matched = paired.filter { currentWindowIDs.contains($0.key) }
                if paired.count != matched.count {
                    // Separates "could not pair" from "paired, then discarded as stale". The two
                    // have nothing in common except the symptom.
                    Log.registry.info("""
                        \(paired.count - matched.count) of \(paired.count) paired browser \
                        windows discarded as no longer current
                        """)
                }

                if !matched.isEmpty {
                    let incognito = Set(
                        matched.compactMap { windowID, window in
                            window.isIncognito ? windowID : nil
                        }
                    )
                    let explicitlyNormal = Set(
                        matched.compactMap { windowID, window in
                            window.allowsFaviconRequest ? windowID : nil
                        }
                    )
                    // A CGWindowID may be recycled. An explicit current normal result clears an
                    // older private classification; unknown modes fail closed and clear nothing.
                    self.knownIncognitoWindowIDs.subtract(explicitlyNormal)
                    self.knownIncognitoWindowIDs.formUnion(incognito)
                    self.incognitoResolvedWindowIDs.formUnion(matched.keys)
                    // A window that turns out to be private must not keep a remembered site icon,
                    // whether it was recycled or reclassified.
                    for windowID in incognito {
                        self.forgetBrowserIcon(for: windowID)
                    }

                    if let presentationID,
                       self.state.isVisible,
                       self.state.presentationID == presentationID {
                        let visibleIDs = Set(self.state.allWindowEntries.map(\.windowID))
                        self.state.incognitoWindowIDs = self.knownIncognitoWindowIDs
                            .intersection(visibleIDs)
                    }

                    // Counts on both sides, not just the matches. "1 matched" alone cannot
                    // distinguish a browser window missing from the switcher's own list from one
                    // that is present but could not be paired with the browser's description of
                    // it — and those are unrelated faults with unrelated fixes.
                    Log.registry.info("""
                        inspected \(matched.count) of \(candidates.count) browser windows \
                        (\(scripted.count) reported by their browsers), \
                        \(incognito.count) incognito
                        """)

                    if matched.count < candidates.count {
                        // Which signal failed, for the windows that did not pair. Titles are not
                        // logged — they are the user's browsing — so this reports only whether
                        // each signal agreed with anything, which is what separates "the two APIs
                        // disagree about the title" from "several windows look identical".
                        let unmatched = candidates.filter { matched[$0.windowID] == nil }
                        for entry in unmatched {
                            let sameBrowser = scripted.filter {
                                $0.browser.bundleIdentifier == entry.bundleIdentifier
                            }
                            let titleAgreements = sameBrowser.filter {
                                let ours = entry.title
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                let theirs = $0.title
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                return !ours.isEmpty && ours == theirs
                            }.count
                            let frameAgreements = sameBrowser.filter {
                                abs($0.frame.minX - entry.frame.minX)
                                    <= IncognitoMatcher.frameTolerance
                                    && abs($0.frame.minY - entry.frame.minY)
                                        <= IncognitoMatcher.frameTolerance
                                    && abs($0.frame.width - entry.frame.width)
                                        <= IncognitoMatcher.frameTolerance
                                    && abs($0.frame.height - entry.frame.height)
                                        <= IncognitoMatcher.frameTolerance
                            }.count
                            Log.registry.info("""
                                unpaired browser window \(entry.windowID): \
                                \(sameBrowser.count) same-browser records, \
                                \(titleAgreements) agree on title, \
                                \(frameAgreements) agree on frame, \
                                our title \(entry.title.count) chars, \
                                our frame \(entry.frame.debugDescription, privacy: .public)
                                """)
                        }
                        for window in scripted where !matched.values.contains(window) {
                            Log.registry.info("""
                                unpaired browser record \(window.identifier): \
                                their title \(window.title.count) chars, \
                                their frame \(window.frame.debugDescription, privacy: .public)
                                """)
                        }
                    }

                    var completedWindowIDs: Set<CGWindowID> = []
                    for (windowID, browserWindow) in matched {
                        // Private and unknown modes are complete app-icon-only results. A normal
                        // record with no URL stays pending because that read can fail transiently.
                        guard browserWindow.allowsFaviconRequest else {
                            completedWindowIDs.insert(windowID)
                            continue
                        }
                        guard !self.knownIncognitoWindowIDs.contains(windowID),
                              let activeTabURL = browserWindow.activeTabURL
                        else { continue }

                        completedWindowIDs.insert(windowID)
                        // Named before the favicon is even requested. The host is already known
                        // here, and a site whose icon cannot be fetched is still worth naming —
                        // which is most of them on a first visit.
                        if let presentationID {
                            self.state.setSiteHost(
                                BrowserTab.host(ofURL: activeTabURL),
                                for: windowID,
                                presentationID: presentationID
                            )
                        }
                        Task { [weak self, browserFavicons] in
                            guard let self,
                                  self.browserInspectionGeneration == generation
                            else { return }

                            guard let favicon = await browserFavicons.favicon(
                                for: activeTabURL,
                                prefetch: presentationID == nil
                            ) else {
                                Log.registry.info("""
                                    no site icon resolved for a browser window; \
                                    keeping its application icon
                                    """)
                                return
                            }

                            // Deliberately not gated on the inspection generation. A generation
                            // change means "do not touch the current presentation", not "this
                            // window's active tab was wrong": dismissing the overlay or opening it
                            // again both bump it, and discarding a resolved icon there is what made
                            // the composed icon come and go. Publication below is still gated, and
                            // reuse is revalidated by title, so recording it cannot show a stale
                            // site for a tab that has since changed.

                            let image = NSImage(
                                cgImage: favicon,
                                size: NSSize(width: favicon.width, height: favicon.height)
                            )
                            image.isTemplate = false

                            // Recorded before any publication decision, for the same reason: an
                            // Apple Event can take seconds, by which time a quick switch has
                            // already closed the overlay.
                            guard let entry = self.state.allWindowEntries.first(where: {
                                $0.windowID == windowID
                            }),
                            !self.knownIncognitoWindowIDs.contains(windowID)
                            else { return }

                            let composed = entry.applicationIcon.map {
                                BrowserWindowIcon.layered(siteIcon: image, browserIcon: $0)
                            } ?? image
                            // Sampled from the site icon rather than the composition, which is
                            // mostly browser: the site is what distinguishes one browser window
                            // from the next.
                            let siteTint = IconTint.sampled(from: image)
                            self.rememberBrowserIcon(
                                composed,
                                for: windowID,
                                title: entry.title,
                                tint: siteTint
                            )

                            // A dismissal-time lookup exists only to warm the caches.
                            guard let presentationID else { return }

                            if self.state.setBrowserIcon(
                                composed,
                                for: windowID,
                                presentationID: presentationID,
                                isComposed: true,
                                siteTint: siteTint
                            ) != nil {
                                Log.registry.info("published a layered site icon for a browser window")
                            } else {
                                Log.registry.info("""
                                    a site icon arrived after its presentation ended; \
                                    it will show on the next one
                                    """)
                            }
                        }
                    }
                    pending.removeAll { completedWindowIDs.contains($0.windowID) }
                }

                guard !pending.isEmpty, attempt < retryDelays.count else { return }
                do {
                    try await Task.sleep(nanoseconds: retryDelays[attempt])
                } catch {
                    return
                }
            }
        }

        if allowPermissionPrompt {
            browserAuthorizationTask?.cancel()
            browserAuthorizationTask = task
        }
    }

    private func startCaptures(for entries: [WindowEntry], backingScale: CGFloat) {
        let windows = entries.filter(\.isWindow)
        guard !windows.isEmpty else { return }

        // Two ways to end up with no use for a screenshot: Icon View draws application icons
        // by choice, and the spiral cannot show a screenshot at all because its seats are
        // wedges. Either way capturing is work whose result is thrown away — and between them
        // they are why neither needs Screen Recording.
        guard state.viewMode.usesThumbnails, state.layoutStyle.canShowThumbnails else { return }
        // Requirement 10.8: without Screen Recording, skip capture entirely and let
        // the cards keep their app icons rather than burning time on calls that fail.
        guard permissions.screenRecordingGranted else { return }

        Task { [weak self, thumbnails] in
            let token = await thumbnails.beginGeneration()
            await MainActor.run { self?.captureToken = token }

            await thumbnails.captureStills(
                for: windows,
                scale: backingScale,
                token: token
            ) { windowID, image in
                self?.state.setThumbnail(image, for: windowID)
            }
        }

        refreshSelectedPreview(backingScale: backingScale)
    }

    /// Requirement 3.4 plus Requirement 9.6–9.8: high-resolution still for the
    /// selected card, then a bounded live refresh of just that card.
    private func refreshSelectedPreview(backingScale: CGFloat) {
        guard state.viewMode.usesThumbnails, state.layoutStyle.canShowThumbnails else { return }
        guard permissions.screenRecordingGranted,
              let entry = state.selectedEntry,
              entry.isWindow else { return }
        let token = captureToken

        Task { [weak self, thumbnails] in
            await thumbnails.captureSelectedPreview(
                for: entry,
                scale: backingScale,
                token: token
            ) { windowID, image in
                self?.state.setThumbnail(image, for: windowID)
            }
            await thumbnails.startLiveStream(
                for: entry,
                scale: backingScale,
                token: token
            ) { windowID, image in
                self?.state.setThumbnail(image, for: windowID)
            }
        }
    }

    // MARK: - Dismissal

    /// Single exit point. `entry == nil` means "leave the frontmost window alone"
    /// (Requirement 8.1–8.4).
    /// - Parameter activationDelay: how long to hold the raise back so the switch animation is
    ///   visible first. Zero means the previous behaviour: raise immediately.
    private func dismiss(activating entry: WindowEntry?, activationDelay: TimeInterval = 0) {
        let wasVisible = state.isVisible

        // Requirement 7.1: the overlay goes away before activation work starts, so
        // the switch reads as instant.
        panel?.dismiss()
        state.isVisible = false
        triggerMonitor.setOverlayTapEnabled(false)
        triggerMonitor.clearHeldState()
        stopHoverTracking()
        removeClickMonitors()
        hoveredIndex = nil
        invalidateBrowserTabLoad()
        pendingSearchConfirmation = nil
        activateAsSoonAsReady = false
        state.isPersistent = false
        // Reset so a stray press starts a fresh presentation rather than being read as
        // another confirmation.
        presentationMode = .hold
        if wasVisible {
            suppressTriggerUntil = DispatchTime.now() + Self.reopenSuppression
        }

        if let entry {
            performActivation(entry, afterDelay: activationDelay)
        }

        // Requirement 8.5, 8.6.
        Task { [thumbnails] in
            await thumbnails.teardown()
        }

        // Before the entries are released: asked now, with the overlay gone, so the Automation
        // consent dialog cannot take focus away from a presentation. Use the unfiltered window
        // snapshot rather than an active search's subset.
        if wasVisible {
            learnBrowserWindows(for: state.allWindowEntries)
        }
        state.releaseThumbnails()

        if wasVisible {
            Log.overlay.debug("overlay dismissed\(entry == nil ? " without switching" : "", privacy: .public)")
        }
    }

    private func performActivation(_ entry: WindowEntry, afterDelay delay: TimeInterval = 0) {
        // Stamped now rather than with the raise, so MRU ordering is already correct if the user
        // re-triggers during the delay. Requirement 2.2's reason for stamping eagerly applies
        // just as much when the raise itself is deferred.
        if entry.isWindow {
            mruTracker.recordActivation(windowID: entry.windowID)
        }

        guard delay > 0 else {
            raise(entry)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.raise(entry)
            }
        }
    }

    private func raise(_ entry: WindowEntry) {
        do {
            let raisedExactWindow = try activation.activate(
                entry,
                canUseAccessibility: permissions.accessibilityGranted
            )
            if !raisedExactWindow {
                Log.activation.debug("activated app only for \(entry.applicationName, privacy: .public)")
            }
        } catch ActivationService.Failure.windowGone {
            // Requirement 7.7, 7.8.
            Log.activation.info("target window vanished before activation; leaving focus alone")
            mruTracker.forget(windowID: entry.windowID)
        } catch ActivationService.Failure.applicationGone {
            if let application = entry.launchableApplication {
                discardUnavailableApplication(application)
                NSSound.beep()
                Log.activation.info("installed application is no longer available at its indexed path")
            } else {
                Log.activation.info("target application quit before activation; leaving focus alone")
                if entry.isWindow {
                    mruTracker.forget(windowID: entry.windowID)
                }
            }
        } catch {
            Log.activation.error("activation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleApplicationLaunchFailure(
        _ application: LaunchableApplication,
        error: Error
    ) {
        discardUnavailableApplication(application)
        NSSound.beep()
        Log.activation.error(
            "removed unlaunchable application \(application.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }

    private func discardUnavailableApplication(_ application: LaunchableApplication) {
        applicationCatalog.remove(application)
        state.removeApplication(id: application.id)
    }

    private func resolvePendingSearchConfirmationIfReady() {
        guard let pending = pendingSearchConfirmation else { return }
        guard state.isVisible,
              state.presentationID == pending.presentationID,
              state.searchQuery == pending.query else {
            pendingSearchConfirmation = nil
            return
        }
        guard !state.isResolvingSearch else { return }

        pendingSearchConfirmation = nil
        commitSelection(intent: pending.intent)
    }

    private func commitSelection(intent: ConfirmationIntent = .selection) {
        if state.isResolvingSearch {
            pendingSearchConfirmation = PendingSearchConfirmation(
                presentationID: state.presentationID,
                query: state.searchQuery,
                intent: intent
            )
            Log.overlay.debug("queued confirmation until local search sources settle")
            return
        }
        pendingSearchConfirmation = nil

        // Return owns the final web fallback. Mouse/trigger confirmation still means a selected
        // local target, so if there is none it retains the established dismiss-without-action
        // behaviour rather than unexpectedly opening a browser.
        if case .returnKey = intent,
           state.canOfferWebSearch,
           let destination = WebSearch.destination(for: state.searchQuery) {
            openInDefaultBrowser(destination)
            return
        }

        guard let entry = state.selectedEntry else {
            dismiss(activating: nil)
            return
        }

        // A web-search result leaves the machine rather than raising anything on it, so it is
        // handled before the activation path that assumes a target to bring forward. Unlike the
        // empty-state offer above, this one is reachable whatever else matched — which is the whole
        // point of it being a result — so it is not restricted to Return.
        if let webSearch = entry.webSearch {
            openInDefaultBrowser(webSearch.destination)
            return
        }

        // Planned before dismissal, because it needs the card's frame while the panel is still
        // on screen, and the thumbnail before `releaseThumbnails` drops it.
        let transition = planTransition(for: entry)
        let ghostImage = state.thumbnails[entry.windowID]
        let ghostIcon = state.displayIcon(for: entry)

        // The overlay still goes away at once (Requirement 7.1); only the raise waits, and only
        // when there is an animation to see.
        dismiss(activating: entry, activationDelay: transition?.activationDelay ?? 0)

        if let transition {
            runTransition(transition, for: entry, image: ghostImage, icon: ghostIcon)
        }
    }

    // MARK: - Switch animation

    /// Work out where the ghost should fly from and to.
    ///
    /// Returns `nil` whenever the animation would mislead rather than explain:
    ///
    /// - **Tabs** have no window frame to fly to.
    /// - **Minimized windows** report a stale or empty frame; the window is going to the Dock's
    ///   idea of somewhere, not to that rectangle.
    /// - **Windows on another Space** are about to trigger a Space switch, and a ghost flying
    ///   across a desktop change looks like a glitch.
    /// - **Reduce Motion**, handled inside `WindowTransition.plan`.
    private func planTransition(for entry: WindowEntry) -> WindowTransition? {
        guard entry.isWindow, !entry.isMinimized, entry.isOnActiveSpace else { return nil }
        guard let panel, state.isVisible else { return nil }
        guard let index = state.entries.firstIndex(where: { $0.id == entry.id }) else { return nil }

        let layout = state.layout
        guard let card = layout.positionedCards(scrollOffset: state.scrollOffset)
            .first(where: { $0.index == index })
        else { return nil }

        // The card's rectangle is in panel top-left coordinates; the ghost is placed in AppKit
        // screen coordinates.
        let drawn = layout.drawnFrame(for: card, selectedScale: state.selectedScale)
        let cardFrame = CGRect(
            x: panel.frame.minX + drawn.minX,
            y: panel.frame.maxY - drawn.maxY,
            width: drawn.width,
            height: drawn.height
        )

        guard let primaryHeight = Self.primaryDisplayHeight() else { return nil }
        let targetFrame = ScreenGeometry.appKitFrame(
            fromQuartz: entry.frame,
            primaryHeight: primaryHeight
        )

        return WindowTransition.plan(
            cardFrame: cardFrame,
            targetFrame: targetFrame,
            displayFrames: NSScreen.screens.map(\.frame),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    private func runTransition(
        _ transition: WindowTransition,
        for entry: WindowEntry,
        image: CGImage?,
        icon: NSImage?
    ) {
        let ghost = TransitionPanel(
            image: image,
            icon: icon,
            startFrame: transition.start
        )
        // Held so the panel is not deallocated mid-animation, and released when it finishes.
        activeTransition = ghost

        Log.overlay.debug("""
            switch animation \(transition.crossesDisplay ? "across displays" : "in place", privacy: .public), \
            moving \(transition.direction.rawValue, privacy: .public)
            """)

        ghost.run(to: transition.end, duration: transition.duration) { [weak self] in
            self?.activeTransition = nil
        }
    }

    /// The main display's height, which is the axis both coordinate systems are flipped about.
    private static func primaryDisplayHeight() -> CGFloat? {
        // `screens.first` is the display whose origin is (0, 0) — the one with the menu bar.
        guard let primary = NSScreen.screens.first else { return nil }
        return primary.frame.maxY
    }

    /// Briefly ignore trigger presses after a presentation ends.
    ///
    /// Defence in depth alongside the dedup in `TriggerMonitor`. Two independent input
    /// sources (the event tap and the raw HID stream) report the same physical button
    /// with no ordering guarantee between them, and the visible cost of a stray
    /// duplicate is the strip reopening the instant it was dismissed. Short enough that
    /// a deliberate second tap still registers.
    private static let reopenSuppression: TimeInterval = 0.12
    private var suppressTriggerUntil: DispatchTime?

    private var isTriggerSuppressed: Bool {
        guard let suppressTriggerUntil else { return false }
        if DispatchTime.now() < suppressTriggerUntil { return true }
        self.suppressTriggerUntil = nil
        return false
    }

    // MARK: - Hover tracking

    private func startHoverTracking() {
        stopHoverTracking()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func sampleHover() {
        guard state.isVisible, let panel, !state.entries.isEmpty else { return }
        let point = NSEvent.mouseLocation
        let index = cardIndex(atScreenPoint: point, panel: panel)

        updateCloseButtonHover(at: point, panel: panel)

        guard index != hoveredIndex else { return }
        hoveredIndex = index

        // Requirement 4.7.
        if let index {
            let previousSelection = state.selectedIndex
            state.setSelection(index)
            if state.selectedIndex != previousSelection {
                onSelectionChanged()
            }
        }
    }

    /// Track whether the cursor is on the close affordance, so it can light up.
    private func updateCloseButtonHover(at point: CGPoint, panel: OverlayPanel) {
        var isOnCloseButton = false

        if panel.frame.contains(point) {
            let pointInPanel = CGPoint(
                x: point.x - panel.frame.minX,
                y: point.y - panel.frame.minY
            )
            if case .close(let index) = state.layout.target(
                atPanelPoint: pointInPanel,
                scrollOffset: state.scrollOffset,
                selectedScale: state.selectedScale
            ), state.entries.indices.contains(index) {
                isOnCloseButton = state.canClose(state.entries[index])
            }
        }

        if state.isCloseButtonHovered != isOnCloseButton {
            state.isCloseButtonHovered = isOnCloseButton
        }
    }

    private func cardIndex(atScreenPoint point: CGPoint, panel: OverlayPanel) -> Int? {
        let frame = panel.frame
        guard frame.contains(point) else { return nil }
        let pointInPanel = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        return state.layout.cardIndex(
            atPanelPoint: pointInPanel,
            scrollOffset: state.scrollOffset,
            // Pass the scale the card is actually drawn at, so the enlarged edges of
            // the selected card are clickable rather than a dead border.
            selectedScale: state.selectedScale
        )
    }

    private func onSelectionChanged() {
        let scale = panel?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        Task { [thumbnails] in
            // Requirement 9.8: the previous card's stream stops before a new one
            // starts. `startLiveStream` enforces the single-stream invariant, but
            // stopping here keeps the gap short when the new card is minimized.
            await thumbnails.stopLiveStream()
        }
        refreshSelectedPreview(backingScale: scale)
    }

    // MARK: - Click handling

    private enum ClickSource: String {
        case eventTap = "HID event-tap"
        case local
        case global
    }

    /// Handle every left click observed while the overlay is visible.
    ///
    /// A nonactivating panel normally receives its own mouse events, but AppKit can
    /// route a first click to the application underneath. Local and global event
    /// monitors are mutually exclusive for a given destination, so both must use the
    /// same decision path. Most importantly, a global click inside the panel is a
    /// fallback card click — not something to ignore.
    ///
    /// - Returns: `true` when a local monitor should consume the event. Global monitors
    ///   cannot consume events, so their caller ignores this result.
    @discardableResult
    private func handleLeftMouseDown(at point: CGPoint, source: ClickSource) -> Bool {
        guard state.isVisible, let panel else { return false }

        let isInsidePanel = panel.frame.contains(point)
        guard isInsidePanel else {
            // Requirement 8.2: a click outside closes the overlay without switching,
            // and is left unconsumed so it still does whatever the user aimed it at.
            dismiss(activating: nil)
            return false
        }

        let pointInPanel = CGPoint(
            x: point.x - panel.frame.minX,
            y: point.y - panel.frame.minY
        )

        switch state.layout.target(
            atPanelPoint: pointInPanel,
            scrollOffset: state.scrollOffset,
            selectedScale: state.selectedScale
        ) {
        case .close(let index):
            // No button is drawn for a window that cannot be closed, so a click there
            // means the card, not the affordance.
            guard state.entries.indices.contains(index),
                  state.canClose(state.entries[index]) else {
                state.setSelection(index)
                commitSelection()
                return true
            }
            Log.overlay.info(
                "close clicked on card \(index) via \(source.rawValue, privacy: .public) monitor"
            )
            closeWindow(at: index)
            return true

        case .card(let index):
            Log.overlay.info(
                "card \(index) clicked via \(source.rawValue, privacy: .public) monitor"
            )
            state.setSelection(index)
            commitSelection()
            return true

        case .confirmSelection:
            // The list and radial styles preview the selected window at size. A click
            // there means "this one", not "never mind".
            Log.overlay.info(
                "preview clicked via \(source.rawValue, privacy: .public) monitor"
            )
            commitSelection()
            return true

        case .background:
            // Consumed so a click on empty panel background cannot fall through to the
            // application underneath.
            dismiss(activating: nil)
            return true
        }
    }

    /// Close the window behind a card and leave the overlay open.
    ///
    /// Staying open is the point: closing windows is a housekeeping task done in runs,
    /// and an overlay that dismissed after each one would mean re-triggering the
    /// switcher for every window.
    private func closeWindow(at index: Int) {
        guard state.entries.indices.contains(index) else { return }
        let entry = state.entries[index]

        do {
            try activation.close(entry, canUseAccessibility: permissions.accessibilityGranted)
        } catch ActivationService.Failure.windowGone {
            // Already gone; dropping the card is still the right outcome.
            Log.activation.debug("window was already closed; removing its card")
        } catch {
            Log.activation.info("""
                could not close \(entry.applicationName, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """)
            return
        }

        invalidateBrowserInspections()
        knownIncognitoWindowIDs.remove(entry.windowID)
        incognitoResolvedWindowIDs.remove(entry.windowID)
        // The id can be handed to a different window later, so the icon verified for this one
        // must not outlive it.
        forgetBrowserIcon(for: entry.windowID)
        mruTracker.forget(windowID: entry.windowID)
        Task { [thumbnails] in
            await thumbnails.stopLiveStream()
        }
        state.remove(windowID: entry.windowID)

        guard !state.entries.isEmpty else {
            // Nothing left to switch to, so there is nothing for the overlay to do.
            Log.overlay.info("last window closed; dismissing")
            dismiss(activating: nil)
            return
        }

        // The card under the cursor has changed, so re-resolve hover and refresh the
        // preview for whatever is now selected.
        hoveredIndex = nil
        resizePanelForCurrentLayout()
        sampleHover()
        onSelectionChanged()
    }

    /// Re-fit the panel after the card count changes.
    ///
    /// Every style sizes itself from the number of cards, so a panel left at its old
    /// size would leave a gap where the closed card was — or, for the strip, keep a
    /// clickable region with nothing in it.
    private func resizePanelForCurrentLayout() {
        guard let panel, state.isVisible else { return }
        let size = state.layout.panelSize
        guard size != panel.frame.size else { return }

        let screen = Self.screen(containing: NSEvent.mouseLocation)
        let visibleFrame = screen?.visibleFrame ?? panel.frame
        let origin = OverlayPlacement.origin(
            panelSize: size,
            // Keep the panel where it is rather than letting it jump to the cursor.
            cursor: CGPoint(x: panel.frame.midX, y: panel.frame.midY),
            visibleFrame: visibleFrame,
            anchor: .cursor
        )
        panel.present(
            at: origin,
            size: size,
            afterLayout: true,
            castsShadow: state.layoutStyle.drawsBackdrop
        )
    }

    private func installClickMonitors() {
        removeClickMonitors()

        // Clicks delivered to PeekSwitch, including the normal card-click path.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow)
                ?? NSEvent.mouseLocation
            return self.handleLeftMouseDown(at: point, source: .local) ? nil : event
        }

        // Clicks delivered to another process. A nonactivating panel can occasionally
        // let its first click reach the app beneath it, so an inside-panel click must be
        // hit-tested and committed here too. Previously this path returned early for
        // the entire panel frame, which is what left the drawer stuck on screen.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.handleLeftMouseDown(at: NSEvent.mouseLocation, source: .global)
            }
        }
    }

    private func removeClickMonitors() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    // MARK: - Helpers

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// The keyboard shortcut goes through exactly the same path as the mouse button.
    ///
    /// This is deliberate rather than incidental. A button a mouse holds inside its own
    /// firmware cannot reach an event tap at all — not even when it is set to "Do
    /// Nothing", which swallows the press rather than passing it on — so the only way to
    /// use such a button is to assign it to a keyboard shortcut. Routing the shortcut
    /// through the same press/release logic means it then behaves identically: tap to
    /// keep the strip open, hold and release to switch.
    private func handleHotKeyPressed() {
        handlePress(from: .keyboardShortcut)
    }

    /// One entry point for both triggers, differing only where they should.
    private func handlePress(from source: TriggerSource) {
        switch TriggerResponse.forPress(
            from: source,
            overlayVisible: state.isVisible,
            mode: presentationMode
        ) {
        case .open:
            guard !isTriggerSuppressed else {
                Log.trigger.debug("ignoring trigger press immediately after a dismissal")
                return
            }
            // Requirement 5.5.
            beginPresentation(mode: .hold)

        case .commitSelection:
            commitSelection()

        case .dismissWithoutSwitching:
            // Requirement 6.2.
            Log.overlay.info("shortcut pressed again; closing the overlay without switching")
            dismiss(activating: nil)

        case .ignore:
            break
        }
    }

    private func handleHotKeyReleased(heldFor duration: TimeInterval) {
        triggerButtonReleased(heldFor: duration)
    }
}

// MARK: - TriggerMonitorDelegate

extension SwitcherController: TriggerMonitorDelegate {

    func triggerButtonPressed() {
        handlePress(from: .button)
    }

    func triggerButtonReleased(heldFor duration: TimeInterval) {
        // A release with nothing on screen has nothing to act on. It arrives routinely — the
        // shortcut's own release lands just after a press closed the overlay — and without this it
        // would leave the tap branch below setting flags for a presentation that is already gone.
        guard state.isVisible || isPresenting else { return }

        // Requirement 5.10 and 8.3, now filtered through the activation mode.
        guard presentationMode == .hold else { return }

        let shouldCommit = settings.activationMode.commitsOnRelease(heldFor: duration)

        guard shouldCommit else {
            // A tap, not a hold. Leave the strip up so the user can read it and click
            // or scroll at their own pace, and remember that this presentation is now
            // a toggle so a later release does not close it.
            presentationMode = .toggle
            activateAsSoonAsReady = false
            state.isPersistent = true
            Log.overlay.debug("tap detected (\(duration, format: .fixed(precision: 3)) s); keeping the strip open")
            return
        }

        if isPresenting {
            // Released faster than enumeration; honour it once the list lands.
            activateAsSoonAsReady = true
            return
        }
        guard state.isVisible else { return }
        commitSelection()
    }

    func leftMousePressed(atScreenPoint point: CGPoint) {
        handleLeftMouseDown(at: point, source: .eventTap)
    }

    func buttonCaptured(number: Int) {
        guard let captured = TriggerButton(number: number) else {
            // Left and right buttons are refused: consuming either would break
            // ordinary clicking everywhere.
            Log.trigger.info("ignoring captured button \(number); only buttons 2 and above can be used")
            onButtonCaptured?(nil)
            onButtonCaptured = nil
            return
        }
        Log.trigger.info("captured trigger button \(number)")
        settings.triggerButton = captured
        applySettingsChange()
        onButtonCaptured?(captured)
        onButtonCaptured = nil
    }

    func scrollReceived(delta: Double) {
        guard state.isVisible, !state.entries.isEmpty else { return }
        // Requirement 4.1, 4.2.
        let steps = scrollAccumulator.consume(delta: delta)
        guard steps != 0 else { return }

        // Requirement 4.3–4.6: wrap at both ends.
        let next = SelectionMath.advance(
            current: state.selectedIndex,
            by: steps,
            count: state.entries.count
        )
        guard next != state.selectedIndex else { return }
        state.setSelection(next)
        // Scrolling takes precedence over a stale hover highlight.
        hoveredIndex = nil
        onSelectionChanged()
    }

    /// Move the selection with the arrow keys.
    ///
    /// Shares everything below the step itself with scrolling — the same wrapping, the same
    /// hover override, the same follow-up work — because they are the same gesture arriving from
    /// a different device, and two paths would drift.
    func arrowPressed(_ direction: ArrowDirection) {
        guard state.isVisible, !state.entries.isEmpty else { return }

        // The arrangement decides what the key means; a grid crosses a row where the others move
        // one card.
        let step = state.layout.selectionStep(for: direction)
        guard step != 0 else { return }

        let next = SelectionMath.advance(
            current: state.selectedIndex,
            by: step,
            count: state.entries.count
        )
        guard next != state.selectedIndex else { return }

        state.setSelection(next)
        // The keyboard has taken over; a highlight left under a stationary pointer would now be
        // claiming a selection that has moved on.
        hoveredIndex = nil
        onSelectionChanged()
    }

    /// The shortcut pressed again while the overlay is up.
    ///
    /// Routed into the same press handling as the global hotkey rather than into `escapePressed()`.
    /// The overlay's own event tap consumes the keystroke — it has to, or a space would be typed as
    /// well — which means the Carbon hotkey never sees it, so this has to reproduce the hotkey's
    /// behaviour exactly rather than approximate it with a dismissal.
    func keyboardShortcutPressed() {
        handlePress(from: .keyboardShortcut)
    }

    func escapePressed() {
        // Requirement 8.1.
        guard state.isVisible else { return }

        // With a search active, Escape backs out of the search first. Closing the whole
        // overlay on a mistyped letter would be a harsh way to learn that.
        if state.clearSearch() {
            pendingSearchConfirmation = nil
            Log.overlay.debug("search cleared")
            afterSearchChanged()
            return
        }
        dismiss(activating: nil)
    }

    func searchCharactersTyped(_ characters: String) {
        guard state.isVisible else { return }
        pendingSearchConfirmation = nil
        let changed = state.appendToSearch(characters)
        // Shape only, never content: the query is the user's own typing. Enough to tell a stray
        // space that the switcher inserted from one the user meant, which is the only way to
        // separate "the caret is drawn too far right" from "a space really is in there".
        if characters.allSatisfy(\.isWhitespace) {
            Log.overlay.info("""
                whitespace typed into search; query is now \(self.state.searchQuery.count)                 characters and ends with whitespace: \
                \(self.state.searchQuery.last?.isWhitespace == true)
                """)
        }
        loadBrowserTabsIfNeeded()
        guard changed else { return }
        afterSearchChanged()
    }

    /// Fetch browser tabs once per presentation, the first time the user types.
    ///
    /// Deliberately not at presentation time: listing tabs costs an Apple Event round trip
    /// per browser window, around 0.3 s in total, against a 150 ms budget for showing the
    /// overlay (Requirement 14.1). Typing is the moment the user is looking for something
    /// by name, and is the only moment tabs are worth that cost.
    /// Relinquish ownership of an AppleScript request without waiting for its synchronous work
    /// to return. The request-id check drops its eventual callback, and a reopened presentation
    /// can start its own 750 ms deadline immediately even if the browser actor is still busy.
    private func invalidateBrowserTabLoad() {
        browserTabRequestID &+= 1
        isLoadingBrowserTabs = false
    }

    private func loadBrowserTabsIfNeeded() {
        guard !state.hasLoadedTabs, !isLoadingBrowserTabs else { return }
        isLoadingBrowserTabs = true
        browserTabRequestID &+= 1

        let requestID = browserTabRequestID
        let presentationID = state.presentationID
        let timeoutNanoseconds = Self.browserTabSearchTimeoutNanoseconds

        Task { [weak self, browserTabs] in
            let tabs = await browserTabs.tabs()
            let applications = await MainActor.run {
                Dictionary(
                    NSWorkspace.shared.runningApplications
                        .compactMap { app in app.bundleIdentifier.map { ($0, app) } },
                    uniquingKeysWith: { first, _ in first }
                )
            }
            let entries = tabs.map { tab in
                WindowEntry.tabEntry(
                    tab,
                    application: applications[tab.browser.bundleIdentifier]
                )
            }

            await MainActor.run {
                self?.finishBrowserTabLoad(
                    entries,
                    requestID: requestID,
                    presentationID: presentationID
                )
            }
        }

        // AppleScript is synchronous inside the browser service and cannot be cancelled while
        // an Automation prompt or an unresponsive browser is holding it. Bound how long it may
        // gate local application results; a late answer is deliberately ignored for this query
        // so the selected app cannot suddenly be replaced under the user.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await MainActor.run {
                self?.timeOutBrowserTabLoad(
                    requestID: requestID,
                    presentationID: presentationID
                )
            }
        }
    }

    private func finishBrowserTabLoad(
        _ entries: [WindowEntry],
        requestID: UInt64,
        presentationID: Int
    ) {
        guard requestID == browserTabRequestID else { return }
        isLoadingBrowserTabs = false

        guard state.isVisible,
              state.presentationID == presentationID,
              !state.hasLoadedTabs else {
            // If this result belonged to a dismissed presentation, free the slot and begin the
            // currently visible search's own request rather than injecting stale tabs into it.
            if state.isVisible, state.isSearching, state.presentationID != presentationID {
                loadBrowserTabsIfNeeded()
            }
            return
        }

        Log.registry.info("found \(entries.count) browser tabs to search")
        settleBrowserTabs(entries)
    }

    private func timeOutBrowserTabLoad(requestID: UInt64, presentationID: Int) {
        guard requestID == browserTabRequestID else { return }
        isLoadingBrowserTabs = false

        guard state.isVisible,
              state.presentationID == presentationID,
              !state.hasLoadedTabs else {
            if state.isVisible, state.isSearching, state.presentationID != presentationID {
                loadBrowserTabsIfNeeded()
            }
            return
        }

        Log.registry.info("browser tab search exceeded 750 ms; continuing with applications")
        settleBrowserTabs([])
    }

    private func settleBrowserTabs(_ entries: [WindowEntry]) {
        let changed = state.setTabs(entries)
        if changed {
            afterSearchChanged()
        }
        resolvePendingSearchConfirmationIfReady()
    }

    func searchBackspacePressed() {
        guard state.isVisible else { return }
        pendingSearchConfirmation = nil
        guard state.backspaceSearch() else { return }
        afterSearchChanged()
    }

    /// Re-fit and re-capture after the visible list changes.
    private func afterSearchChanged() {
        hoveredIndex = nil
        resizePanelForCurrentLayout()
        refreshTabIcons()

        // Filtering can bring windows into view whose thumbnails were never captured,
        // because capture is scoped to what was on screen. Tabs are skipped: they have no
        // window to capture, and a browser screenshot would show whichever tab is currently
        // frontmost rather than the one being offered.
        let capturable = state.entries.filter(\.isWindow)
        guard !capturable.isEmpty else { return }
        let scale = panel?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        startCaptures(for: capturable, backingScale: scale)
    }

    /// Resolve site icons for the tab results currently on screen.
    ///
    /// Bounded to what is visible, which matters here more than it does for windows: a search can
    /// match dozens of tabs, and a browser with forty of them would otherwise fan out forty
    /// requests for a list the user is about to narrow further with the next keystroke. The service
    /// deduplicates by origin underneath, so ten tabs on one site cost one request.
    private func refreshTabIcons() {
        guard state.isVisible else { return }
        let presentationID = state.presentationID

        let pending = state.entries
            .filter { $0.isTab && !state.hasSiteIcon(for: $0) }
            .prefix(Self.maximumVisibleTabIconRequests)

        for entry in pending {
            // Fails closed: a tab whose window did not report the browser's exact `normal` mode is
            // never sent to the network, so a private tab keeps the plain browser icon.
            guard let tab = entry.tab, tab.allowsFaviconRequest else { continue }

            let entryID = entry.id
            let browserIcon = entry.applicationIcon

            Task { [weak self, browserFavicons] in
                guard let self,
                      let favicon = await browserFavicons.favicon(for: tab.url)
                else { return }

                let siteIcon = NSImage(
                    cgImage: favicon,
                    size: NSSize(width: favicon.width, height: favicon.height)
                )
                siteIcon.isTemplate = false

                // Same composition as a browser window's: the browser in front, the site behind
                // it, so a tab result reads as "a page, in this browser" at a glance.
                let composed = browserIcon.map {
                    BrowserWindowIcon.layered(siteIcon: siteIcon, browserIcon: $0)
                } ?? siteIcon

                self.state.setTabIcon(
                    composed,
                    tint: IconTint.sampled(from: siteIcon),
                    for: entryID,
                    presentationID: presentationID
                )
            }
        }
    }

    func confirmPressed() {
        // Requirement 6.4. The shared commit path queues this intent if tabs or applications
        // are still resolving, then preserves Return's final web-search fallback once settled.
        guard state.isVisible else { return }
        commitSelection(intent: .returnKey)
    }

    /// Hand a destination to whichever browser the user has set as their default.
    private func openInDefaultBrowser(_ destination: WebSearch.Destination) {
        // Deliberately not phrased as "no window matched" any more. This is reached both from the
        // empty state and from a web-search result the user picked while local matches were on
        // screen, and a log line that asserted the first would be wrong half the time.
        switch destination {
        case .address:
            Log.overlay.info("opening the query as an address")
        case .search:
            Log.overlay.info("searching the web for the query")
        }

        // Dismissed first, so the overlay is gone before the browser comes forward rather than
        // hanging over it while the page loads.
        dismiss(activating: nil)
        NSWorkspace.shared.open(destination.url)
    }

    func eventTapBecameUnstable(_ unstable: Bool) {
        // Requirement 5.13.
        permissions.setWarning(.eventTapUnstable, active: unstable)
    }
}

// MARK: - Hosting view

/// Bridges the controller's non-published hover index into SwiftUI.
///
/// Hover updates at 60 Hz. Publishing it through `OverlayState` would invalidate the
/// whole strip on every sample; instead the hosting view re-reads it on each render
/// pass that the selection change already triggered, which is the only time the
/// highlight can actually differ.
private struct OverlayHostView: View {
    @ObservedObject var state: OverlayState
    let controller: SwitcherController

    var body: some View {
        OverlayView(state: state, hoveredIndex: controller.currentHoveredIndex)
    }
}
