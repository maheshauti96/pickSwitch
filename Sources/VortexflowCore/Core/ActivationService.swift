import AppKit
import ApplicationServices
import Foundation

/// Brings the chosen window to the front (Requirement 7).
///
/// Order matters and is not arbitrary:
///
/// 1. **Unhide the app** (7.5). A hidden app's windows cannot be raised.
/// 2. **Unminimize the window** (7.4). Minimized windows are in the Dock, not in
///    the app's window list on screen; raising one before restoring it is a no-op.
/// 3. **Raise the window** within its app (7.2). This is the step that makes the
///    switcher window-level rather than app-level.
/// 4. **Activate the app** (7.3), which moves keyboard focus to the app and, since
///    the raise already happened, to the intended window.
///
/// Doing 4 before 3 produces a visible flicker: the app's previously frontmost
/// window appears, then the target window replaces it.
@MainActor
final class ActivationService {

    enum Failure: Error {
        case windowGone
        case applicationGone
        /// The window exposes no close button, or pressing it was refused.
        case notClosable
    }

    private let registry: WindowRegistry
    private let tabs: BrowserTabService

    /// Called on the main actor when Launch Services rejects an indexed application.
    var onApplicationLaunchFailure: ((LaunchableApplication, Error) -> Void)?

    init(registry: WindowRegistry, tabs: BrowserTabService) {
        self.registry = registry
        self.tabs = tabs
    }

    /// - Returns: `true` when the target window was raised, `false` when only
    ///   app-level activation was possible (the Requirement 10.10 degraded path).
    @discardableResult
    func activate(_ entry: WindowEntry, canUseAccessibility: Bool) throws -> Bool {
        let stopwatch = Stopwatch("activation", logger: Log.activation)
        defer { stopwatch.log() }

        // An installed-application result is opened by bundle URL. It may not be running yet,
        // which is precisely why resolving it through `NSRunningApplication` would be wrong.
        if let application = entry.launchableApplication {
            guard FileManager.default.fileExists(atPath: application.bundleURL.path) else {
                throw Failure.applicationGone
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let launchFailure = onApplicationLaunchFailure
            NSWorkspace.shared.openApplication(
                at: application.bundleURL,
                configuration: configuration
            ) { _, error in
                guard let error else { return }
                Log.activation.error(
                    "could not open \(application.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                Task { @MainActor in
                    launchFailure?(application, error)
                }
            }
            return true
        }

        // A tab is switched to through its browser, not by raising a window: the tab the
        // user picked may not be the one the browser is currently showing, so selecting it
        // has to happen before — and as part of — bringing the browser forward.
        if let tab = entry.tab {
            if tab.usesNativeWindowIdentifier {
                let windowElement = entry.axElement
                    ?? registry.axElement(for: CGWindowID(tab.windowIdentifier))
                // Scripting is what actually switches Spaces. The strip's CGWindowID
                // is not a Chrome window id, and raising via Accessibility while the
                // browser is in the background leaves the current desktop in front.
                if let scripted = tab.scriptedActivation {
                    let processID = entry.processID
                    let windowID = CGWindowID(tab.windowIdentifier)
                    let tabIndex = tab.tabIndex
                    let tabs = self.tabs
                    Task {
                        let raised = await tabs.activate(scripted)
                        if !raised {
                            await MainActor.run {
                                _ = BrowserTabAlertService.selectTab(
                                    processID: processID,
                                    windowID: windowID,
                                    tabIndex: tabIndex,
                                    windowElement: windowElement
                                )
                            }
                        }
                    }
                    return true
                }
                return BrowserTabAlertService.selectTab(
                    processID: entry.processID,
                    windowID: CGWindowID(tab.windowIdentifier),
                    tabIndex: tab.tabIndex,
                    windowElement: windowElement
                )
            }
            let tabs = self.tabs
            Task { await tabs.activate(tab) }
            return true
        }

        guard let app = NSRunningApplication(processIdentifier: entry.processID), !app.isTerminated
        else {
            registry.invalidateCache(for: entry.processID)
            throw Failure.applicationGone
        }

        // Requirement 7.5.
        if app.isHidden {
            app.unhide()
        }

        guard canUseAccessibility, let axWindow = entry.axElement else {
            // Requirement 10.10: without Accessibility, the best available action is
            // to bring the owning application forward.
            app.activate()
            return false
        }

        // Requirement 7.7 / 7.8: the window may have closed between enumeration and
        // now. Probe before acting so a dead element does not get a raise.
        guard registry.windowStillExists(entry) else {
            registry.invalidateCache(for: entry.processID)
            throw Failure.windowGone
        }

        // Requirement 7.4.
        if entry.isMinimized || (AXBridge.bool(axWindow, kAXMinimizedAttribute as String) ?? false) {
            AXBridge.setBool(axWindow, kAXMinimizedAttribute as String, false)
        }

        return raiseAndActivate(entry, app: app, axWindow: axWindow)
    }

    /// Put this window in front of everything else, without treating it as a switch.
    ///
    /// Tiling and Move to Display change the window's frame. Without a raise that
    /// happens behind whatever the user is looking at, so the only visible result is
    /// a hole opening in some other application's layout.
    @discardableResult
    func bringForward(_ entry: WindowEntry, canUseAccessibility: Bool) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: entry.processID), !app.isTerminated
        else {
            return false
        }
        if app.isHidden {
            app.unhide()
        }
        guard canUseAccessibility, let axWindow = entry.axElement else {
            app.activate()
            return false
        }
        return raiseAndActivate(entry, app: app, axWindow: axWindow)
    }

    /// Raise the window within its application, then activate the application.
    ///
    /// Raise first: activating first produces a flicker of whichever window the app
    /// already had in front. A rejected `AXRaise` is not a failed switch — plenty of
    /// applications decline it on a window that is already frontmost, or manage their
    /// own ordering, and still come forward from `app.activate()`.
    private func raiseAndActivate(
        _ entry: WindowEntry,
        app: NSRunningApplication,
        axWindow: AXUIElement
    ) -> Bool {
        let raised = AXBridge.perform(axWindow, kAXRaiseAction as String)
        AXBridge.setBool(axWindow, kAXMainAttribute as String, true)
        AXBridge.setBool(axWindow, kAXFocusedAttribute as String, true)
        app.activate()
        if !raised {
            Log.activation.debug("""
                AXRaise declined by \(entry.applicationName, privacy: .public); \
                the application was activated instead
                """)
        }
        return raised
    }

    /// Close a window from the switcher, without switching to it.
    ///
    /// Done by pressing the window's own Accessibility close button rather than by
    /// sending ⌘W. That distinction matters: ⌘W goes to whichever window is focused, so
    /// closing a *background* window that way would close the wrong one. Pressing the
    /// button addresses the exact window and needs no focus change, which is why the
    /// overlay can stay open and keyboard focus can stay where it was.
    ///
    /// Applications may still refuse — a document with unsaved changes typically raises
    /// its own save sheet instead, which is correct behaviour and not an error here.
    func close(_ entry: WindowEntry, canUseAccessibility: Bool) throws {
        // Tabs and installed-app search results are not windows and never receive this
        // affordance, so reaching either target kind here is always a programming error.
        guard entry.isWindow else { throw Failure.notClosable }
        guard canUseAccessibility, let axWindow = entry.axElement else {
            throw Failure.notClosable
        }
        guard registry.windowStillExists(entry) else {
            registry.invalidateCache(for: entry.processID)
            throw Failure.windowGone
        }
        guard let button = AXBridge.element(axWindow, kAXCloseButtonAttribute as String) else {
            throw Failure.notClosable
        }
        guard AXBridge.perform(button, kAXPressAction as String) else {
            throw Failure.notClosable
        }
    }

    /// Whether a close button is worth drawing on this window's card.
    ///
    /// Deliberately only the cheap local checks. Asking Accessibility whether the
    /// window has a close button is an IPC round trip per window, and enumeration is
    /// already spending its whole budget (Requirement 1.2) — paying for it on every
    /// card to decide whether to draw an 18pt glyph is the wrong trade. Windows without
    /// one are rare, and the failure is handled: the press throws `notClosable` and the
    /// card stays put.
    func canAttemptClose(_ entry: WindowEntry, canUseAccessibility: Bool) -> Bool {
        entry.isWindow && canUseAccessibility && entry.axElement != nil
    }
}
