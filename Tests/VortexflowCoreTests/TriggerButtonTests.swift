import Testing
@testable import VortexflowCore

/// The trigger button became an arbitrary number rather than a fixed enum, because a
/// closed list could not name the extra buttons real mice actually report.
@Suite("Trigger button")
struct TriggerButtonTests {

    // MARK: - Validation

    /// Consuming the left or right button would break ordinary clicking everywhere,
    /// so they must be impossible to select.
    @Test("Left and right buttons are refused", arguments: [0, 1])
    func refusesPrimaryAndSecondary(number: Int) {
        #expect(TriggerButton(number: number) == nil)
    }

    @Test("Negative and out-of-range numbers are refused", arguments: [-5, -1, 32, 99, 1000])
    func refusesOutOfRange(number: Int) {
        #expect(TriggerButton(number: number) == nil)
    }

    @Test("Every button in range is accepted")
    func acceptsEveryNumberInRange() {
        for number in TriggerButton.minimumNumber...TriggerButton.maximumNumber {
            let button = TriggerButton(number: number)
            #expect(button != nil, "button \(number) should be usable")
            #expect(button?.number == number)
        }
    }

    /// The whole point of the rework: a button number no preset list would have
    /// guessed still has to work.
    @Test("An exotic button number is usable")
    func acceptsExoticButton() {
        let gesture = TriggerButton(number: 16)
        #expect(gesture != nil)
        #expect(gesture?.displayName == "Button 16")
    }

    // MARK: - Storage compatibility

    /// The three original enum cases had raw values 2, 3 and 4. Preferences written by
    /// the previous version must still resolve to the same buttons.
    @Test("Raw values match the original enum so existing preferences survive")
    func rawValuesUnchanged() {
        #expect(TriggerButton.middle.rawValue == 2)
        #expect(TriggerButton.thumbBack.rawValue == 3)
        #expect(TriggerButton.thumbForward.rawValue == 4)
    }

    @Test("Raw value round-trips")
    func rawValueRoundTrips() {
        for number in TriggerButton.minimumNumber...TriggerButton.maximumNumber {
            guard let button = TriggerButton(number: number) else {
                Issue.record("button \(number) unexpectedly rejected")
                continue
            }
            #expect(TriggerButton(rawValue: button.rawValue) == button)
        }
    }

    @Test("Event tap comparison value matches the button number")
    func buttonNumberMatches() {
        #expect(TriggerButton.middle.buttonNumber == 2)
        #expect(TriggerButton.from(buttonNumber: 4) == .thumbForward)
        #expect(TriggerButton.from(buttonNumber: 1) == nil)
    }

    // MARK: - Presentation

    @Test("Presets are the three common buttons")
    func presets() {
        #expect(TriggerButton.presets == [.middle, .thumbBack, .thumbForward])
    }

    @Test("Known buttons get friendly names")
    func friendlyNames() {
        #expect(TriggerButton.middle.displayName.contains("Middle"))
        #expect(TriggerButton.thumbBack.displayName.contains("Thumb"))
        #expect(TriggerButton.thumbForward.displayName.contains("Thumb"))
    }

    /// Claiming the middle button costs the user middle-click in browsers, so that
    /// tradeoff has to be surfaced rather than discovered.
    @Test("Only the middle button carries a conflict warning")
    func conflictWarning() {
        #expect(TriggerButton.middle.hasCommonConflict)
        #expect(TriggerButton.middle.conflictWarning != nil)

        #expect(!TriggerButton.thumbBack.hasCommonConflict)
        #expect(TriggerButton.thumbBack.conflictWarning == nil)
        #expect(TriggerButton.thumbForward.conflictWarning == nil)
    }
}
