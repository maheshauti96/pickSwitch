import AppKit
import SwiftUI

/// Version 1 settings: trigger, activation behaviour, window list, permissions
/// (Requirement 12.1).
struct SettingsView: View {

    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var model: SettingsViewModel

    /// Precomputed because Swift cannot parse a `...` operator that begins a
    /// continuation line inside an argument list.
    private static let historyDepthBounds: ClosedRange<Double> = {
        let lower = Double(SettingsStore.historyDepthRange.lowerBound)
        let upper = Double(SettingsStore.historyDepthRange.upperBound)
        return lower...upper
    }()

    var body: some View {
        Form {
            triggerSection
            activationSection
            shortcutSection
            viewModeSection
            layoutSection
            windowListSection
            pinnedSection
            permissionsSection
            privacySection
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 680)
        .onAppear { permissions.beginPolling() }
        .onDisappear {
            permissions.endPolling()
            model.cancelCapture()
            // A live key monitor must not outlive the window that owns it.
            model.cancelShortcutCapture()
        }
    }

    // MARK: - Trigger

    private var triggerSection: some View {
        Section("Trigger button") {
            // Requirement 12.2.
            Picker("Mouse button", selection: $model.triggerButton) {
                ForEach(model.pickerOptions, id: \.self) { button in
                    Text(button.displayName).tag(button)
                }
            }

            captureRow

            if let warning = model.triggerConflictWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            logitechNote
        }
    }

    /// Placed right next to the Detect control, because this is where a Logitech user
    /// discovers that their thumb button cannot be detected at all and needs to know
    /// why before concluding PeekSwitch is broken.
    /// Placed next to Detect because this is where a Logitech user discovers their thumb
    /// button cannot be seen, and needs to know why before concluding PeekSwitch is broken.
    ///
    /// The order of the two routes is deliberate. Remapping to Back or Forward keeps
    /// everything inside the mouse-button path that Detect already handles, and needs no
    /// spare key on the keyboard. The keyboard route is the fallback, not the headline —
    /// it was previously recommended with F13, which no laptop keyboard has.
    private var logitechNote: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Thumb or Gesture button not detected?")
                .font(.system(size: 11, weight: .semibold))
            Text("Logi Options+ takes those buttons inside the mouse firmware, so no application can see them \u{2014} not PeekSwitch, and not Karabiner or BetterTouchTool either. Setting the button to \u{201C}Do Nothing\u{201D} does not help; that still discards the press.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Easiest fix: in Options+, assign the button to Forward (or Back). macOS then reports it as an ordinary mouse button \u{2014} click Detect Button above and press it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Alternative: assign it to a Keyboard shortcut in Options+, record a combination you can actually type such as \u{2318}\u{2325}\u{2303}Space, and pick the same one under Keyboard shortcut below.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The capture flow. A preset list cannot name every button on every mouse — an
    /// MX Master's Gesture button reports a number no list would guess — so the
    /// reliable way to configure it is to let the user press the button they mean.
    @ViewBuilder
    private var captureRow: some View {
        switch model.captureState {
        case .idle:
            HStack {
                Button("Detect Button\u{2026}") { model.beginCapture() }
                    .controlSize(.small)
                Text("Press the button you want to use.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

        case .waiting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Press any mouse button now\u{2026}")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button("Cancel") { model.cancelCapture() }
                    .controlSize(.small)
            }

        case .captured(let button):
            HStack(spacing: 8) {
                Label("Using \(button.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                Spacer()
                Button("Detect Again") { model.beginCapture() }
                    .controlSize(.small)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.beginCapture() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Activation

    private var activationSection: some View {
        Section("When you press it") {
            Picker("Behaviour", selection: $model.activationMode) {
                ForEach(ActivationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.activationMode.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        Section("Keyboard shortcut") {
            Picker("Shortcut", selection: $model.hotKeyShortcut) {
                ForEach(model.shortcutOptions) { shortcut in
                    Text(shortcut.displayName).tag(shortcut)
                }
            }

            recordShortcutRow

            if let caveat = model.hotKeyShortcut.caveat {
                Label(caveat, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.hotKeyHasFired {
                Label("This shortcut is working", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                // macOS reports successful registration even when another app already
                // owns the combination and keeps the keystroke, so "registered" is not
                // evidence it works. Say so rather than let the user assume a bug.
                Text("Not seen yet. If pressing it does nothing, another app has almost certainly claimed it \u{2014} record a different one. Adding all three of Control, Option and Command makes a clash very unlikely.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Press-to-record, matching the mouse button's Detect flow.
    ///
    /// A preset list cannot cover every keyboard or every set of already-taken combinations,
    /// and the previous advice — record F13 in your mouse software, then pick F13 here — was
    /// unusable on a laptop, which has no F13 to press.
    @ViewBuilder
    private var recordShortcutRow: some View {
        switch model.shortcutCaptureState {
        case .idle:
            HStack {
                Button("Record Shortcut\u{2026}") { model.beginShortcutCapture() }
                    .controlSize(.small)
                Text("Press the combination you want to use.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

        case .recording:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Press the keys now\u{2026}")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button("Cancel") { model.cancelShortcutCapture() }
                    .controlSize(.small)
            }

        case .captured(let shortcut):
            HStack(spacing: 8) {
                Label("Using \(shortcut.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                Spacer()
                Button("Record Again") { model.beginShortcutCapture() }
                    .controlSize(.small)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Try Again") { model.beginShortcutCapture() }
                        .controlSize(.small)
                    Button("Cancel") { model.clearShortcutFeedback() }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Layout

    /// What each item shows, as opposed to how items are arranged.
    ///
    /// A section of its own rather than more options in the arrangement picker, because the two
    /// are independent: either view mode works in any of the four arrangements.
    private var viewModeSection: some View {
        Section("What each window shows") {
            Picker("View", selection: $model.overlayViewMode) {
                ForEach(OverlayViewMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.overlayViewMode.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.overlayViewMode == .icon, !permissions.status(.screenRecording).isGranted {
                Label(
                    "Icon View needs no Screen Recording, so it works fully as configured.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var layoutSection: some View {
        Section("Overlay layout") {
            Picker("Arrangement", selection: $model.overlayLayoutStyle) {
                ForEach(OverlayLayoutStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.overlayLayoutStyle.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Include the switcher in screenshots", isOn: $model.includeOverlayInScreenshots)

            Text(
                model.includeOverlayInScreenshots
                    ? "The switcher appears in screenshots, screen recordings and screen shares, like anything else on screen."
                    : "The switcher is hidden from screenshots, recordings and screen shares. Useful while presenting, since the switcher lists the title of every window you have open."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Window list

    /// Applications whose windows should always be offered first.
    ///
    /// A checklist of what is running rather than a file picker: the applications worth
    /// pinning are the ones you are already using, and picking them by icon is faster than
    /// finding them on disk.
    private var pinnedSection: some View {
        Section("Always show first") {
            Text(model.pinnedSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.applicationChoices) { choice in
                        Toggle(isOn: Binding(
                            get: { model.isPinned(choice.bundleIdentifier) },
                            set: { model.setPinned($0, for: choice.bundleIdentifier) }
                        )) {
                            HStack(spacing: 7) {
                                if let icon = choice.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "app.dashed")
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(.secondary)
                                }
                                Text(choice.name)
                                    .font(.system(size: 12))
                                if !choice.isRunning {
                                    Text("not running")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 150)

            Button("Refresh List") { model.refreshApplicationChoices() }
                .controlSize(.small)
        }
    }

    private var windowListSection: some View {
        Section("Window list") {
            // Requirement 12.4, 12.5.
            VStack(alignment: .leading, spacing: 5) {
                Slider(
                    value: $model.historyDepth,
                    in: Self.historyDepthBounds,
                    step: 1
                ) {
                    Text("Windows to show")
                } minimumValueLabel: {
                    Text("\(SettingsStore.historyDepthRange.lowerBound)")
                        .font(.system(size: 10))
                } maximumValueLabel: {
                    Text("\(SettingsStore.historyDepthRange.upperBound)")
                        .font(.system(size: 10))
                }

                Text(model.historyDepthDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Requirement 12.6.
    private var permissionsSection: some View {
        Section("Permissions") {
            ForEach(Authorization.allCases) { authorization in
                let status = permissions.status(authorization)
                LabeledContent(authorization.title) {
                    HStack(spacing: 8) {
                        Text(status.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(status.isGranted ? Color.green : Color.orange)
                        if !status.isGranted {
                            Button("Open\u{2026}") {
                                permissions.openSettings(for: authorization)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        Section {
            // Requirement 16.1, 16.2 stated where a user will actually see it.
            Text("PeekSwitch runs entirely on this Mac. It makes no network connections and collects nothing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
