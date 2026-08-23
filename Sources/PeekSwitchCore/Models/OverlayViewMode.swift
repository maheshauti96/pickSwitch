import Foundation

/// What each item in the switcher shows.
///
/// Orthogonal to `OverlayLayoutStyle`, which decides how items are *arranged* (a row, a grid, a
/// list, a ring). This decides what one item *is*, and the two compose: any view mode works in
/// any arrangement.
///
/// The raw values are persisted, so they must stay stable.
enum OverlayViewMode: Int, CaseIterable, Codable, Sendable {

    /// A live screenshot of each window, with its details underneath. The original behaviour.
    case window = 0

    /// A large application icon with the window's details above it.
    ///
    /// Worth having as more than a style choice. A screenshot of a text editor looks much like a
    /// screenshot of another text editor, whereas an icon is recognised instantly and at any
    /// size. It is also the only mode that works without Screen Recording, since nothing is
    /// captured — and it does no capture work at all, so it is cheaper.
    case icon = 1

    var displayName: String {
        switch self {
        case .window: return "Window View (live previews)"
        case .icon: return "Icon View (large app icons)"
        }
    }

    var shortName: String {
        switch self {
        case .window: return "Window"
        case .icon: return "Icon"
        }
    }

    var explanation: String {
        switch self {
        case .window:
            return "Each window is shown as a live preview of its contents, with its name and title underneath. Best when you recognise your windows by what is in them."
        case .icon:
            return "Each window is shown as a large application icon, with its name and title above it. Faster to recognise than a screenshot, works without Screen Recording, and captures nothing."
        }
    }

    /// Whether this mode needs window screenshots. Icon View skips capture entirely.
    var usesThumbnails: Bool { self == .window }
}
