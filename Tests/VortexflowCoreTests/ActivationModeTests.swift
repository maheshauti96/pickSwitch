import Foundation
import Testing
@testable import VortexflowCore

/// The tap-versus-hold decision. This is the behaviour a real user hit first — the
/// strip vanishing the instant they released the button — so the rule that decides it
/// is worth pinning down precisely.
@Suite("Activation mode")
struct ActivationModeTests {

    private let threshold = ActivationMode.tapThreshold

    // MARK: - Hold

    @Test("Hold mode always commits on release, however brief")
    func holdAlwaysCommits() {
        for duration in [0.0, 0.01, 0.1, threshold, 1.0, 10.0] {
            #expect(ActivationMode.hold.commitsOnRelease(heldFor: duration))
        }
    }

    // MARK: - Toggle

    @Test("Toggle mode never commits on release, however long")
    func toggleNeverCommits() {
        for duration in [0.0, 0.01, 0.1, threshold, 1.0, 10.0] {
            #expect(!ActivationMode.toggle.commitsOnRelease(heldFor: duration))
        }
    }

    // MARK: - Automatic

    /// A quick tap means "show me what's open", so the strip must stay.
    @Test("A tap does not commit in automatic mode")
    func automaticTapKeepsStripOpen() {
        #expect(!ActivationMode.automatic.commitsOnRelease(heldFor: 0))
        #expect(!ActivationMode.automatic.commitsOnRelease(heldFor: 0.05))
        #expect(!ActivationMode.automatic.commitsOnRelease(heldFor: threshold - 0.001))
    }

    /// A deliberate hold means "I'm steering", so releasing switches.
    @Test("A hold commits in automatic mode")
    func automaticHoldCommits() {
        #expect(ActivationMode.automatic.commitsOnRelease(heldFor: threshold))
        #expect(ActivationMode.automatic.commitsOnRelease(heldFor: threshold + 0.001))
        #expect(ActivationMode.automatic.commitsOnRelease(heldFor: 2.0))
    }

    /// The boundary is inclusive on the hold side, so exactly-at-threshold is a hold.
    @Test("The threshold itself counts as a hold")
    func thresholdIsAHold() {
        #expect(ActivationMode.automatic.commitsOnRelease(heldFor: threshold))
    }

    /// Chosen so an ordinary click (80-150 ms) is unambiguously a tap and never
    /// accidentally switches windows.
    @Test("The threshold sits clear of a normal click")
    func thresholdIsClearOfANormalClick() {
        #expect(threshold > 0.15)
        #expect(threshold < 0.5)
    }

    // MARK: - Metadata

    @Test("Every mode is presentable and distinct")
    func everyModeIsPresentable() {
        var names: Set<String> = []
        for mode in ActivationMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.shortName.isEmpty)
            #expect(!mode.explanation.isEmpty)
            names.insert(mode.shortName)
        }
        #expect(names.count == ActivationMode.allCases.count)
    }

    @Test("Raw values are stable for persistence")
    func rawValuesStable() {
        #expect(ActivationMode.automatic.rawValue == 0)
        #expect(ActivationMode.hold.rawValue == 1)
        #expect(ActivationMode.toggle.rawValue == 2)
    }
}
