import Foundation

/// The three authorizations VortexFlow needs, and nothing else
/// (Requirement 10, Requirement 16.5).
enum Authorization: String, CaseIterable, Identifiable, Sendable {
    case inputMonitoring
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    /// Shown verbatim in onboarding. Each line states the capability lost without
    /// the grant, because "why does it need this" is the first question a
    /// privacy-conscious user asks of a window switcher.
    var purpose: String {
        switch self {
        case .inputMonitoring:
            return "Lets VortexFlow notice when you hold your extra mouse button. Without it, only the keyboard shortcut opens the switcher."
        case .accessibility:
            return "Lets VortexFlow list individual windows and raise the exact one you pick. Without it, VortexFlow can only bring a whole app forward."
        case .screenRecording:
            return "Lets VortexFlow show a thumbnail of each window. Without it, cards show app icons instead of previews."
        }
    }

    /// Deep link into the matching System Settings privacy pane (Requirement 10.4).
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum AuthorizationStatus: String, Sendable {
    case granted
    case denied
    /// Input Monitoring reports this before the first prompt has been answered.
    case undetermined

    var isGranted: Bool { self == .granted }

    var displayName: String {
        switch self {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .undetermined: return "Not requested yet"
        }
    }
}
