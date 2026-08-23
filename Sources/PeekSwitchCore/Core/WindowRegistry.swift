import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Enumerates every switchable window (Requirement 1).
///
/// ## Why two APIs
///
/// Neither Accessibility nor CGWindowList is sufficient alone:
///
/// - **CGWindowList** gives front-to-back z-order and CGWindowIDs, both essential.
///   But `.optionOnScreenOnly` omits minimized windows, and Requirement 1.4 says
///   minimized windows must appear. It also cannot raise anything.
/// - **Accessibility** enumerates minimized windows, exposes the standard-window
///   subrole needed to filter out panels and sheets (Requirement 1.5), and is the
///   only way to raise one specific window. But it has no concept of z-order across
///   applications, and no public way to get a CGWindowID.
///
/// So: AX supplies the window set and the raise handles, CGWindowList supplies the
/// ordering, and `_AXUIElementGetWindow` stitches them together by CGWindowID.
///
/// ## Correlation pitfalls
///
/// When `_AXUIElementGetWindow` is unavailable the fallback matches on
/// `(pid, frame)`. That is genuinely ambiguous for windows that share a frame —
/// exactly tiled or stacked windows — so the fallback resolves collisions by
/// consuming each CGWindowList candidate at most once, in z-order. Imperfect, but
/// it degrades to "possibly wrong ordering between two identically-placed windows"
/// rather than "wrong window raised".
///
/// ## Threading
///
/// `enumerate()` blocks on AX round trips and must never be called on the main
/// thread from the event tap path. `SwitcherController` calls it on a utility queue.
///
/// `@unchecked Sendable` is claimed deliberately: the only mutable state is
/// `applicationElements`, and every read and write of it goes through `cacheLock`.
/// `ownProcessID` is immutable. The AX and CGWindowList C APIs are themselves
/// thread-safe. The compiler cannot see the lock discipline, hence `unchecked`.
final class WindowRegistry: @unchecked Sendable {

    /// AX subroles that count as a switchable window. Dialogs and system floating
    /// panels are excluded: they are not things a user "switches to".
    private static let allowedSubroles: Set<String> = [
        kAXStandardWindowSubrole as String
    ]

    private let ownProcessID = ProcessInfo.processInfo.processIdentifier

    /// Cached per-process AX application elements. Creating one is cheap but not
    /// free, and enumeration runs on every overlay presentation.
    private var applicationElements: [pid_t: AXUIElement] = [:]

    /// Cached application name and icon.
    ///
    /// `NSRunningApplication.icon` reads the icon out of the app bundle on disk, which
    /// measured at roughly 8 ms per application — around 100 ms across a dozen apps,
    /// on its own twice the whole enumeration budget in Requirement 1.2. Icons do not
    /// change while an app is running, so they are fetched once and reused.
    private var applicationMetadata: [pid_t: ApplicationMetadata] = [:]

    /// Windows seen through Accessibility at any point in this session.
    ///
    /// This is what makes other Spaces work. Accessibility does not enumerate windows on
    /// inactive Spaces — measured on a live session, `kAXWindowsAttribute` returned
    /// exactly the active Space's ten windows and zero for every application whose
    /// windows had moved elsewhere — but an `AXUIElement` obtained while a window *was*
    /// on the active Space stays valid afterwards, and can still be raised.
    ///
    /// So the registry remembers what it has seen. A window that moves to another Space
    /// keeps its entry, keeps its raise handle, and keeps being listed. Entries are
    /// dropped once the window server stops reporting the window at all.
    private var rememberedWindows: [CGWindowID: RememberedWindow] = [:]

    private let cacheLock = NSLock()

    struct ApplicationMetadata {
        let name: String
        let icon: NSImage?
        /// Used to identify an application across launches, for the pinned-applications
        /// setting. A localized name would break the moment the user changed language, and
        /// two applications can legitimately share one.
        let bundleIdentifier: String?
    }

    private struct RememberedWindow {
        let processID: pid_t
        let axElement: AXUIElement
        var title: String
        var frame: CGRect
        var isMinimized: Bool
        /// When this window was last seen on the active Space. Carried into the entry so
        /// ordering can prefer the window you were most recently looking at.
        var lastSeen: TimeInterval
    }

    // MARK: - Public

    /// The set of applications worth enumerating, captured on the caller's thread.
    ///
    /// This is deliberately separate from `enumerate` so callers can take the snapshot
    /// on the main thread. `NSWorkspace.shared.runningApplications` is maintained on
    /// the main thread and churns precisely when an application is activated — which
    /// is the moment right before the switcher is typically reopened. Reading it from
    /// the enumeration queue could come back short, or empty, producing a switcher
    /// with no windows in it immediately after a switch.
    func switchableApplicationsSnapshot() -> [NSRunningApplication] {
        switchableApplications()
    }

    /// Snapshot of the current window set. Ordered arbitrarily; `MRUTracker.ordered`
    /// imposes the real order.
    ///
    /// - Parameter applications: apps to inspect, ideally captured on the main thread
    ///   via `switchableApplicationsSnapshot()`. Passing `nil` gathers them here, which
    ///   is fine for diagnostics but carries the race described above.
    func enumerate(applications: [NSRunningApplication]? = nil) -> [WindowEntry] {
        let stopwatch = Stopwatch("window enumeration", logger: Log.registry)
        defer { stopwatch.log() }

        let apps = applications ?? switchableApplications()
        let zIndex = captureZOrder(
            regularProcessIDs: Set(apps.map(\.processIdentifier))
        )

        // Without Accessibility, every AX call against another process stalls until
        // the messaging timeout expires and then fails. Across a dozen apps that is
        // hundreds of milliseconds spent to learn nothing, blowing the 50 ms budget
        // in Requirement 1.2. Check once and take the CGWindowList-only path instead.
        //
        // That path is not merely an optimisation: Requirement 10.10 says activation
        // falls back to raising the owning application, and that is only reachable if
        // there are cards to select in the first place.
        guard AXIsProcessTrusted() else {
            let entries = enumerateFromWindowListOnly(zIndex: zIndex, apps: apps)
            Log.registry.debug("enumerated \(entries.count) windows without Accessibility")
            return entries
        }

        let seenAt = Date().timeIntervalSinceReferenceDate
        var live = enumerateViaAccessibility(zIndex: zIndex, apps: apps)
        if !live.isEmpty {
            remember(live, at: seenAt)
            pruneRememberedWindows(liveWindowIDs: zIndex.liveWindowIDs)

            // Everything Accessibility returned is on the active Space right now — that is what
            // "Accessibility returned it" means, since it cannot see any other Space.
            for index in live.indices {
                live[index].lastSeenOnActiveSpace = seenAt
                live[index].isOnActiveSpace = true
            }

            // Windows on other Spaces, in order of how much is known about them: what
            // Accessibility told us previously first, then whatever the window server
            // can offer for windows this session has never seen.
            var entries = live
            var seen = Set(entries.map(\.windowID))

            let remembered = rememberedEntries(excluding: seen, zIndex: zIndex, apps: apps)
            entries.append(contentsOf: remembered)
            seen.formUnion(remembered.map(\.windowID))

            let discovered = offScreenEntries(excluding: seen, zIndex: zIndex, apps: apps)
            entries.append(contentsOf: discovered)

            // Info rather than debug: this breakdown is the one line that explains why a
            // particular window is or is not in the switcher, and debug records are not
            // retained long enough to answer that after the fact.
            Log.registry.info("""
                enumerated \(entries.count) windows \
                (\(live.count) on this Space, \(remembered.count) remembered elsewhere, \
                \(discovered.count) newly discovered elsewhere)
                """)
            return entries
        }

        // Accessibility produced nothing. Before believing that, cross-check against
        // CGWindowList, which needs no permission and cannot time out. If the window
        // server can see normal-layer windows, then "no windows" is a lie and the AX
        // queries simply failed — most often because the system was busy activating an
        // application a moment earlier.
        //
        // Falling back to the window-list data yields real, selectable cards (app icon
        // instead of a thumbnail, and activation raises the owning application rather
        // than the exact window). That is a far better answer than an empty box telling
        // the user nothing is open while a dozen windows are visibly on screen.
        guard !zIndex.byWindowID.isEmpty else {
            Log.registry.debug("no windows found by either Accessibility or CGWindowList")
            return []
        }

        let fallback = enumerateFromWindowListOnly(zIndex: zIndex, apps: apps)
        Log.registry.error("""
            Accessibility enumeration returned nothing across \(apps.count) applications \
            while CGWindowList sees \(zIndex.byWindowID.count) windows; \
            falling back to \(fallback.count) window-list entries
            """)
        return fallback
    }

    // MARK: - Accessibility path

    private func enumerateViaAccessibility(
        zIndex: ZOrderSnapshot,
        apps: [NSRunningApplication]
    ) -> [WindowEntry] {
        guard !apps.isEmpty else { return [] }

        // The geometry fallback needs a shared "already claimed" set across apps, so
        // it cannot run in parallel. With `_AXUIElementGetWindow` available — the
        // normal case — each app is fully independent, and going wide keeps a slow or
        // unresponsive app from serialising everything behind its timeout.
        guard AXBridge.supportsDirectWindowIDLookup else {
            var consumed = Set<CGWindowID>()
            return apps.flatMap { windows(for: $0, zIndex: zIndex, consumed: &consumed) }
        }

        var perApp = [[WindowEntry]](repeating: [], count: apps.count)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            var unused = Set<CGWindowID>()
            let entries = self.windows(for: apps[index], zIndex: zIndex, consumed: &unused)
            guard !entries.isEmpty else { return }
            lock.lock()
            perApp[index] = entries
            lock.unlock()
        }

        return perApp.flatMap { $0 }
    }

    private func windows(
        for app: NSRunningApplication,
        zIndex: ZOrderSnapshot,
        consumed: inout Set<CGWindowID>
    ) -> [WindowEntry] {
        let pid = app.processIdentifier
        let appElement = applicationElement(for: pid)
        guard let axWindows = AXBridge.elements(appElement, kAXWindowsAttribute as String) else {
            return []
        }

        let appMetadata = metadata(for: app)
        var entries: [WindowEntry] = []
        entries.reserveCapacity(axWindows.count)

        for axWindow in axWindows {
            guard isSwitchable(axWindow) else { continue }

            let title = AXBridge.string(axWindow, kAXTitleAttribute as String) ?? ""
            let isMinimized = AXBridge.bool(axWindow, kAXMinimizedAttribute as String) ?? false
            let origin = AXBridge.point(axWindow, kAXPositionAttribute as String) ?? .zero
            let size = AXBridge.size(axWindow, kAXSizeAttribute as String) ?? .zero
            let frame = CGRect(origin: origin, size: size)

            // Zero-sized windows are transient artefacts of apps mid-launch.
            guard isMinimized || (frame.width > 1 && frame.height > 1) else { continue }

            guard let windowID = resolveWindowID(
                for: axWindow,
                pid: pid,
                frame: frame,
                zIndex: zIndex,
                consumed: &consumed
            ) else { continue }

            entries.append(
                WindowEntry(
                    windowID: windowID,
                    processID: pid,
                    applicationName: appMetadata.name,
                    applicationIcon: appMetadata.icon,
                    bundleIdentifier: appMetadata.bundleIdentifier,
                    title: title,
                    frame: frame,
                    isMinimized: isMinimized,
                    // Minimized windows are absent from CGWindowList, so they sort to
                    // the back rather than claiming a spurious front position.
                    zOrder: zIndex.byWindowID[windowID] ?? Int.max - 1,
                    axElement: axWindow
                )
            )
        }
        return entries
    }

    // MARK: - Cross-Space windows

    /// Record what Accessibility just told us, so these windows stay listable after they
    /// move to a Space where Accessibility can no longer see them.
    private func remember(_ entries: [WindowEntry], at seenAt: TimeInterval) {
        cacheLock.lock()
        for entry in entries {
            guard let axElement = entry.axElement else { continue }
            rememberedWindows[entry.windowID] = RememberedWindow(
                processID: entry.processID,
                axElement: axElement,
                title: entry.title,
                frame: entry.frame,
                isMinimized: entry.isMinimized,
                // Being returned by Accessibility *is* being on the active Space, so this
                // is the moment the window was last in front of the user. Space changes
                // call `learnCurrentSpace`, so the stamp keeps up without a presentation.
                lastSeen: seenAt
            )
        }
        cacheLock.unlock()
    }

    /// Forget windows the window server no longer reports.
    ///
    /// Liveness comes from the all-Spaces window list rather than from probing each
    /// remembered element, because probing is an IPC round trip per window and this runs
    /// on the presentation path. A closed window disappears from that list immediately.
    private func pruneRememberedWindows(liveWindowIDs: Set<CGWindowID>) {
        guard !liveWindowIDs.isEmpty else { return }
        cacheLock.lock()
        rememberedWindows = rememberedWindows.filter { liveWindowIDs.contains($0.key) }
        cacheLock.unlock()
    }

    /// Entries for remembered windows that Accessibility did not return this time —
    /// which, in practice, means they are on another Space.
    ///
    /// These keep their `axElement`, so activating one raises that exact window and lets
    /// macOS switch Spaces to reach it, exactly as if it were on the current Space.
    private func rememberedEntries(
        excluding seen: Set<CGWindowID>,
        zIndex: ZOrderSnapshot,
        apps: [NSRunningApplication]
    ) -> [WindowEntry] {
        cacheLock.lock()
        let candidates = rememberedWindows.filter { !seen.contains($0.key) }
        cacheLock.unlock()

        guard !candidates.isEmpty else { return [] }

        var metadataByPID: [pid_t: ApplicationMetadata] = [:]
        for app in apps {
            metadataByPID[app.processIdentifier] = metadata(for: app)
        }

        // Fresher geometry and titles when the window server has them; a browser window
        // whose tab changed while on another Space would otherwise show a stale title.
        var latestByID: [CGWindowID: ZOrderSnapshot.Candidate] = [:]
        for candidate in zIndex.offScreenCandidates {
            latestByID[candidate.id] = candidate
        }

        return candidates.compactMap { windowID, remembered in
            // Restricted to applications that would qualify on the Accessibility path,
            // so a quit-and-relaunched pid cannot resurrect a stale window.
            guard let appMetadata = metadataByPID[remembered.processID] else { return nil }

            let latest = latestByID[windowID]
            let title = latest?.title.flatMap { $0.isEmpty ? nil : $0 } ?? remembered.title

            return WindowEntry(
                windowID: windowID,
                processID: remembered.processID,
                applicationName: appMetadata.name,
                applicationIcon: appMetadata.icon,
                bundleIdentifier: appMetadata.bundleIdentifier,
                title: title,
                frame: latest?.frame ?? remembered.frame,
                // A window absent from the on-screen list may be minimized or simply on
                // another Space, and the two are not distinguishable from here. The
                // remembered flag is the last thing Accessibility actually said.
                isMinimized: remembered.isMinimized,
                zOrder: zIndex.byWindowID[windowID] ?? Int.max - 1,
                axElement: remembered.axElement,
                // The whole reason this matters: these windows are on another Space, so
                // this is the only recency signal they have.
                lastSeenOnActiveSpace: remembered.lastSeen
            )
        }
    }

    /// Entries for windows on other Spaces that this session has never seen through
    /// Accessibility, built from the window server's data alone.
    ///
    /// `axElement` is nil, so activating one brings its application forward rather than
    /// raising that specific window (the Requirement 10.10 degraded path). That is the
    /// honest limit of what is knowable without ever having had Accessibility access to
    /// the window: it is better to offer the window and switch approximately than to
    /// pretend it does not exist.
    private func offScreenEntries(
        excluding seen: Set<CGWindowID>,
        zIndex: ZOrderSnapshot,
        apps: [NSRunningApplication]
    ) -> [WindowEntry] {
        let fresh = zIndex.offScreenCandidates.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return [] }

        var metadataByPID: [pid_t: ApplicationMetadata] = [:]
        for app in apps {
            metadataByPID[app.processIdentifier] = metadata(for: app)
        }

        return fresh.compactMap { candidate in
            guard let appMetadata = metadataByPID[candidate.pid] else { return nil }
            return WindowEntry(
                windowID: candidate.id,
                processID: candidate.pid,
                applicationName: appMetadata.name,
                applicationIcon: appMetadata.icon,
                bundleIdentifier: appMetadata.bundleIdentifier,
                title: candidate.title ?? "",
                frame: candidate.frame,
                isMinimized: false,
                zOrder: zIndex.byWindowID[candidate.id] ?? Int.max - 1,
                axElement: nil
            )
        }
    }

    // MARK: - Degraded path

    /// Windows built purely from CGWindowList, for when Accessibility is unavailable.
    ///
    /// Titles need Screen Recording, so they are frequently empty here and the card
    /// falls back to the application name. `axElement` is nil, which is what tells
    /// `ActivationService` to activate the application rather than a specific window.
    /// Minimized windows are simply absent, because CGWindowList does not report them.
    private func enumerateFromWindowListOnly(
        zIndex: ZOrderSnapshot,
        apps: [NSRunningApplication]
    ) -> [WindowEntry] {
        var metadataByPID: [pid_t: ApplicationMetadata] = [:]
        for app in apps {
            metadataByPID[app.processIdentifier] = metadata(for: app)
        }

        var entries: [WindowEntry] = []
        entries.reserveCapacity(zIndex.byWindowID.count)

        for (pid, candidates) in zIndex.candidatesByPID {
            // Restrict to apps that would qualify under the AX path too, so the two
            // paths list the same set of applications.
            guard let appMetadata = metadataByPID[pid] else { continue }

            // `candidatesByPID` already carries the plausible off-screen windows, so this
            // path spans Spaces too.
            for candidate in candidates {
                guard candidate.frame.width > 1, candidate.frame.height > 1 else { continue }
                entries.append(
                    WindowEntry(
                        windowID: candidate.id,
                        processID: pid,
                        applicationName: appMetadata.name,
                        applicationIcon: appMetadata.icon,
                        bundleIdentifier: appMetadata.bundleIdentifier,
                        title: candidate.title ?? "",
                        frame: candidate.frame,
                        isMinimized: false,
                        zOrder: zIndex.byWindowID[candidate.id] ?? Int.max - 1,
                        axElement: nil
                    )
                )
            }
        }
        return entries
    }

    /// Populate the icon and name caches ahead of the first trigger.
    ///
    /// Called once at launch on a background queue. Without this the first overlay
    /// presentation of the session pays the full icon-loading cost and misses the
    /// 150 ms budget in Requirement 14.1; every later one would be fast, which is a
    /// bad first impression for the one interaction the app exists for.
    func warmCaches() {
        for app in switchableApplications() {
            _ = metadata(for: app)
        }
        Log.registry.debug("warmed metadata for \(self.cachedApplicationCount) applications")
    }

    var cachedApplicationCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return applicationMetadata.count
    }

    /// Forget a process's cached state, e.g. after it quits.
    func invalidateCache(for pid: pid_t) {
        cacheLock.lock()
        applicationElements.removeValue(forKey: pid)
        applicationMetadata.removeValue(forKey: pid)
        rememberedWindows = rememberedWindows.filter { $0.value.processID != pid }
        cacheLock.unlock()
    }

    func invalidateAllCaches() {
        cacheLock.lock()
        applicationElements.removeAll()
        applicationMetadata.removeAll()
        rememberedWindows.removeAll()
        cacheLock.unlock()
    }

    /// How many windows are being remembered from Spaces other than the active one.
    /// Surfaced in diagnostics.
    var rememberedWindowCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return rememberedWindows.count
    }

    /// Learn the windows on whichever Space is active now, without showing anything.
    ///
    /// Called when the user switches Spaces. Accessibility can only see the active
    /// Space, so the only way to build a picture that spans Spaces is to look while each
    /// one is in front — which is exactly what a Space change offers. Cheap enough to do
    /// eagerly: enumeration is a few milliseconds once the caches are warm.
    func learnCurrentSpace() {
        _ = enumerate()
    }

    /// True when the target window still exists (Requirement 7.7, 7.8).
    func windowStillExists(_ entry: WindowEntry) -> Bool {
        guard let axElement = entry.axElement else { return false }
        // Any successful attribute read proves the element is still live.
        return AXBridge.copyAttribute(axElement, kAXRoleAttribute as String) != nil
    }

    // MARK: - Z-order

    struct ZOrderSnapshot {
        struct Candidate {
            let id: CGWindowID
            let pid: pid_t
            let frame: CGRect
            /// Populated only when Screen Recording is granted; CGWindowList withholds
            /// window names otherwise.
            let title: String?
            /// False for windows on another Space, minimized, or belonging to a hidden
            /// application.
            let isOnScreen: Bool
        }

        /// windowID -> front-to-back index, 0 == frontmost. Windows on the active Space
        /// come first, then everything else.
        var byWindowID: [CGWindowID: Int] = [:]
        /// pid -> candidate windows in z-order, for the geometry fallback and for the
        /// Accessibility-denied path.
        var candidatesByPID: [pid_t: [Candidate]] = [:]
        /// Every normal-layer window the window server knows about, whichever Space it
        /// is on. Used to tell a remembered window that still exists from one that has
        /// been closed.
        var liveWindowIDs: Set<CGWindowID> = []
        /// Candidates that are not on the active Space, already filtered down to ones
        /// that look like real windows.
        var offScreenCandidates: [Candidate] = []
    }

    /// Minimum size for an off-screen window to be believable.
    ///
    /// The off-screen list is full of helper surfaces — 64×64 icon hosts, 500×500
    /// scratch windows, toolbar and autofill panels — and unlike the Accessibility path
    /// there is no subrole to filter on. Size plus a title is what is left.
    private static let minimumOffScreenSize = CGSize(width: 200, height: 120)

    /// Requirement 2.6's ordering source, plus the cross-Space window census.
    ///
    /// ## Why two passes
    ///
    /// `.optionOnScreenOnly` returns only the active Space, in true front-to-back order.
    /// `.optionAll` returns every Space but in no useful order and mixed with a great
    /// deal of noise — on a normal session, 10 real on-screen windows against roughly
    /// 190 off-screen entries, most of them helper surfaces belonging to XPC services.
    ///
    /// So the on-screen pass defines the ordering and the all-windows pass supplies
    /// coverage: existence (to know a remembered window is still alive) and candidates
    /// for windows Accessibility cannot see.
    /// - Parameter regularProcessIDs: processes whose off-screen windows are worth
    ///   considering, captured on the main thread by the caller.
    ///
    ///   Passed in rather than read here on purpose. `NSWorkspace.runningApplications` is
    ///   maintained on the main thread and churns exactly when an application is being
    ///   activated — the moment before the switcher is typically reopened — so reading it
    ///   from the enumeration queue can come back short. `switchableApplicationsSnapshot()`
    ///   exists for the same reason.
    func captureZOrder(regularProcessIDs: Set<pid_t>) -> ZOrderSnapshot {
        var snapshot = ZOrderSnapshot()

        let onScreen = normalLayerWindows([.optionOnScreenOnly, .excludeDesktopElements])
        var index = 0
        for info in onScreen {
            guard let candidate = candidate(from: info, isOnScreen: true) else { continue }
            snapshot.byWindowID[candidate.id] = index
            index += 1
            snapshot.candidatesByPID[candidate.pid, default: []].append(candidate)
            snapshot.liveWindowIDs.insert(candidate.id)
        }

        // Regular applications only. An off-screen window belonging to an agent or an
        // XPC service is never something the user switches to, and that single check
        // removes most of the noise before any heuristic is applied.
        for info in normalLayerWindows([.optionAll, .excludeDesktopElements]) {
            guard let candidate = candidate(from: info, isOnScreen: false) else { continue }
            snapshot.liveWindowIDs.insert(candidate.id)
            guard snapshot.byWindowID[candidate.id] == nil else { continue }

            snapshot.byWindowID[candidate.id] = index
            index += 1

            guard regularProcessIDs.contains(candidate.pid),
                  isPlausibleOffScreenWindow(candidate) else { continue }

            snapshot.candidatesByPID[candidate.pid, default: []].append(candidate)
            snapshot.offScreenCandidates.append(candidate)
        }

        return snapshot
    }

    private func normalLayerWindows(_ options: CGWindowListOption) -> [[String: Any]] {
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // Layer 0 is the normal application window layer. Anything else is the menu bar,
        // the Dock, a status item, a notification, or similar.
        return raw.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
    }

    private func candidate(
        from info: [String: Any],
        isOnScreen: Bool
    ) -> ZOrderSnapshot.Candidate? {
        guard let number = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              pid != ownProcessID
        else { return nil }

        var frame = CGRect.zero
        if let bounds = info[kCGWindowBounds as String] as? [String: Any],
           let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
            frame = rect
        }

        return ZOrderSnapshot.Candidate(
            id: number,
            pid: pid,
            frame: frame,
            title: info[kCGWindowName as String] as? String,
            isOnScreen: isOnScreen
        )
    }

    /// Whether an off-screen window looks like something a user would switch to.
    ///
    /// A title is the strongest single signal available: measured on a live session,
    /// requiring one cut 147 off-screen entries down to 13, and those 13 were almost
    /// entirely real windows. It is not perfect — a couple of helper surfaces do carry
    /// titles — which is why remembered Accessibility data is preferred over this
    /// wherever it exists.
    private func isPlausibleOffScreenWindow(_ candidate: ZOrderSnapshot.Candidate) -> Bool {
        guard let title = candidate.title, !title.isEmpty else { return false }
        return candidate.frame.width >= Self.minimumOffScreenSize.width
            && candidate.frame.height >= Self.minimumOffScreenSize.height
    }

    // MARK: - Private

    private func switchableApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            // `.regular` excludes agents and daemons, which have no user-facing
            // windows to switch to.
            app.activationPolicy == .regular
                // Requirement 1.6.
                && app.processIdentifier != ownProcessID
                && !app.isTerminated
        }
    }

    private func metadata(for app: NSRunningApplication) -> ApplicationMetadata {
        let pid = app.processIdentifier

        cacheLock.lock()
        if let cached = applicationMetadata[pid] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Read outside the lock: this is the slow disk-touching part, and holding the
        // lock through it would serialise the concurrent per-app enumeration.
        let resolved = ApplicationMetadata(
            name: app.localizedName ?? "Unknown",
            icon: app.icon,
            bundleIdentifier: app.bundleIdentifier
        )

        cacheLock.lock()
        applicationMetadata[pid] = resolved
        cacheLock.unlock()
        return resolved
    }

    private func applicationElement(for pid: pid_t) -> AXUIElement {
        cacheLock.lock()
        if let cached = applicationElements[pid] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let element = AXUIElementCreateApplication(pid)
        AXBridge.applyMessagingTimeout(element)

        cacheLock.lock()
        applicationElements[pid] = element
        cacheLock.unlock()
        return element
    }

    /// Requirement 1.5.
    private func isSwitchable(_ axWindow: AXUIElement) -> Bool {
        guard let role = AXBridge.string(axWindow, kAXRoleAttribute as String),
              role == kAXWindowRole as String
        else { return false }

        guard let subrole = AXBridge.string(axWindow, kAXSubroleAttribute as String) else {
            // Some apps omit the subrole. Accept those: rejecting them would lose
            // real windows, and the role check above already excluded most noise.
            return true
        }
        return Self.allowedSubroles.contains(subrole)
    }

    private func resolveWindowID(
        for axWindow: AXUIElement,
        pid: pid_t,
        frame: CGRect,
        zIndex: ZOrderSnapshot,
        consumed: inout Set<CGWindowID>
    ) -> CGWindowID? {
        if let direct = AXBridge.windowID(for: axWindow) {
            return direct
        }

        // Geometry fallback. Consume candidates so two same-framed windows cannot
        // both resolve to the same CGWindowID.
        guard let candidates = zIndex.candidatesByPID[pid] else { return nil }
        let tolerance: CGFloat = 2
        if let match = candidates.first(where: { candidate in
            !consumed.contains(candidate.id)
                && abs(candidate.frame.origin.x - frame.origin.x) <= tolerance
                && abs(candidate.frame.origin.y - frame.origin.y) <= tolerance
                && abs(candidate.frame.width - frame.width) <= tolerance
                && abs(candidate.frame.height - frame.height) <= tolerance
        }) {
            consumed.insert(match.id)
            return match.id
        }

        // Minimized windows have no CGWindowList row at all; fall back to any
        // unconsumed candidate for the process so the window is still listed.
        if let leftover = candidates.first(where: { !consumed.contains($0.id) }) {
            consumed.insert(leftover.id)
            return leftover.id
        }
        return nil
    }
}
