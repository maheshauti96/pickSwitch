import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

/// Editable state behind `SettingsView`.
///
/// This is an `ObservableObject` rather than view-local `@State` for two reasons.
/// The practical one: `@State` is a macro in the current SwiftUI, and its macro
/// plugin (`SwiftUIMacros`) ships only with Xcode, not with the Command Line Tools
/// that build this package. The design one: settings are not view-local state
/// anyway — they are written through to `SettingsStore` and read by the trigger
/// monitor, so a model object is the honest home for them.
@MainActor
final class SettingsViewModel: ObservableObject {

    /// Progress of the "press the button you want" capture flow.
    enum CaptureState: Equatable {
        case idle
        case waiting
        case captured(TriggerButton)
        /// Capture could not run, or the press was refused.
        case failed(String)
    }

    @Published var triggerButton: TriggerButton {
        didSet {
            guard triggerButton != oldValue else { return }
            store.triggerButton = triggerButton
            // Requirement 12.3: applies without a restart.
            onSettingsChanged()
        }
    }

    @Published var activationMode: ActivationMode {
        didSet {
            guard activationMode != oldValue else { return }
            store.activationMode = activationMode
            onSettingsChanged()
        }
    }

    @Published var hotKeyShortcut: HotKeyShortcut {
        didSet {
            guard hotKeyShortcut != oldValue else { return }
            store.hotKeyShortcut = hotKeyShortcut
            onSettingsChanged()
        }
    }

    @Published var overlayViewMode: OverlayViewMode {
        didSet {
            guard overlayViewMode != oldValue else { return }
            store.overlayViewMode = overlayViewMode
            onSettingsChanged()
        }
    }

    @Published var includeOverlayInScreenshots: Bool {
        didSet {
            guard includeOverlayInScreenshots != oldValue else { return }
            store.includeOverlayInScreenshots = includeOverlayInScreenshots
            onSettingsChanged()
        }
    }

    @Published var tintWindowsByIcon: Bool {
        didSet {
            guard tintWindowsByIcon != oldValue else { return }
            store.tintWindowsByIcon = tintWindowsByIcon
            onSettingsChanged()
        }
    }

    @Published var overlayLayoutStyle: OverlayLayoutStyle {
        didSet {
            guard overlayLayoutStyle != oldValue else { return }
            store.overlayLayoutStyle = overlayLayoutStyle
            onSettingsChanged()
        }
    }

    /// `Double` because `Slider` binds to a floating-point value; the store clamps
    /// and rounds on the way in.
    @Published var historyDepth: Double {
        didSet {
            let rounded = Int(historyDepth.rounded())
            guard rounded != store.historyDepth else { return }
            store.historyDepth = rounded
        }
    }

    /// Applications whose windows are always offered first, by bundle identifier.
    @Published private(set) var pinnedApplications: Set<String> = []

    /// One row in the pinned-applications list.
    struct ApplicationChoice: Identifiable, Equatable {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage?
        /// False for an application that is pinned but not currently running.
        let isRunning: Bool

        var id: String { bundleIdentifier }

        static func == (lhs: ApplicationChoice, rhs: ApplicationChoice) -> Bool {
            lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.isRunning == rhs.isRunning
        }
    }

    @Published private(set) var applicationChoices: [ApplicationChoice] = []

    @Published private(set) var captureState: CaptureState = .idle

    /// Progress of the "press the shortcut you want" flow.
    enum ShortcutCaptureState: Equatable {
        case idle
        case recording
        case captured(HotKeyShortcut)
        case failed(String)
    }

    @Published private(set) var shortcutCaptureState: ShortcutCaptureState = .idle

    /// Local monitor active only while recording.
    private var shortcutMonitor: Any?

    var isRecordingShortcut: Bool { shortcutCaptureState == .recording }

    /// Start listening for the next key combination.
    ///
    /// A local `NSEvent` monitor rather than the overlay's event tap: recording happens while
    /// the Settings window is focused, which is the one time PeekSwitch has a key window and
    /// can simply read its own key events. It also means recording needs no permissions at
    /// all, unlike the tap.
    func beginShortcutCapture() {
        cancelShortcutCapture()
        shortcutCaptureState = .recording

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecordingShortcut else { return event }
            self.handleRecorded(event)
            // Consumed, so the keystroke does not also reach the Settings UI behind it.
            return nil
        }
    }

    func cancelShortcutCapture() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        shortcutMonitor = nil
        if shortcutCaptureState == .recording {
            shortcutCaptureState = .idle
        }
    }

    func clearShortcutFeedback() {
        cancelShortcutCapture()
        shortcutCaptureState = .idle
    }

    private func handleRecorded(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)

        // Escape with no modifiers is how you back out of recording, not a shortcut to assign.
        if keyCode == UInt32(kVK_Escape), Self.carbonModifiers(from: event.modifierFlags) == 0 {
            stopRecording()
            shortcutCaptureState = .idle
            return
        }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)

        guard let shortcut = HotKeyShortcut.recorded(keyCode: keyCode, carbonModifiers: modifiers) else {
            // Stay in recording mode so the user can simply press a better combination.
            let reason = HotKeyShortcut.rejectionReason(keyCode: keyCode, carbonModifiers: modifiers)
            shortcutCaptureState = .failed(reason ?? "That combination cannot be used.")
            return
        }

        stopRecording()
        // Assign through the published property so it is persisted and applied like any other
        // change to the shortcut.
        hotKeyShortcut = shortcut
        shortcutCaptureState = .captured(shortcut)
    }

    private func stopRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
        shortcutMonitor = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private let store: SettingsStore
    private let onSettingsChanged: () -> Void
    private let captureHandler: (@escaping (TriggerButton?) -> Void) -> Void
    private let cancelCaptureHandler: () -> Void
    private let hotKeyFiredProvider: () -> Bool

    init(
        store: SettingsStore,
        onSettingsChanged: @escaping () -> Void,
        beginCapture: @escaping (@escaping (TriggerButton?) -> Void) -> Void,
        cancelCapture: @escaping () -> Void,
        hotKeyHasFired: @escaping () -> Bool
    ) {
        self.store = store
        self.onSettingsChanged = onSettingsChanged
        self.captureHandler = beginCapture
        self.cancelCaptureHandler = cancelCapture
        self.hotKeyFiredProvider = hotKeyHasFired
        self.triggerButton = store.triggerButton
        self.activationMode = store.activationMode
        self.hotKeyShortcut = store.hotKeyShortcut
        self.overlayViewMode = store.overlayViewMode
        self.includeOverlayInScreenshots = store.includeOverlayInScreenshots
        self.tintWindowsByIcon = store.tintWindowsByIcon
        self.overlayLayoutStyle = store.overlayLayoutStyle
        self.historyDepth = Double(store.historyDepth)
        self.pinnedApplications = store.pinnedApplications
        refreshApplicationChoices()
    }

    // MARK: - Pinned applications

    func isPinned(_ bundleIdentifier: String) -> Bool {
        pinnedApplications.contains(bundleIdentifier)
    }

    func setPinned(_ isPinned: Bool, for bundleIdentifier: String) {
        var updated = pinnedApplications
        if isPinned {
            updated.insert(bundleIdentifier)
        } else {
            updated.remove(bundleIdentifier)
        }
        guard updated != pinnedApplications else { return }

        pinnedApplications = updated
        store.pinnedApplications = updated
        // Requirement 12.3: the next trigger uses the new order, no restart.
        onSettingsChanged()
        refreshApplicationChoices()
    }

    /// Rebuild the list of applications the user can choose from.
    ///
    /// Running applications, plus any that are pinned but not running. Dropping the latter
    /// would make a pinned application vanish from the list the moment it quit, taking the
    /// only way to unpin it with it.
    func refreshApplicationChoices() {
        var choices: [String: ApplicationChoice] = [:]

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isTerminated {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            choices[bundleIdentifier] = ApplicationChoice(
                bundleIdentifier: bundleIdentifier,
                name: app.localizedName ?? bundleIdentifier,
                icon: app.icon,
                isRunning: true
            )
        }

        for bundleIdentifier in pinnedApplications where choices[bundleIdentifier] == nil {
            choices[bundleIdentifier] = ApplicationChoice(
                bundleIdentifier: bundleIdentifier,
                // No running instance to ask for a display name, so the identifier's last
                // component is the most readable thing available.
                name: bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier,
                icon: nil,
                isRunning: false
            )
        }

        // Pinned first, then alphabetically, so a choice stays where the user left it.
        applicationChoices = choices.values.sorted { lhs, rhs in
            let lhsPinned = pinnedApplications.contains(lhs.bundleIdentifier)
            let rhsPinned = pinnedApplications.contains(rhs.bundleIdentifier)
            if lhsPinned != rhsPinned { return lhsPinned }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var pinnedSummary: String {
        pinnedApplications.isEmpty
            ? "No applications pinned. Windows are ordered by how recently you used them."
            : "\(pinnedApplications.count) pinned. Their windows come first, after the window you are currently in."
    }

    var historyDepthDescription: String {
        "Showing \(Int(historyDepth.rounded())) most recently used windows."
    }

    /// Shortcuts offered in the picker: the presets, plus the current one when it was
    /// recorded rather than chosen from the list.
    var shortcutOptions: [HotKeyShortcut] {
        var options = HotKeyShortcut.presets
        if !options.contains(hotKeyShortcut) {
            options.insert(hotKeyShortcut, at: 0)
        }
        return options
    }

    /// Buttons offered in the picker: the presets, plus the current button when it is
    /// something exotic that was assigned by capture.
    var pickerOptions: [TriggerButton] {
        var options = TriggerButton.presets
        if !options.contains(triggerButton) {
            options.append(triggerButton)
        }
        return options
    }

    var triggerConflictWarning: String? { triggerButton.conflictWarning }

    /// Whether the configured shortcut has been seen to fire. Used to warn that a
    /// shortcut which registered fine may still be swallowed by another app.
    var hotKeyHasFired: Bool { hotKeyFiredProvider() }

    // MARK: - Button capture

    func beginCapture() {
        captureState = .waiting
        captureHandler { [weak self] captured in
            guard let self else { return }
            if let captured {
                // Assign directly rather than through `triggerButton`'s setter: the
                // controller has already persisted and applied it.
                self.triggerButton = captured
                self.captureState = .captured(captured)
            } else {
                self.captureState = .failed(
                    "That button can't be used — the left and right buttons are off limits. If nothing was detected at all, check the button isn't set to \"Do Nothing\" in Logi Options+, and see the note below."
                )
            }
        }
    }

    func cancelCapture() {
        cancelCaptureHandler()
        captureState = .idle
    }

    func clearCaptureFeedback() {
        captureState = .idle
    }
}
