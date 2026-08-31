import AppKit
import SwiftUI

/// Settings as a sidebar of short pages, not one scrolling column of help text.
///
/// Each page is only the controls for one job. Warnings stay when they change what
/// the user should do (middle-click cost, an unfired shortcut). Essays that used to
/// sit under every picker do not — the labels already say what the choice is.
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
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 640, minHeight: 460)
        .frame(width: 680, height: 500)
        .onAppear { permissions.beginPolling() }
        .onDisappear {
            permissions.endPolling()
            model.cancelCapture()
            model.cancelShortcutCapture()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text("VortexFlow")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    sidebarItem(pane)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(width: 168)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarItem(_ pane: SettingsPane) -> some View {
        let isSelected = model.selectedPane == pane
        return Button {
            model.show(pane)
        } label: {
            Label(pane.title, systemImage: pane.symbolName)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Pages

    private var detail: some View {
        Form {
            switch model.selectedPane {
            case .trigger: triggerPage
            case .appearance: appearancePage
            case .windows: windowsPage
            case .permissions: permissionsPage
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Trigger

    @ViewBuilder
    private var triggerPage: some View {
        Section("Mouse") {
            Picker("Button", selection: $model.triggerButton) {
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
        }

        Section("When you press it") {
            Picker("Behaviour", selection: $model.activationMode) {
                ForEach(ActivationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }

        Section("Keyboard") {
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
                Text("Not seen yet. If it does nothing, another app owns it — record a different one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var captureRow: some View {
        switch model.captureState {
        case .idle:
            Button("Detect Button\u{2026}") { model.beginCapture() }
                .controlSize(.small)

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

    @ViewBuilder
    private var recordShortcutRow: some View {
        switch model.shortcutCaptureState {
        case .idle:
            Button("Record Shortcut\u{2026}") { model.beginShortcutCapture() }
                .controlSize(.small)

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

    // MARK: Appearance

    @ViewBuilder
    private var appearancePage: some View {
        Section("Arrangement") {
            Picker("Layout", selection: $model.overlayLayoutStyle) {
                ForEach(OverlayLayoutStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.radioGroup)
        }

        if model.overlayLayoutStyle.canShowThumbnails {
            Section("Each window shows") {
                Picker("View", selection: $model.overlayViewMode) {
                    ForEach(model.overlayLayoutStyle.availableViewModes, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if model.overlayViewMode == .icon, !permissions.status(.screenRecording).isGranted {
                    Label(
                        "Icon View works without Screen Recording.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                }
            }
        }

        Section("Cards") {
            Toggle("Tint cards by app icon", isOn: $model.tintWindowsByIcon)
                .help("Each card takes a hint of colour from its icon. Off automatically when Increase Contrast is on.")

            Toggle("Show in screenshots", isOn: $model.includeOverlayInScreenshots)
                .help("Turn this off while presenting. The switcher lists the title of every open window.")
        }
    }

    // MARK: Windows

    @ViewBuilder
    private var windowsPage: some View {
        Section("How many") {
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

        Section("Always show first") {
            Text(model.pinnedSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

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
            .frame(minHeight: 140)

            Button("Refresh List") { model.refreshApplicationChoices() }
                .controlSize(.small)
        }
    }

    // MARK: Permissions

    @ViewBuilder
    private var permissionsPage: some View {
        Section {
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

        Section {
            Text("VortexFlow runs entirely on this Mac. It makes no network connections and collects nothing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
