import AppKit
import ApplicationServices
import CoreGraphics

/// One individual open window (Requirement 1.1, 1.3).
///
/// Deliberately a struct with a value-typed identity (`windowID`) so the strip can
/// diff cheaply, plus an escape hatch to the live `axElement` for activation.
/// `axElement` is not part of equality: the same window keeps its identity across
/// re-enumeration even though AX handn't guaranteed to hand back an identical
/// element reference.
struct WindowEntry: Identifiable {

    /// CGWindowID. Stable for the lifetime of the window and the shared vocabulary
    /// between Accessibility, CGWindowList and ScreenCaptureKit.
    let windowID: CGWindowID
    let processID: pid_t
    let applicationName: String
    let applicationIcon: NSImage?
    /// Stable identity for the owning application, for settings that name applications.
    /// `nil` for the rare process that has no bundle.
    var bundleIdentifier: String?
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    /// Front-to-back position in the system window list at enumeration time.
    /// `0` is frontmost. Used to seed MRU order for windows this session has never
    /// seen activate (Requirement 2.6).
    let zOrder: Int
    let axElement: AXUIElement?

    /// Whether this window is on the desktop the user is looking at right now.
    ///
    /// True only for windows Accessibility returned this time round, which is precisely the
    /// active Space. Used to decide whether geometry can be trusted for on-screen effects: a
    /// window on another Space has a frame in the same coordinate space, but switching to it
    /// changes desktop, so animating anything to that rectangle would be nonsense.
    var isOnActiveSpace: Bool = false

    /// When PeekSwitch last saw this window on the active Space, if ever.
    ///
    /// Distinct from "used": a window can be seen without being switched to. It exists
    /// because Accessibility only reports the active Space, so a window sitting on another
    /// desktop has no focus history from this session and would otherwise be ordered by its
    /// position in the window server's all-Spaces list — which is arbitrary. When you last
    /// had it in front of you is a far better answer than that.
    var lastSeenOnActiveSpace: TimeInterval?

    /// Set when this entry is a browser tab rather than a window.
    ///
    /// A tab is reached through its browser's scripting interface, so it has no
    /// `CGWindowID`, Accessibility element or z-order.
    private(set) var tab: BrowserTab?

    /// Set when search is offering an installed application that has no matching window.
    ///
    /// Its bundle URL is the thing activation opens. Keeping this distinct from both windows
    /// and tabs makes every window-only operation opt in through `isWindow` rather than
    /// accidentally accepting a synthetic entry because it happens not to be a tab.
    private(set) var launchableApplication: LaunchableApplication?

    /// A `CGWindowID` is not unique across tabs, and launchable applications have no window id
    /// at all, so each target kind owns a stable namespace. Application takes precedence in the
    /// impossible malformed case where both optional payloads are supplied, matching activation.
    var id: String {
        if let launchableApplication { return "application:\(launchableApplication.id)" }
        if let tab { return "tab:\(tab.identity)" }
        return "window:\(windowID)"
    }

    var isApplication: Bool { launchableApplication != nil }
    var isTab: Bool { launchableApplication == nil && tab != nil }
    var isWindow: Bool { tab == nil && launchableApplication == nil }

    /// What the card shows on its title line. Some windows genuinely have no
    /// title (utility panels, freshly opened documents).
    var displayTitle: String {
        if let tab {
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? tab.host : title
        }
        if isApplication { return "Open application" }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? applicationName : title
    }

    /// A tab entry for `tab`, borrowing its browser's name and icon.
    static func tabEntry(_ tab: BrowserTab, application: NSRunningApplication?) -> WindowEntry {
        WindowEntry(
            windowID: 0,
            processID: application?.processIdentifier ?? 0,
            applicationName: application?.localizedName ?? tab.browser.scriptingName,
            applicationIcon: application?.icon,
            bundleIdentifier: tab.browser.bundleIdentifier,
            title: tab.title,
            frame: .zero,
            isMinimized: false,
            zOrder: Int.max,
            axElement: nil,
            tab: tab,
            launchableApplication: nil
        )
    }

    /// A selectable result that opens an installed application instead of raising a window.
    static func applicationEntry(_ application: LaunchableApplication) -> WindowEntry {
        WindowEntry(
            windowID: 0,
            processID: 0,
            applicationName: application.name,
            applicationIcon: application.icon,
            bundleIdentifier: application.bundleIdentifier,
            title: "",
            frame: .zero,
            isMinimized: false,
            zOrder: Int.max,
            axElement: nil,
            tab: nil,
            launchableApplication: application
        )
    }
}

extension WindowEntry: Equatable {
    static func == (lhs: WindowEntry, rhs: WindowEntry) -> Bool {
        lhs.windowID == rhs.windowID
            && lhs.title == rhs.title
            && lhs.isMinimized == rhs.isMinimized
            && lhs.frame == rhs.frame
            && lhs.zOrder == rhs.zOrder
            && lhs.tab == rhs.tab
            && lhs.launchableApplication == rhs.launchableApplication
    }
}
