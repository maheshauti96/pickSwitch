import AppKit
import SwiftUI

/// Application wiring (Requirement 11).
///
/// `public` because it is the single symbol the thin executable target reaches for;
/// everything else in `VortexflowCore` stays internal so tests can use
/// `@testable import`.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = SettingsStore()
    private let permissions = PermissionsManager()
    private lazy var controller = SwitcherController(settings: settings, permissions: permissions)
    private lazy var menuBar = MenuBarController(permissions: permissions, settings: settings)

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    public override init() {
        super.init()
    }

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Requirement 11.1. LSUIElement in Info.plist covers the bundled app; this
        // makes `swift run` behave the same way during development.
        NSApp.setActivationPolicy(.accessory)

        permissions.refresh()

        // Log the app's own view of its permissions. This is the authoritative
        // reading: `--probe` runs as a child of whatever terminal launched it, and
        // macOS attributes some checks (Screen Recording in particular) to that
        // parent process, so the probe can report a permission as missing when the
        // real app has it.
        Log.app.info("""
            permissions — input monitoring: \(self.permissions.status(.inputMonitoring).rawValue, privacy: .public), \
            accessibility: \(self.permissions.status(.accessibility).rawValue, privacy: .public), \
            screen recording: \(self.permissions.status(.screenRecording).rawValue, privacy: .public)
            """)

        menuBar.onOpenSettings = { [weak self] in self?.showSettings() }
        menuBar.onOpenOnboarding = { [weak self] in self?.showOnboarding() }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.onViewModeChanged = { [weak self] mode in
            guard let self else { return }
            self.settings.overlayViewMode = mode
            self.controller.applySettingsChange()
            Log.app.info("overlay view mode set to \(mode.shortName, privacy: .public)")
        }
        menuBar.onLayoutStyleChanged = { [weak self] style in
            guard let self else { return }
            self.settings.overlayLayoutStyle = style
            // Requirement 12.3: the next trigger uses the new arrangement, no restart.
            self.controller.applySettingsChange()
            Log.app.info("overlay layout set to \(style.shortName, privacy: .public)")
        }
        _ = menuBar

        controller.start()

        // Requirement 10.2: onboarding appears when anything is missing. It is shown
        // on every launch while permissions are incomplete, not just the first —
        // a user who skipped a grant needs the route back, and the menu bar warning
        // alone is easy to miss.
        if !permissions.allGranted {
            showOnboarding()
        } else {
            settings.hasCompletedOnboarding = true
        }

        Log.app.info("Vortexflow \(MenuBarController.versionString, privacy: .public) started")
    }

    /// Requirement 11.4, 11.5.
    public func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        permissions.endPolling()
        Log.app.info("Vortexflow terminating")
    }

    /// Agent apps have no windows to keep alive, but they must not quit when the
    /// last one closes either.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Windows

    private func showSettings() {
        if let settingsWindow {
            bringToFront(settingsWindow)
            return
        }
        let model = SettingsViewModel(
            store: settings,
            onSettingsChanged: { [weak self] in self?.controller.applySettingsChange() },
            beginCapture: { [weak self] completion in
                self?.controller.beginButtonCapture(completion)
            },
            cancelCapture: { [weak self] in self?.controller.cancelButtonCapture() },
            hotKeyHasFired: { [weak self] in self?.controller.hotKeyHasFired ?? false }
        )
        let view = SettingsView(permissions: permissions, model: model)
        let window = makeWindow(title: "Vortexflow Settings", content: view)
        settingsWindow = window
        bringToFront(window)
    }

    private func showOnboarding() {
        if let onboardingWindow {
            bringToFront(onboardingWindow)
            return
        }
        let view = OnboardingView(permissions: permissions) { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
        }
        let window = makeWindow(title: "Vortexflow Setup", content: view)
        onboardingWindow = window
        bringToFront(window)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        return window
    }

    /// An accessory app is not active by default, so showing a real window needs an
    /// explicit activation or it opens behind everything.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === onboardingWindow { onboardingWindow = nil }
        // Drop back to accessory so closing a window does not leave Vortexflow
        // sitting in the Dock.
        NSApp.setActivationPolicy(.accessory)
    }
}
