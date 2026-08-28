import AppKit
import Combine
import SwiftUI

/// The menu bar status item and its menu (Requirement 11).
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let permissions: PermissionsManager
    private let settings: SettingsStore

    private var cancellables: Set<AnyCancellable> = []

    var onOpenSettings: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?
    var onQuit: (() -> Void)?
    /// Called when the user picks a different overlay arrangement from the menu.
    var onLayoutStyleChanged: ((OverlayLayoutStyle) -> Void)?
    /// Called when the user switches between Window View and Icon View.
    var onViewModeChanged: ((OverlayViewMode) -> Void)?

    init(permissions: PermissionsManager, settings: SettingsStore) {
        self.permissions = permissions
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        // Requirement 5.13, 6.5, 10.11 all surface as the same warning affordance.
        permissions.$warnings
            .receive(on: RunLoop.main)
            .sink { [weak self] warnings in
                self?.updateButton(warnings: warnings)
            }
            .store(in: &cancellables)
    }

    private func configureButton() {
        applyAppearance(hasWarning: false, tooltip: "Vortexflow")
        statusItem.menu = buildMenu()
        logVisibility(context: "initial")
    }

    /// Record the rendered width of the status item.
    ///
    /// A zero width means the item exists but is invisible, which for a menu-bar-only
    /// agent is indistinguishable from the app not running — there is no Dock icon or
    /// window to fall back on. This has already bitten once (a missing SF Symbol left
    /// the button with a nil image), so it is worth a line in the log.
    private func logVisibility(context: String) {
        let width = statusItem.button?.frame.width ?? 0
        let hasImage = statusItem.button?.image != nil
        let title = statusItem.button?.title ?? ""

        if width > 0 {
            Log.app.info("""
                status item visible (\(context, privacy: .public)): width \
                \(width, format: .fixed(precision: 1)), image: \(hasImage ? "yes" : "no"), \
                title: "\(title, privacy: .public)"
                """)
        } else {
            Log.app.error("""
                status item has zero width (\(context, privacy: .public)) and will be \
                invisible in the menu bar — image: \(hasImage ? "yes" : "no"), title: "\(title, privacy: .public)"
                """)
        }
    }

    private func updateButton(warnings: Set<PermissionsManager.Warning>) {
        let hasWarning = !warnings.isEmpty
        applyAppearance(
            hasWarning: hasWarning,
            tooltip: hasWarning ? Self.warningSummary(warnings) : "Vortexflow"
        )
        // Rebuild so the permissions line reflects current status.
        statusItem.menu = buildMenu()
        logVisibility(context: hasWarning ? "warning state" : "normal state")
    }

    /// Set the status item's appearance, guaranteeing it stays visible.
    ///
    /// This is the app's only permanent affordance — lose it and there is no way to
    /// reach Settings or Quit, because a menu-bar agent has no Dock icon and no
    /// window. A `variableLength` status item with a nil image and no title collapses
    /// to zero width and vanishes, so a missing symbol must never reach the button
    /// unguarded. It happened: `exclamationmark.rectangle` does not exist on every
    /// macOS version, and the app disappeared from the menu bar the moment a
    /// permission warning was raised.
    private func applyAppearance(hasWarning: Bool, tooltip: String) {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.setAccessibilityLabel(hasWarning ? "Vortexflow, needs attention" : "Vortexflow")

        if let image = Self.icon(hasWarning: hasWarning) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            // Last resort: no symbol resolved, so fall back to text. Ugly beats
            // invisible.
            button.image = nil
            button.imagePosition = .noImage
            button.title = hasWarning ? "Vortexflow !" : "Vortexflow"
        }
    }

    /// SF Symbol availability varies by macOS version, so try candidates in order of
    /// preference and take the first that actually resolves.
    private static func icon(hasWarning: Bool) -> NSImage? {
        let candidates = hasWarning
            ? [
                "exclamationmark.triangle.fill",
                "exclamationmark.triangle",
                "exclamationmark.circle.fill",
                "exclamationmark.circle",
                "exclamationmark",
            ]
            : [
                "rectangle.on.rectangle",
                "macwindow.on.rectangle",
                "square.on.square",
                "macwindow",
            ]
        let description = hasWarning ? "Vortexflow needs attention" : "Vortexflow"

        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: description) {
                return image
            }
        }
        return nil
    }

    private static func warningSummary(_ warnings: Set<PermissionsManager.Warning>) -> String {
        var lines: [String] = []
        if warnings.contains(.missingAuthorization) {
            lines.append("Some permissions are missing")
        }
        if warnings.contains(.eventTapUnstable) {
            lines.append("The mouse trigger keeps getting interrupted by macOS")
        }
        if warnings.contains(.hotkeyUnavailable) {
            lines.append("The keyboard shortcut could not be registered")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Menu

    /// Requirement 11.3.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: permissions.summary, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !permissions.allGranted {
            let fix = NSMenuItem(
                title: "Finish Setup…",
                action: #selector(openOnboarding),
                keyEquivalent: ""
            )
            fix.target = self
            menu.addItem(fix)
        }

        menu.addItem(.separator())

        let trigger = NSMenuItem(
            title: "Trigger: \(settings.triggerButton.shortName)  ·  \(settings.hotKeyShortcut.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        trigger.isEnabled = false
        menu.addItem(trigger)

        let activation = NSMenuItem(
            title: "Activation: \(settings.activationMode.shortName)  ·  \(settings.overlayViewMode.shortName)  ·  \(settings.overlayLayoutStyle.shortName)",
            action: nil,
            keyEquivalent: ""
        )
        activation.isEnabled = false
        menu.addItem(activation)

        // A submenu rather than a Settings-only control: trying the four arrangements
        // against real windows is the only way to tell which one suits, and making
        // that a two-click round trip through a settings window discourages it.
        let viewMode = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMode.submenu = buildViewModeMenu()
        menu.addItem(viewMode)

        let layout = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        layout.submenu = buildLayoutMenu()
        menu.addItem(layout)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let version = NSMenuItem(title: "Vortexflow \(Self.versionString)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        let quit = NSMenuItem(title: "Quit Vortexflow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func buildViewModeMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = settings.overlayViewMode

        for mode in OverlayViewMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectViewMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = true
            item.tag = mode.rawValue
            item.state = mode == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func buildLayoutMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = settings.overlayLayoutStyle

        for style in OverlayLayoutStyle.allCases {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(selectLayoutStyle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = true
            item.tag = style.rawValue
            item.state = style == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return short
    }

    // MARK: - Actions

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func selectViewMode(_ sender: NSMenuItem) {
        guard let mode = OverlayViewMode(rawValue: sender.tag) else { return }
        onViewModeChanged?(mode)
        statusItem.menu = buildMenu()
    }

    @objc private func selectLayoutStyle(_ sender: NSMenuItem) {
        guard let style = OverlayLayoutStyle(rawValue: sender.tag) else { return }
        onLayoutStyleChanged?(style)
        // Rebuild so the checkmark and the summary line reflect the new choice.
        statusItem.menu = buildMenu()
    }

    @objc private func openOnboarding() {
        onOpenOnboarding?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
