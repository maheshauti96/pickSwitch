import Testing
@testable import PeekSwitchCore

/// Requirement 4.3–4.6 (selection movement and wrap-around) and Requirement 2.5
/// (initial selection).
@Suite("Selection math")
struct SelectionMathTests {

    // MARK: - advance

    @Test("Selection moves forward and backward")
    func advanceMovesInBothDirections() {
        #expect(SelectionMath.advance(current: 0, by: 1, count: 5) == 1)
        #expect(SelectionMath.advance(current: 3, by: -1, count: 5) == 2)
        #expect(SelectionMath.advance(current: 1, by: 3, count: 5) == 4)
    }

    /// Requirement 4.5.
    @Test("Selection wraps past the right end")
    func advanceWrapsRight() {
        #expect(SelectionMath.advance(current: 4, by: 1, count: 5) == 0)
        #expect(SelectionMath.advance(current: 4, by: 2, count: 5) == 1)
    }

    /// Requirement 4.6.
    @Test("Selection wraps past the left end")
    func advanceWrapsLeft() {
        #expect(SelectionMath.advance(current: 0, by: -1, count: 5) == 4)
        #expect(SelectionMath.advance(current: 0, by: -2, count: 5) == 3)
    }

    /// A fast wheel spin can produce a delta far larger than the card count. The
    /// result must still be a valid index, never a negative or out-of-range one.
    @Test("Large deltas still land on a valid index", arguments: [-97, -13, -5, 5, 13, 97])
    func advanceHandlesLargeDeltas(delta: Int) {
        for count in 1...9 {
            for current in 0..<count {
                let result = SelectionMath.advance(current: current, by: delta, count: count)
                #expect(result != nil)
                if let result {
                    #expect(
                        (0..<count).contains(result),
                        "delta \(delta), count \(count), current \(current) produced \(result)"
                    )
                }
            }
        }
    }

    @Test("Advancing from no selection picks an end")
    func advanceFromNoSelection() {
        #expect(SelectionMath.advance(current: nil, by: 1, count: 4) == 0)
        #expect(SelectionMath.advance(current: nil, by: -1, count: 4) == 3)
    }

    @Test("An empty strip has no selection to advance")
    func advanceOnEmptyStrip() {
        #expect(SelectionMath.advance(current: nil, by: 1, count: 0) == nil)
        #expect(SelectionMath.advance(current: 2, by: 1, count: 0) == nil)
    }

    @Test("A single card stays selected in both directions")
    func advanceOnSingleCard() {
        #expect(SelectionMath.advance(current: 0, by: 1, count: 1) == 0)
        #expect(SelectionMath.advance(current: 0, by: -1, count: 1) == 0)
    }

    // MARK: - clamp

    @Test("Clamping keeps the selection valid when windows disappear")
    func clampKeepsSelectionValid() {
        #expect(SelectionMath.clamp(9, count: 4) == 3)
        #expect(SelectionMath.clamp(-2, count: 4) == 0)
        #expect(SelectionMath.clamp(2, count: 4) == 2)
        #expect(SelectionMath.clamp(2, count: 0) == nil)
        #expect(SelectionMath.clamp(nil, count: 4) == nil)
    }

    // MARK: - initial selection

    /// Requirement 2.5: preselect the second card so a quick flick returns to the
    /// previous window instead of doing nothing.
    @Test("Initial selection is the second card")
    func initialSelectionIsSecondCard() {
        #expect(SelectionMath.initialSelection(count: 5) == 1)
        #expect(SelectionMath.initialSelection(count: 2) == 1)
    }

    @Test("Initial selection falls back with one or zero windows")
    func initialSelectionFallsBack() {
        #expect(SelectionMath.initialSelection(count: 1) == 0)
        #expect(SelectionMath.initialSelection(count: 0) == nil)
    }

    // MARK: - scroll accumulation

    /// Requirement 4.2: one notch, one card.
    @Test("Accumulator emits one step per threshold of travel")
    func accumulatorEmitsOneStepPerThreshold() {
        var accumulator = SelectionMath.ScrollAccumulator()
        let threshold = SelectionMath.ScrollAccumulator.stepThreshold

        #expect(accumulator.consume(delta: threshold / 4) == 0)
        #expect(accumulator.consume(delta: threshold / 4) == 0)
        #expect(accumulator.consume(delta: threshold / 2) == 1)
    }

    @Test("A large delta emits proportionally many steps")
    func accumulatorEmitsMultipleSteps() {
        var accumulator = SelectionMath.ScrollAccumulator()
        #expect(accumulator.consume(delta: SelectionMath.ScrollAccumulator.stepThreshold * 3) == 3)
    }

    @Test("Negative deltas step backwards")
    func accumulatorHandlesNegativeDeltas() {
        var accumulator = SelectionMath.ScrollAccumulator()
        let threshold = SelectionMath.ScrollAccumulator.stepThreshold
        #expect(accumulator.consume(delta: -threshold) == -1)
        #expect(accumulator.consume(delta: -threshold * 2) == -2)
    }

    /// Reversing direction should feel immediate rather than first paying back the
    /// residue accumulated in the old direction.
    @Test("Reversing direction discards the accumulated residue")
    func accumulatorDropsResidueOnReversal() {
        var accumulator = SelectionMath.ScrollAccumulator()
        let threshold = SelectionMath.ScrollAccumulator.stepThreshold

        #expect(accumulator.consume(delta: threshold * 0.9) == 0)
        #expect(accumulator.consume(delta: -threshold) == -1)
    }

    @Test("Reset clears the residue")
    func accumulatorResetClearsResidue() {
        var accumulator = SelectionMath.ScrollAccumulator()
        let threshold = SelectionMath.ScrollAccumulator.stepThreshold
        _ = accumulator.consume(delta: threshold * 0.9)
        accumulator.reset()
        #expect(accumulator.consume(delta: threshold * 0.5) == 0)
    }
}
