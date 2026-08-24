import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Per-window most-recently-used ordering (Requirement 2).
///
/// Two sources feed the order, in priority order:
///
/// 1. **Observed activations.** An `AXObserver` on the frontmost application
///    reports `kAXFocusedWindowChangedNotification`, and `NSWorkspace` reports app
///    activations. Both stamp the affected window with the current time. This is
///    the authoritative signal and it captures window-to-window moves *inside* one
///    app, which app-level tracking would miss entirely.
/// 2. **Z-order seeding.** Any window this session has never seen activate gets a
///    synthetic timestamp derived from its front-to-back position
///    (Requirement 2.6). Front-to-back order is itself an excellent MRU proxy, so
///    the very first invocation after launch is already correctly ordered rather
///    than arbitrary.
///
/// The observer is retargeted to whichever app is frontmost instead of one observer
/// per running app. One app can only have one focused window at a time, so a single
/// retargeted observer sees every focus change that matters, at a fraction of the
/// setup cost and with no per-app teardown to leak.
final class MRUTracker {

    /// Injectable clock so ordering is testable without sleeping.
    private let now: () -> TimeInterval
    private var timestamps: [CGWindowID: TimeInterval] = [:]

    /// Offsets that keep the three ordering tiers from interleaving.
    ///
    /// A real timestamp is seconds since 2001, currently around 8 × 10⁸, so subtracting
    /// 2 × 10⁹ puts every "seen" window below every "used" one while still ordering the
    /// seen windows among themselves by time. The unseen base is far below both, leaving
    /// room for z-order to be subtracted from it without ever climbing into a real tier.
    private static let seenBase: TimeInterval = -2e9
    private static let unseenBase = -Double(Int.max / 2)

    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var observedAppElement: AXUIElement?

    init(now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.now = now
    }

    deinit {
        stopObserving()
    }

    // MARK: - Recording

    /// Requirement 2.2.
    func recordActivation(windowID: CGWindowID) {
        timestamps[windowID] = now()
    }

    /// Requirement 2.8.
    func forget(windowID: CGWindowID) {
        timestamps.removeValue(forKey: windowID)
    }

    /// Drop timestamps for windows that no longer exist, so the table cannot grow
    /// without bound over a long uptime.
    func prune(livingWindowIDs: Set<CGWindowID>) {
        timestamps = timestamps.filter { livingWindowIDs.contains($0.key) }
    }

    func timestamp(for windowID: CGWindowID) -> TimeInterval? {
        timestamps[windowID]
    }

    // MARK: - Ordering

    /// Sort `entries` newest-first, then pin the focused window leftmost and cap the
    /// list at `historyDepth` (Requirements 2.3, 2.4, 2.7).
    ///
    /// Truncation happens *after* the focused window is pinned, so the window the
    /// user is currently in is never the one dropped by a small history depth.
    ///
    /// ## Three tiers, in order of how much they actually tell us
    ///
    /// 1. **Used.** An observed activation: the user switched to this window. Authoritative.
    /// 2. **Seen.** The window was on the active Space at a known time, but never focused
    ///    while PeekSwitch was watching. This tier exists for windows on other desktops:
    ///    Accessibility cannot see them, so they have no focus history, and without it they
    ///    would be ordered by their position in the window server's all-Spaces list — which
    ///    is arbitrary. "When you last had it in front of you" is a much better answer.
    /// 3. **Never seen.** Ordered by z-order, which is itself a good MRU proxy
    ///    (Requirement 2.6).
    ///
    /// The tiers are offset so they can never interleave. Within a tier the raw timestamp
    /// orders things, so a more recent window always wins against a less recent one of the
    /// same kind.
    /// - Parameter pinnedApplications: bundle identifiers whose windows come first,
    ///   whatever their recency. Everything inside the pinned group is still ordered by
    ///   the tiers above, so pinning changes *where* a window sits rather than replacing
    ///   the ordering with something arbitrary.
    func ordered(
        _ entries: [WindowEntry],
        historyDepth: Int,
        pinnedApplications: Set<String> = []
    ) -> [WindowEntry] {
        guard !entries.isEmpty else { return [] }

        let ranked = entries.map { entry -> (entry: WindowEntry, stamp: TimeInterval, pinned: Bool) in
            let pinned = entry.bundleIdentifier.map(pinnedApplications.contains) ?? false
            if let stamp = timestamps[entry.windowID] {
                return (entry, stamp, pinned)
            }
            if let seen = entry.lastSeenOnActiveSpace {
                return (entry, Self.seenBase + seen, pinned)
            }
            return (entry, Self.unseenBase - Double(entry.zOrder), pinned)
        }

        var sorted = ranked
            .sorted { lhs, rhs in
                // Pinning is a coarser key than recency, so a pinned window that has not
                // been touched in an hour still beats an unpinned one from a minute ago.
                // That is the point of pinning it.
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                if lhs.stamp != rhs.stamp { return lhs.stamp > rhs.stamp }
                // Front-to-back, and this tiebreak carries far more weight than it looks.
                //
                // Every window on the active Space is stamped with the *same* seen time — one
                // `seenAt` for the whole enumeration — so the entire active-Space set ties here and
                // this comparison alone decides its order. Breaking it by window id ordered them by
                // creation, which is arbitrary: an app used moments ago could sit ninth simply for
                // having been opened late. Z-order is the front-to-back stack, which Requirement 2.6
                // already names as a good recency proxy, so a window that was recently in front
                // ranks accordingly even with nothing observed about it.
                if lhs.entry.zOrder != rhs.entry.zOrder {
                    return lhs.entry.zOrder < rhs.entry.zOrder
                }
                // Deterministic last resort, so the arrangement cannot reshuffle between
                // presentations.
                return lhs.entry.windowID < rhs.entry.windowID
            }
            .map(\.entry)

        // Requirement 2.4: frontmost window occupies the leftmost slot.
        //
        // Deliberately applied *after* pinning, so slot zero stays the window the user is
        // currently in. That is what keeps the switcher's core gesture intact — the initial
        // selection is the second card, so hold-and-release still means "the other window"
        // — and it makes pinned windows the first thing you can actually switch *to* rather
        // than burying the current window somewhere in the middle of the strip.
        if let frontIndex = sorted.enumerated().min(by: { $0.element.zOrder < $1.element.zOrder })?.offset,
           frontIndex != 0 {
            let front = sorted.remove(at: frontIndex)
            sorted.insert(front, at: 0)
        }

        guard sorted.count > historyDepth else { return sorted }
        return Array(sorted.prefix(historyDepth))
    }

    // MARK: - Live observation

    func startObserving() {
        let center = NSWorkspace.shared.notificationCenter

        let activation = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.handleApplicationActivated(app)
        }

        let termination = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.handleApplicationTerminated(app)
        }

        workspaceObservers = [activation, termination]

        if let front = NSWorkspace.shared.frontmostApplication {
            handleApplicationActivated(front)
        }
    }

    func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        detachAXObserver()
    }

    private func handleApplicationActivated(_ app: NSRunningApplication) {
        stampFocusedWindow(of: app)
        attachAXObserver(to: app)
    }

    private func handleApplicationTerminated(_ app: NSRunningApplication) {
        if observedPID == app.processIdentifier {
            detachAXObserver()
        }
    }

    /// Stamp whichever window is focused in `app` right now.
    private func stampFocusedWindow(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXBridge.applyMessagingTimeout(element)

        if let focused = AXBridge.element(element, kAXFocusedWindowAttribute as String),
           let windowID = AXBridge.windowID(for: focused) {
            recordActivation(windowID: windowID)
            return
        }

        // Accessibility does not always answer for a window that plainly exists — some
        // applications report no focused window, and the attribute can be refused outright.
        // Silently recording nothing was the expensive outcome: an app the user genuinely just
        // switched to kept no activation of its own and fell back to being ordered among the
        // windows nobody has touched. The window server's own front-to-back list needs no
        // permission and cannot decline.
        if let windowID = Self.frontmostWindowID(ofProcess: pid) {
            recordActivation(windowID: windowID)
        }
    }

    /// The frontmost normal window belonging to `pid`, according to the window server.
    private static func frontmostWindowID(ofProcess pid: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // The list arrives front to back, so the first match is the one in front.
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  // Layer zero excludes panels, menus and other chrome, which are not windows a
                  // user thinks of switching to.
                  window[kCGWindowLayer as String] as? Int == 0,
                  let number = window[kCGWindowNumber as String] as? UInt32
            else { continue }
            return CGWindowID(number)
        }
        return nil
    }

    private func attachAXObserver(to app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != observedPID else { return }
        detachAXObserver()

        // Requires Accessibility. Without it observer creation fails and MRU falls
        // back to z-order seeding, which still yields a sensible order
        // (Requirement 10.10 degradation).
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<MRUTracker>.fromOpaque(refcon).takeUnretainedValue()

            if let windowID = AXBridge.windowID(for: element) {
                tracker.recordActivation(windowID: windowID)
                return
            }
            // The notification fired for an element that will not name a window — an application
            // element rather than a window one, typically. The window server still knows which of
            // that process's windows is in front, and losing the stamp entirely is worse.
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success,
                  let windowID = MRUTracker.frontmostWindowID(ofProcess: pid)
            else { return }
            tracker.recordActivation(windowID: windowID)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            Log.registry.debug("AXObserverCreate failed for pid \(pid); MRU falls back to z-order")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXBridge.applyMessagingTimeout(appElement)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        for notification in [
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXApplicationActivatedNotification,
        ] {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        axObserver = observer
        observedPID = pid
        observedAppElement = appElement
    }

    private func detachAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(axObserver),
                .defaultMode
            )
        }
        axObserver = nil
        observedPID = nil
        observedAppElement = nil
    }
}
