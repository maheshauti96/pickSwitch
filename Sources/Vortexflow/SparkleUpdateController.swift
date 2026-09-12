import AppKit
import Sparkle

/// Owns Sparkle's standard updater for the menu-bar agent.
///
/// The app is `LSUIElement`, so Sparkle windows need an explicit activation or
/// they open behind everything. Core never imports Sparkle; the executable
/// forwards "Check for Updates" through a callback.
final class SparkleUpdateController: NSObject, SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
