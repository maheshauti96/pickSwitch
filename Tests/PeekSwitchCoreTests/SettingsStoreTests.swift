import Foundation
import Testing
@testable import PeekSwitchCore

/// Requirement 12.4, 12.7, 12.8 and Requirement 16.3.
///
/// A `final class` suite rather than a struct so `deinit` can tear the scratch
/// defaults suite down. swift-testing creates one instance per test, so each test
/// gets a clean, isolated user-defaults domain and the real one is never touched.
@Suite("Settings store")
final class SettingsStoreTests {

    private let suiteName: String
    private let defaults: UserDefaults
    private let store: SettingsStore

    init() {
        suiteName = "dev.peekswitch.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Defaults

    /// Requirement 12.8.
    @Test("A fresh install uses the documented defaults")
    func freshInstallDefaults() {
        #expect(store.triggerButton == .middle)
        #expect(store.historyDepth == 10)
        #expect(store.hasCompletedOnboarding == false)
        // Tap-to-keep-open by default: a switcher that vanishes on release is
        // unusable until you already know what you are aiming at.
        #expect(store.activationMode == .automatic)
        #expect(store.hotKeyShortcut == .default)
        // The strip stays the default arrangement: it fits any display and is the
        // cheapest to read at a glance.
        #expect(store.overlayLayoutStyle == .strip)
        // Window View stays the default so an upgrade does not change what people see.
        #expect(store.overlayViewMode == .window)
    }

    /// Bad persisted values must fall back rather than crash or disable the app.
    @Test("Unrecognised persisted values fall back to defaults")
    func corruptValuesFallBack() {
        defaults.set(999, forKey: SettingsStore.Key.activationMode)
        #expect(store.activationMode == SettingsStore.defaultActivationMode)

        defaults.set(-1, forKey: SettingsStore.Key.hotKeyShortcut)
        #expect(store.hotKeyShortcut == .default)

        defaults.set(1, forKey: SettingsStore.Key.triggerButton)
        #expect(store.triggerButton == SettingsStore.defaultTriggerButton)

        defaults.set(42, forKey: SettingsStore.Key.overlayLayoutStyle)
        #expect(store.overlayLayoutStyle == SettingsStore.defaultOverlayLayoutStyle)

        defaults.set(7, forKey: SettingsStore.Key.overlayViewMode)
        #expect(store.overlayViewMode == SettingsStore.defaultOverlayViewMode)
    }

    @Test("Pinned applications round-trip and start empty")
    func pinnedApplicationsRoundTrip() {
        #expect(store.pinnedApplications.isEmpty)

        store.pinnedApplications = ["com.slack", "com.apple.Safari"]
        #expect(SettingsStore(defaults: defaults).pinnedApplications == ["com.slack", "com.apple.Safari"])

        // Unpinning everything must leave nothing behind.
        store.pinnedApplications = []
        #expect(SettingsStore(defaults: defaults).pinnedApplications.isEmpty)
    }

    /// Stored sorted, so the persisted value does not churn every time the set is written.
    @Test("Pinned applications persist in a stable order")
    func pinnedApplicationsPersistStably() {
        store.pinnedApplications = ["com.zeta", "com.alpha", "com.middle"]
        #expect(defaults.stringArray(forKey: SettingsStore.Key.pinnedApplications)
            == ["com.alpha", "com.middle", "com.zeta"])
    }

    @Test("Every overlay layout style round-trips")
    func overlayLayoutStyleRoundTrips() {
        for style in OverlayLayoutStyle.allCases {
            store.overlayLayoutStyle = style
            #expect(SettingsStore(defaults: defaults).overlayLayoutStyle == style)
        }
    }

    @Test("Every overlay view mode round-trips")
    func overlayViewModeRoundTrips() {
        for mode in OverlayViewMode.allCases {
            store.overlayViewMode = mode
            #expect(SettingsStore(defaults: defaults).overlayViewMode == mode)
        }
    }

    /// The two are separate axes, so setting one must not disturb the other. If they ever
    /// shared a key, this is the test that would notice.
    @Test("The view mode and the layout style persist independently")
    func viewModeAndLayoutStyleAreIndependent() {
        store.overlayLayoutStyle = .circular
        store.overlayViewMode = .icon
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.overlayLayoutStyle == .circular)
        #expect(reloaded.overlayViewMode == .icon)

        store.overlayViewMode = .window
        #expect(SettingsStore(defaults: defaults).overlayLayoutStyle == .circular)
    }

    // MARK: - Persistence

    /// Requirement 12.7.
    @Test("Values survive a new store over the same defaults")
    func valuesPersist() {
        store.triggerButton = .thumbForward
        store.historyDepth = 18
        store.hasCompletedOnboarding = true

        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.triggerButton == .thumbForward)
        #expect(reopened.historyDepth == 18)
        #expect(reopened.hasCompletedOnboarding)
    }

    @Test("Every preset trigger button round-trips")
    func everyTriggerButtonRoundTrips() {
        for button in TriggerButton.presets {
            store.triggerButton = button
            #expect(SettingsStore(defaults: defaults).triggerButton == button)
        }
    }

    /// A button assigned by the capture flow will often not be a preset, so storage
    /// has to handle arbitrary numbers.
    @Test("A captured non-preset button round-trips")
    func capturedButtonRoundTrips() {
        guard let exotic = TriggerButton(number: 13) else {
            Issue.record("button 13 should be usable")
            return
        }
        store.triggerButton = exotic
        #expect(SettingsStore(defaults: defaults).triggerButton == exotic)
    }

    @Test("Activation mode round-trips")
    func activationModeRoundTrips() {
        for mode in ActivationMode.allCases {
            store.activationMode = mode
            #expect(SettingsStore(defaults: defaults).activationMode == mode)
        }
    }

    @Test("Hot key shortcut round-trips")
    func hotKeyShortcutRoundTrips() {
        for shortcut in HotKeyShortcut.presets {
            store.hotKeyShortcut = shortcut
            #expect(SettingsStore(defaults: defaults).hotKeyShortcut == shortcut)
        }
    }

    // MARK: - Clamping

    /// Requirement 12.4. A hand-edited plist must not be able to produce an empty
    /// strip or an absurdly long one.
    @Test("History depth is clamped when written")
    func historyDepthClampedOnWrite() {
        store.historyDepth = 1
        #expect(store.historyDepth == SettingsStore.historyDepthRange.lowerBound)

        store.historyDepth = 500
        #expect(store.historyDepth == SettingsStore.historyDepthRange.upperBound)

        store.historyDepth = -20
        #expect(store.historyDepth == SettingsStore.historyDepthRange.lowerBound)
    }

    @Test("History depth is clamped when read")
    func historyDepthClampedOnRead() {
        // Bypass the setter to simulate an externally written value.
        defaults.set(9999, forKey: SettingsStore.Key.historyDepth)
        #expect(store.historyDepth == SettingsStore.historyDepthRange.upperBound)
    }

    @Test("An in-range history depth is preserved exactly")
    func inRangeHistoryDepthPreserved() {
        for depth in SettingsStore.historyDepthRange {
            store.historyDepth = depth
            #expect(store.historyDepth == depth)
        }
    }

    /// An unrecognised raw value must fall back rather than crash or yield nil.
    @Test("An unknown trigger button raw value falls back to the default")
    func unknownTriggerButtonFallsBack() {
        defaults.set(99, forKey: SettingsStore.Key.triggerButton)
        #expect(store.triggerButton == SettingsStore.defaultTriggerButton)
    }

    // MARK: - Privacy

    /// Requirement 16.3: preferences only, no window titles, no history, no usage data.
    @Test("The store writes only its own keys")
    func storeWritesOnlyItsOwnKeys() {
        store.triggerButton = .thumbBack
        store.historyDepth = 12
        store.hasCompletedOnboarding = true
        store.activationMode = .toggle
        store.hotKeyShortcut = .f13
        store.overlayLayoutStyle = .grid
        store.overlayViewMode = .icon
        store.pinnedApplications = ["com.slack"]

        let ownKeys: Set<String> = [
            SettingsStore.Key.triggerButton,
            SettingsStore.Key.historyDepth,
            SettingsStore.Key.hasCompletedOnboarding,
            SettingsStore.Key.activationMode,
            SettingsStore.Key.hotKeyShortcut,
            SettingsStore.Key.overlayLayoutStyle,
            SettingsStore.Key.overlayViewMode,
            SettingsStore.Key.pinnedApplications,
        ]
        let all = Set(defaults.dictionaryRepresentation().keys)
        #expect(all.intersection(ownKeys) == ownKeys)

        // Nothing beyond the declared preference keys. `UserDefaults` exposes inherited
        // system domains too, so compare against keys this suite could have written.
        let unexpected = all.subtracting(ownKeys).filter { $0.hasPrefix("peekSwitch") || $0.hasPrefix("dev.peekswitch") }
        #expect(unexpected.isEmpty, "unexpected keys written: \(unexpected)")
    }
}
