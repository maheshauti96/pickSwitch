import Foundation
import Testing
@testable import VortexflowCore

@Suite("Settings panes")
struct SettingsPaneTests {

    @Test("Every page has a title and a symbol")
    func pagesAreNamed() {
        #expect(SettingsPane.allCases.count == 4)
        for pane in SettingsPane.allCases {
            #expect(!pane.title.isEmpty)
            #expect(!pane.symbolName.isEmpty)
        }
    }

    @Test("The four pages stay in a stable, findable order")
    func pageOrder() {
        #expect(SettingsPane.allCases.map(\.title) == [
            "Trigger",
            "Appearance",
            "Windows",
            "Permissions",
        ])
    }
}

@Suite("Settings view model")
@MainActor
final class SettingsViewModelTests {

    private let suiteName: String
    private let store: SettingsStore
    private let model: SettingsViewModel

    init() {
        suiteName = "io.vortexflow.tests.\(UUID().uuidString)"
        store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        model = SettingsViewModel(
            store: store,
            onSettingsChanged: {},
            beginCapture: { _ in },
            cancelCapture: {},
            hotKeyHasFired: { false }
        )
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test("A fresh model opens on Trigger")
    func startsOnTrigger() {
        #expect(model.selectedPane == .trigger)
    }

    @Test("Changing page leaves Trigger")
    func showChangesThePage() {
        model.show(.appearance)
        #expect(model.selectedPane == .appearance)
        model.show(.windows)
        #expect(model.selectedPane == .windows)
    }

    @Test("Showing another page cancels an in-flight button capture")
    func showCancelsCapture() {
        model.beginCapture()
        #expect(model.captureState == .waiting)
        model.show(.appearance)
        #expect(model.captureState == .idle)
        #expect(model.selectedPane == .appearance)
    }

    @Test("Showing the current page is a no-op")
    func showSamePageDoesNothing() {
        model.beginCapture()
        model.show(.trigger)
        #expect(model.captureState == .waiting)
    }

    @Test("The window-count line names the number without an essay")
    func historyDepthIsShort() {
        model.historyDepth = 12
        #expect(model.historyDepthDescription.contains("12"))
        #expect(model.historyDepthDescription.count < 80)
    }
}
