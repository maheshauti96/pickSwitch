import AppKit
import Foundation

/// An installed application that can be opened even when it has no switchable window.
///
/// The bundle URL is the launch target and the stable identity. Keeping the application as
/// its own value — rather than pretending it is window zero — prevents window-only work such
/// as capture, closing, MRU tracking and transition geometry from ever seeing it.
struct LaunchableApplication: Identifiable {
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL
    let icon: NSImage?

    var id: String { bundleURL.path }
}

extension LaunchableApplication: Equatable {
    static func == (lhs: LaunchableApplication, rhs: LaunchableApplication) -> Bool {
        lhs.name == rhs.name
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.bundleURL == rhs.bundleURL
    }
}
