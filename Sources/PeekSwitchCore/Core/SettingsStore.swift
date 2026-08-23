import Foundation

/// Persists the two version 1 preferences and nothing else (Requirement 12.7,
/// 16.3).
///
/// `UserDefaults`-backed, injectable so tests can run against a scratch suite
/// instead of the real user domain.
final class SettingsStore {

    enum Key {
        static let triggerButton = "triggerButton"
        static let historyDepth = "historyDepth"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let activationMode = "activationMode"
        static let hotKeyShortcut = "hotKeyShortcut"
        static let logAllHIDInput = "logAllHIDInput"
        static let overlayLayoutStyle = "overlayLayoutStyle"
        static let pinnedApplications = "pinnedApplications"
        static let overlayViewMode = "overlayViewMode"
    }

    /// Applications whose windows are always offered first.
    ///
    /// Stored as bundle identifiers rather than names: a localized name changes with the
    /// system language, and two applications can share one.
    var pinnedApplications: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.pinnedApplications) ?? []) }
        // Sorted so the stored value is stable and diffable rather than reordering itself
        // every time the set is written.
        set { defaults.set(newValue.sorted(), forKey: Key.pinnedApplications) }
    }

    /// Requirement 12.8: defaults applied on a fresh install.
    ///
    /// The default trigger stays the middle button because it is the one button every
    /// mouse has and it needs no Logi Options+ setup. Settings warns about the
    /// browser middle-click cost and points at the thumb buttons.
    static let defaultTriggerButton: TriggerButton = .middle
    static let defaultHistoryDepth = 10
    /// Requirement 12.4.
    static let historyDepthRange = 5...25
    /// Tap-to-keep-open is the default: it is the behaviour people expect from a
    /// switcher they are still learning, and holding still works for speed.
    static let defaultActivationMode: ActivationMode = .automatic
    /// The strip stays the default: it is the cheapest arrangement to read at a
    /// glance, and it is the one that fits on any display without discussion.
    static let defaultOverlayLayoutStyle: OverlayLayoutStyle = .strip
    /// Window View stays the default: it is the shipped behaviour, and changing what existing
    /// users see on upgrade is not something a new option should do on their behalf.
    static let defaultOverlayViewMode: OverlayViewMode = .window

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var triggerButton: TriggerButton {
        get {
            guard defaults.object(forKey: Key.triggerButton) != nil else {
                return Self.defaultTriggerButton
            }
            let raw = defaults.integer(forKey: Key.triggerButton)
            return TriggerButton(rawValue: raw) ?? Self.defaultTriggerButton
        }
        set { defaults.set(newValue.rawValue, forKey: Key.triggerButton) }
    }

    var historyDepth: Int {
        get {
            guard defaults.object(forKey: Key.historyDepth) != nil else {
                return Self.defaultHistoryDepth
            }
            return clampHistoryDepth(defaults.integer(forKey: Key.historyDepth))
        }
        set { defaults.set(clampHistoryDepth(newValue), forKey: Key.historyDepth) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    /// Diagnostic switch with no UI, for working out why a particular mouse button is
    /// not being seen. Read only; set it from the command line:
    ///
    ///     defaults write dev.peekswitch.PeekSwitch logAllHIDInput -bool true
    ///
    /// Deliberately not in Settings: it is verbose, it is for a support conversation
    /// rather than for daily use, and it should not survive as a discoverable toggle.
    var logsAllHIDInput: Bool {
        defaults.bool(forKey: Key.logAllHIDInput)
    }

    var activationMode: ActivationMode {
        get {
            guard defaults.object(forKey: Key.activationMode) != nil else {
                return Self.defaultActivationMode
            }
            return ActivationMode(rawValue: defaults.integer(forKey: Key.activationMode))
                ?? Self.defaultActivationMode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.activationMode) }
    }

    var overlayViewMode: OverlayViewMode {
        get {
            guard defaults.object(forKey: Key.overlayViewMode) != nil else {
                return Self.defaultOverlayViewMode
            }
            return OverlayViewMode(rawValue: defaults.integer(forKey: Key.overlayViewMode))
                ?? Self.defaultOverlayViewMode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.overlayViewMode) }
    }

    var overlayLayoutStyle: OverlayLayoutStyle {
        get {
            guard defaults.object(forKey: Key.overlayLayoutStyle) != nil else {
                return Self.defaultOverlayLayoutStyle
            }
            return OverlayLayoutStyle(rawValue: defaults.integer(forKey: Key.overlayLayoutStyle))
                ?? Self.defaultOverlayLayoutStyle
        }
        set { defaults.set(newValue.rawValue, forKey: Key.overlayLayoutStyle) }
    }

    var hotKeyShortcut: HotKeyShortcut {
        get {
            guard defaults.object(forKey: Key.hotKeyShortcut) != nil else {
                return .default
            }
            return HotKeyShortcut.from(storageValue: defaults.integer(forKey: Key.hotKeyShortcut))
                ?? .default
        }
        set { defaults.set(newValue.storageValue, forKey: Key.hotKeyShortcut) }
    }

    /// Out-of-range values are clamped rather than rejected, so a hand-edited plist
    /// or a future range change can never leave the strip showing zero cards.
    func clampHistoryDepth(_ value: Int) -> Int {
        min(max(value, Self.historyDepthRange.lowerBound), Self.historyDepthRange.upperBound)
    }
}
