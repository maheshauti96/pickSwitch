import Foundation

/// One page of Settings. The window is a sidebar of these rather than one scrolling form,
/// so a person looking for the shortcut does not have to pass the mouse essay to get there.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {

    case trigger
    case appearance
    case windows
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trigger: return "Trigger"
        case .appearance: return "Appearance"
        case .windows: return "Windows"
        case .permissions: return "Permissions"
        }
    }

    var symbolName: String {
        switch self {
        case .trigger: return "computermouse"
        case .appearance: return "rectangle.on.rectangle"
        case .windows: return "macwindow"
        case .permissions: return "checkmark.shield"
        }
    }
}
