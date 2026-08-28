import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import IOKit.hid

/// Reads and monitors the three required authorizations (Requirement 10).
///
/// macOS offers no notification when a TCC grant changes, so live status in the
/// onboarding window comes from polling (Requirement 10.5 allows 2 s). Polling only
/// runs while a window that displays status is actually open — `beginPolling()` /
/// `endPolling()` are reference counted — so the idle CPU budget in Requirement 14.3
/// is unaffected.
@MainActor
final class PermissionsManager: ObservableObject {

    @Published private(set) var statuses: [Authorization: AuthorizationStatus] = [:]

    /// Requirement 5.13 / 6.5 / 10.11 all surface through this.
    @Published private(set) var warnings: Set<Warning> = []

    enum Warning: String, Hashable {
        case missingAuthorization
        case eventTapUnstable
        case hotkeyUnavailable
    }

    private var pollTimer: Timer?
    private var pollSubscribers = 0
    private static let pollInterval: TimeInterval = 1.0

    init() {
        refresh()
    }

    // MARK: - Status

    var allGranted: Bool {
        Authorization.allCases.allSatisfy { statuses[$0]?.isGranted == true }
    }

    func status(_ authorization: Authorization) -> AuthorizationStatus {
        statuses[authorization] ?? .undetermined
    }

    var accessibilityGranted: Bool { status(.accessibility).isGranted }
    var screenRecordingGranted: Bool { status(.screenRecording).isGranted }
    var inputMonitoringGranted: Bool { status(.inputMonitoring).isGranted }

    func refresh() {
        var next: [Authorization: AuthorizationStatus] = [:]
        next[.accessibility] = AXIsProcessTrusted() ? .granted : .denied
        // Preflight rather than request: this must not put up a system prompt as a
        // side effect of reading status.
        next[.screenRecording] = CGPreflightScreenCaptureAccess() ? .granted : .denied
        next[.inputMonitoring] = Self.inputMonitoringStatus()

        if next != statuses {
            statuses = next
        }
        updateAuthorizationWarning()
    }

    private static func inputMonitoringStatus() -> AuthorizationStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undetermined
        }
    }

    // MARK: - Prompting

    /// Ask for Accessibility. The system shows its prompt at most once per app
    /// version; afterwards the user must use System Settings, which is why the
    /// onboarding window always offers the deep link too.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func requestScreenRecording() {
        // Triggers the system prompt when undetermined; a no-op once decided.
        CGRequestScreenCaptureAccess()
    }

    func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Requirement 10.4, 12.6.
    func openSettings(for authorization: Authorization) {
        guard let url = authorization.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Combined "ask, then show them where to go" action used by onboarding.
    func requestOrReveal(_ authorization: Authorization) {
        switch authorization {
        case .accessibility:
            if status(.accessibility).isGranted { return }
            requestAccessibility()
            openSettings(for: .accessibility)
        case .screenRecording:
            if status(.screenRecording).isGranted { return }
            requestScreenRecording()
            openSettings(for: .screenRecording)
        case .inputMonitoring:
            if status(.inputMonitoring).isGranted { return }
            if status(.inputMonitoring) == .undetermined {
                requestInputMonitoring()
            } else {
                openSettings(for: .inputMonitoring)
            }
        }
    }

    // MARK: - Polling

    func beginPolling() {
        pollSubscribers += 1
        guard pollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Keep firing while a menu is tracking or a sheet is up.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        refresh()
    }

    func endPolling() {
        pollSubscribers = max(0, pollSubscribers - 1)
        guard pollSubscribers == 0 else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Warnings

    private func updateAuthorizationWarning() {
        if allGranted {
            warnings.remove(.missingAuthorization)
        } else {
            warnings.insert(.missingAuthorization)
        }
    }

    func setWarning(_ warning: Warning, active: Bool) {
        if active {
            warnings.insert(warning)
        } else {
            warnings.remove(warning)
        }
    }

    /// One-line summary for the menu bar menu (Requirement 11.3).
    var summary: String {
        if allGranted { return "All permissions granted" }
        let missing = Authorization.allCases
            .filter { !status($0).isGranted }
            .map(\.title)
        return "Needs: \(missing.joined(separator: ", "))"
    }
}
