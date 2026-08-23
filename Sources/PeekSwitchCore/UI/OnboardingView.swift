import AppKit
import SwiftUI

/// First-launch permission setup (Requirement 10.2–10.7).
struct OnboardingView: View {

    @ObservedObject var permissions: PermissionsManager
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Authorization.allCases) { authorization in
                        AuthorizationRow(
                            authorization: authorization,
                            status: permissions.status(authorization),
                            action: { permissions.requestOrReveal(authorization) },
                            openSettings: { permissions.openSettings(for: authorization) }
                        )
                    }

                    Divider().padding(.vertical, 2)
                    mouseSetup
                }
                .padding(18)
            }

            Divider()
            footer
        }
        .frame(width: 520, height: 620)
        // Requirement 10.5: poll only while this window is on screen.
        .onAppear { permissions.beginPolling() }
        .onDisappear { permissions.endPolling() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Welcome to PeekSwitch")
                .font(.system(size: 19, weight: .semibold))
            Text("Switch windows with your mouse. PeekSwitch needs three macOS permissions to do its job, and nothing else.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    /// Requirement 10.7.
    ///
    /// The advice here is the opposite of what seems obvious, and getting it wrong
    /// costs the user a long time: Logi Options+ intercepts the MX Master's extra
    /// buttons inside its driver, so a thumb or Gesture button set to "Do Nothing"
    /// reaches nothing at all — not PeekSwitch, not any event tap. Mapping it to a
    /// keyboard shortcut is the only route.
    private var mouseSetup: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Logitech MX Master setup", systemImage: "computermouse")
                .font(.system(size: 13, weight: .semibold))

            Text("The wheel click works straight away. For a thumb or Gesture button, open Settings and use \u{201C}Detect Button\u{201D}, then press it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("If it isn\u{2019}t detected")
                .font(.system(size: 11, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                bullet("Make sure the button is not set to \u{201C}Do Nothing\u{201D} in Logi Options+; that discards the press.")
                bullet("Otherwise, assign the button to \u{201C}Keyboard shortcut\u{201D} in Options+.")
                bullet("Record F13. No Mac keyboard uses F13 by default.")
                bullet("In PeekSwitch Settings, set the keyboard shortcut to F13.")
            }

            Text("PeekSwitch watches for mouse buttons ahead of tools like Logi Options+, so most extra buttons are reachable directly. A button that Options+ has remapped inside the mouse firmware never reaches the Mac at all, and the keyboard shortcut route covers that case \u{2014} it behaves exactly like a mouse button, tap to keep the switcher open, hold and release to switch.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
    }

    private var footer: some View {
        HStack {
            if permissions.allGranted {
                Label("All set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("You can start using PeekSwitch now; missing permissions only reduce what it can do.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(permissions.allGranted ? "Done" : "Continue Anyway") {
                onDone()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}

/// One permission, its purpose, its live status and a way to grant it.
private struct AuthorizationRow: View {

    let authorization: Authorization
    let status: AuthorizationStatus
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(authorization.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(status.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusTint.opacity(0.18), in: Capsule())
                        .foregroundStyle(statusTint)
                }

                Text(authorization.purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !status.isGranted {
                    HStack(spacing: 8) {
                        Button("Grant\u{2026}", action: action)
                            .controlSize(.small)
                        Button("Open System Settings", action: openSettings)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var statusIcon: some View {
        Image(systemName: status.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.system(size: 15))
            .foregroundStyle(statusTint)
    }

    private var statusTint: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .undetermined: return .secondary
        }
    }
}
