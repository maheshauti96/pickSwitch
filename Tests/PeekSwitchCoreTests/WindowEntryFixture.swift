import CoreGraphics
import Foundation
@testable import PeekSwitchCore

/// Builds `WindowEntry` values for tests without touching Accessibility or any
/// running application.
enum Fixture {

    static func entry(
        id: CGWindowID,
        app: String = "TestApp",
        title: String? = nil,
        zOrder: Int = 0,
        minimized: Bool = false,
        pid: pid_t = 1,
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    ) -> WindowEntry {
        WindowEntry(
            windowID: id,
            processID: pid,
            applicationName: app,
            applicationIcon: nil,
            title: title ?? "Window \(id)",
            frame: frame,
            isMinimized: minimized,
            zOrder: zOrder,
            axElement: nil
        )
    }

    /// `count` entries with ids 1...count and z-order matching that sequence.
    static func entries(count: Int, app: String = "TestApp") -> [WindowEntry] {
        (0..<count).map { index in
            entry(id: CGWindowID(index + 1), app: app, zOrder: index)
        }
    }
}

/// Floating-point comparison helper.
///
/// The tests are built with swift-testing rather than XCTest, because
/// XCTest.framework ships only with Xcode and this package is built with the
/// Command Line Tools. swift-testing's `#expect` has no accuracy parameter, so
/// tolerance comparisons go through this.
func isClose(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

@MainActor
extension OverlayState {

    /// The visible results that are somewhere on this machine, excluding the web-search offer that
    /// every non-empty query now appends.
    ///
    /// Most search assertions are about matching — which windows, tabs and applications a query
    /// finds — and the web offer is not a match, it is the fallback that is always available. Naming
    /// the distinction keeps those tests measuring what they were written to measure.
    var localEntries: [WindowEntry] { entries.filter { !$0.isWebSearch } }
}
