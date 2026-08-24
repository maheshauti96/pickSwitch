import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// What happens to the overlay when a window is closed from it.
///
/// Closing is the one action that mutates the list while the overlay is still on screen,
/// so the invariants the rest of the UI relies on — a selection that is in range, counts
/// and badges that match the shorter list, a scroll offset that still shows the
/// selection — all have to survive it.
@Suite("Overlay state")
@MainActor
struct OverlayStateTests {

    private func state(count: Int, selected: Int? = 0) -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.load(
            entries: (0..<count).map { index in
                Fixture.entry(id: CGWindowID(index + 1), app: "App \(index % 2)", zOrder: index)
            },
            selectedIndex: selected
        )
        return state
    }

    // MARK: - Removal

    @Test("Closing a window drops its card")
    func closingDropsTheCard() {
        let subject = state(count: 4, selected: 1)
        #expect(subject.remove(windowID: 2))

        #expect(subject.entries.count == 3)
        #expect(!subject.entries.contains { $0.windowID == 2 })
    }

    @Test("Closing an unknown window changes nothing")
    func closingUnknownWindowChangesNothing() {
        let subject = state(count: 3, selected: 1)
        #expect(subject.remove(windowID: 999) == false)
        #expect(subject.entries.count == 3)
        #expect(subject.selectedIndex == 1)
    }

    /// The selection stays at the same position in the list, so the next card slides
    /// under the cursor and closing several in a row means clicking the same spot.
    @Test("The selection holds its position so the next card slides under the cursor")
    func selectionHoldsItsPosition() {
        let subject = state(count: 5, selected: 2)
        let followingWindowID = subject.entries[3].windowID

        #expect(subject.remove(windowID: subject.entries[2].windowID))

        #expect(subject.selectedIndex == 2)
        #expect(subject.selectedEntry?.windowID == followingWindowID)
    }

    /// Closing the last card has nowhere to move down to, so the selection has to come
    /// back up rather than point past the end.
    @Test("Closing the last card pulls the selection back")
    func closingLastCardPullsSelectionBack() {
        let subject = state(count: 3, selected: 2)
        #expect(subject.remove(windowID: subject.entries[2].windowID))

        #expect(subject.entries.count == 2)
        #expect(subject.selectedIndex == 1)
        #expect(subject.selectedEntry != nil)
    }

    @Test("Closing the only window leaves nothing selected")
    func closingOnlyWindowLeavesNothingSelected() {
        let subject = state(count: 1, selected: 0)
        #expect(subject.remove(windowID: subject.entries[0].windowID))

        #expect(subject.entries.isEmpty)
        #expect(subject.selectedIndex == nil)
        #expect(subject.selectedEntry == nil)
    }

    @Test("A closed window's thumbnail is released")
    func closedWindowThumbnailIsReleased() {
        let subject = state(count: 3, selected: 0)
        guard let image = makeImage() else {
            Issue.record("could not build a test image")
            return
        }
        for entry in subject.entries {
            subject.setThumbnail(image, for: entry.windowID)
        }
        #expect(subject.thumbnails.count == 3)

        #expect(subject.remove(windowID: 2))
        #expect(subject.thumbnails.count == 2)
        #expect(subject.thumbnails[2] == nil)
    }

    /// The multi-window badge counts windows per application, so closing one has to
    /// recount — a stale "2" on the last remaining window would be wrong.
    @Test("Per-application counts are recomputed")
    func perApplicationCountsAreRecomputed() {
        let subject = OverlayState()
        subject.load(
            entries: [
                Fixture.entry(id: 1, app: "Chrome"),
                Fixture.entry(id: 2, app: "Chrome"),
                Fixture.entry(id: 3, app: "Xcode"),
            ],
            selectedIndex: 0
        )
        #expect(subject.badgeCount(for: subject.entries[0]) == 2)

        #expect(subject.remove(windowID: 2))
        // One Chrome window left, so the badge should be gone entirely.
        #expect(subject.badgeCount(for: subject.entries[0]) == nil)
    }

    /// A removal shortens the strip, which can leave the old offset scrolled past the
    /// end and the selection off screen.
    @Test("The scroll offset stays legal after a removal")
    func scrollOffsetStaysLegalAfterRemoval() {
        let subject = OverlayState()
        subject.availableContentWidth = 600
        subject.load(entries: Fixture.entries(count: 20), selectedIndex: 19)
        #expect(subject.scrollOffset > 0)

        for windowID in (11...20).map(CGWindowID.init) {
            #expect(subject.remove(windowID: windowID))
        }

        #expect(subject.scrollOffset >= 0)
        #expect(subject.scrollOffset <= subject.layout.maxScrollOffset + 0.001)
        if let selected = subject.selectedIndex {
            #expect(subject.entries.indices.contains(selected))
        }
    }

    /// Removing every card one at a time must never leave the selection dangling, which
    /// is what would crash a view reading `entries[selectedIndex]`.
    @Test("Emptying the list one card at a time keeps the selection valid")
    func emptyingKeepsSelectionValid() {
        let subject = state(count: 6, selected: 3)

        while let entry = subject.entries.first {
            #expect(subject.remove(windowID: entry.windowID))
            if let selected = subject.selectedIndex {
                #expect(subject.entries.indices.contains(selected))
            } else {
                #expect(subject.entries.isEmpty)
            }
        }
        #expect(subject.selectedIndex == nil)
    }

    // MARK: - Close affordance policy

    /// Without Accessibility there is no way to press a window's close button, so
    /// offering one would promise something that cannot happen.
    @Test("No close affordance without Accessibility")
    func noCloseAffordanceWithoutAccessibility() {
        let subject = state(count: 2)
        subject.canCloseWindows = false
        #expect(subject.entries.allSatisfy { !subject.canClose($0) })
    }

    /// The fixtures carry no AX element, which is the same position a window enumerated
    /// through the CGWindowList-only fallback is in: listable, switchable, not closable.
    @Test("No close affordance for a window with no Accessibility element")
    func noCloseAffordanceWithoutAXElement() {
        let subject = state(count: 2)
        subject.canCloseWindows = true
        #expect(subject.entries.allSatisfy { $0.axElement == nil })
        #expect(subject.entries.allSatisfy { !subject.canClose($0) })
    }

    private func makeImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()
    }
}

/// The cards' entrance, and the two ways it used to fail.
///
/// The symptom was intermittent: sometimes the cards animated in, sometimes they were simply
/// there, and sometimes they appeared and *then* animated. All of it came from the entrance
/// depending on a state transition nothing enforced the ordering of.
@Suite("Overlay entrance")
@MainActor
struct OverlayRevealSequencingTests {

    private func presented(count: Int = 6) -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.load(entries: Fixture.entries(count: count), selectedIndex: 0)
        state.isVisible = true
        return state
    }

    @Test("Beginning a presentation hides the cards and takes a new identity")
    func beginningAPresentationHidesTheCards() {
        let subject = presented()
        let before = subject.presentationID

        subject.beginPresentation()

        #expect(!subject.isRevealed)
        #expect(subject.presentationID != before)
    }

    @Test("Revealing with the current token lets the cards in")
    func revealingWithTheCurrentTokenWorks() {
        let subject = presented()
        subject.beginPresentation()

        #expect(subject.reveal(token: subject.presentationID))
        #expect(subject.isRevealed)
    }

    /// The defect that made the entrance skip entirely. Trigger twice quickly and the first
    /// presentation's deferred reveal used to land on the second, which had just hidden itself —
    /// so the second presentation's cards snapped straight in.
    @Test("A reveal from an earlier presentation cannot fire during a later one")
    func staleRevealIsIgnored() {
        let subject = presented()

        subject.beginPresentation()
        let firstToken = subject.presentationID

        // The first presentation ends and a second begins before its reveal was delivered.
        subject.beginPresentation()

        #expect(!subject.reveal(token: firstToken), "a stale token revealed the new presentation")
        #expect(!subject.isRevealed, "the second presentation lost its entrance")

        // The second presentation's own token still works.
        #expect(subject.reveal(token: subject.presentationID))
        #expect(subject.isRevealed)
    }

    /// A reveal delivered after dismissal must not quietly mark a hidden overlay revealed, or the
    /// next presentation would start from the wrong state.
    @Test("A reveal after dismissal is ignored")
    func revealAfterDismissalIsIgnored() {
        let subject = presented()
        subject.beginPresentation()
        let token = subject.presentationID

        subject.isVisible = false

        #expect(!subject.reveal(token: token))
        #expect(!subject.isRevealed)
    }

    /// Only a new presentation may replay the entrance. Filtering as the user types changes the
    /// card list constantly, and re-running the animation on every keystroke would be unusable.
    @Test("Searching does not start a new presentation")
    func searchingDoesNotReplayTheEntrance() {
        let subject = presented(count: 8)
        subject.beginPresentation()
        subject.reveal(token: subject.presentationID)
        let identity = subject.presentationID

        subject.appendToSearch("app")
        #expect(subject.presentationID == identity)
        #expect(subject.isRevealed)

        subject.backspaceSearch()
        #expect(subject.presentationID == identity)
        #expect(subject.isRevealed)
    }

    /// Closing a window from the overlay is the other mid-presentation mutation, and it must not
    /// restart the entrance either.
    @Test("Closing a window does not replay the entrance")
    func closingDoesNotReplayTheEntrance() {
        let subject = presented(count: 5)
        subject.beginPresentation()
        subject.reveal(token: subject.presentationID)
        let identity = subject.presentationID

        #expect(subject.remove(windowID: 2))
        #expect(subject.presentationID == identity)
        #expect(subject.isRevealed)
    }

    /// Each presentation gets a distinct identity, which is what the view keys the arrangement on
    /// so that a fresh subtree reads the hidden state directly.
    @Test("Every presentation has its own identity")
    func identitiesAreDistinct() {
        let subject = presented()
        var seen: Set<Int> = [subject.presentationID]

        for _ in 0..<25 {
            subject.beginPresentation()
            #expect(seen.insert(subject.presentationID).inserted, "identity was reused")
            subject.reveal(token: subject.presentationID)
        }
    }
}
