import CoreGraphics
import Testing
@testable import VortexflowCore

@Suite("Overlay presence")
struct OverlayPresenceTests {

    private static let visibleFrame = CGRect(x: 100, y: 100, width: 800, height: 400)

    @Test("a revealed panel with a real frame is on screen")
    func revealedPanelIsOnScreen() {
        #expect(
            OverlayPresence.isOnScreen(
                stateVisible: true,
                panelVisible: true,
                frame: Self.visibleFrame,
                isRevealed: true
            )
        )
    }

    @Test("a leftover visible flag with a dead panel is not on screen")
    func leftoverFlagIsNotOnScreen() {
        #expect(
            !OverlayPresence.isOnScreen(
                stateVisible: true,
                panelVisible: false,
                frame: Self.visibleFrame,
                isRevealed: true
            )
        )
    }

    @Test("an unrevealed spiral is not on screen")
    func unrevealedCardsAreNotOnScreen() {
        #expect(
            !OverlayPresence.isOnScreen(
                stateVisible: true,
                panelVisible: true,
                frame: Self.visibleFrame,
                isRevealed: false
            )
        )
    }

    @Test("a collapsed panel is not on screen")
    func collapsedPanelIsNotOnScreen() {
        #expect(
            !OverlayPresence.isOnScreen(
                stateVisible: true,
                panelVisible: true,
                frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                isRevealed: true
            )
        )
    }

    @Test("a hidden state is not on screen")
    func hiddenStateIsNotOnScreen() {
        #expect(
            !OverlayPresence.isOnScreen(
                stateVisible: false,
                panelVisible: true,
                frame: Self.visibleFrame,
                isRevealed: true
            )
        )
    }
}

@Suite("Trigger open gate")
struct TriggerOpenGateTests {

    @Test("a mouse press right after dismiss is a duplicate")
    func mouseIsSuppressedAfterDismiss() {
        #expect(
            TriggerOpenGate.shouldIgnoreDuplicate(source: .button, recentlyDismissed: true)
        )
    }

    @Test("a keyboard press is never suppressed after dismiss")
    func keyboardIsNeverSuppressed() {
        #expect(
            !TriggerOpenGate.shouldIgnoreDuplicate(
                source: .keyboardShortcut,
                recentlyDismissed: true
            )
        )
    }

    @Test("neither trigger is suppressed once the window has passed")
    func nothingIsSuppressedAfterTheWindow() {
        #expect(
            !TriggerOpenGate.shouldIgnoreDuplicate(source: .button, recentlyDismissed: false)
        )
        #expect(
            !TriggerOpenGate.shouldIgnoreDuplicate(
                source: .keyboardShortcut,
                recentlyDismissed: false
            )
        )
    }
}
