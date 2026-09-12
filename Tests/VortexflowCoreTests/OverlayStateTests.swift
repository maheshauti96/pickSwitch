import CoreGraphics
import Testing
@testable import VortexflowCore

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
        subject.layoutStyle = .strip
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

/// The facts the spiral's middle reads, and the guard that keeps one of them from leaking.
@Suite("Hub facts")
@MainActor
struct HubFactsTests {

    private func state(entries: [WindowEntry]) -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1200
        state.availableContentHeight = 800
        state.isVisible = true
        state.load(entries: entries, selectedIndex: 0)
        return state
    }

    private func chromeWindows() -> [WindowEntry] {
        (1...3).map { index in
            var entry = Fixture.entry(
                id: CGWindowID(index),
                app: "Google Chrome",
                title: "Chrome window \(index)",
                zOrder: index
            )
            entry.isOnActiveSpace = true
            return entry
        }
    }

    /// A private window's destination must never be named, and the guard belongs on the read rather
    /// than only on the write: a `CGWindowID` can be reclassified part-way through a presentation,
    /// after a host has already been recorded for it.
    @Test("a host recorded before a window was known to be private is never read back")
    func privateWindowNeverNamesItsSite() {
        let windows = chromeWindows()
        let subject = state(entries: windows)
        subject.setSiteHost("github.com", for: 2, presentationID: subject.presentationID)
        #expect(subject.siteHost(for: windows[1]) == "github.com")

        // The browser answers late, and this window turns out to be a private one.
        subject.incognitoWindowIDs = [2]

        #expect(subject.siteHost(for: windows[1]) == nil)
        let summary = subject.hubSummary(for: windows[1])
        #expect(summary.identifyingSource == nil)
        #expect(summary.sourceLine == "Google Chrome \u{00B7} 2 of 3")
    }

    /// Hosts arrive from an asynchronous browser inspection, which can finish after the presentation
    /// it belongs to has gone.
    @Test("a host from a finished presentation is refused")
    func staleHostIsRefused() {
        let windows = chromeWindows()
        let subject = state(entries: windows)
        subject.setSiteHost("github.com", for: 1, presentationID: subject.presentationID - 1)
        #expect(subject.siteHost(for: windows[0]) == nil)
    }

    /// Counted over the unfiltered list on purpose. Searching narrows what is on screen; it does not
    /// close two of the three Chrome windows, and "2 of 3" turning into "1 of 1" as the user types
    /// would describe the search rather than the window.
    @Test("position among an application's windows survives a search")
    func positionIsUnaffectedBySearch() {
        let windows = chromeWindows()
        let subject = state(entries: windows)
        let before = subject.windowPosition(for: windows[1])
        #expect(before?.index == 2)
        #expect(before?.count == 3)

        subject.appendToSearch("window 2")
        // Counted over local results: a query also offers the web and the assistants, and those
        // are appended rather than filtered, so `entries` alone no longer shrinks.
        #expect(subject.localEntries.count < 3, "the search should have filtered the list")

        let after = subject.windowPosition(for: windows[1])
        #expect(after?.index == 2, "index should still describe the application, not the search")
        #expect(after?.count == 3, "count should still describe the application, not the search")
    }

    /// One window means no position, so the hub's source line disappears rather than reading
    /// "Warp · 1 of 1".
    @Test("a lone window reports no position and no source line")
    func loneWindowHasNoSourceLine() {
        var entry = Fixture.entry(id: 9, app: "Warp", title: "zsh")
        entry.isOnActiveSpace = true
        let subject = state(entries: [entry])

        #expect(subject.windowPosition(for: entry) == nil)
        #expect(subject.hubSummary(for: entry).sourceLine == nil)
    }

    // MARK: - Radial ring angle

    @Test("A fresh spiral snaps the ring onto the selected seat")
    func loadSnapsTheRingAngle() throws {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = .spiral
        subject.load(
            entries: (0..<8).map { Fixture.entry(id: CGWindowID($0 + 1), zOrder: $0) },
            selectedIndex: 1
        )

        let seat = try #require(subject.layout.radialSeats.first { $0.index == 1 }?.seat)
        #expect(abs(subject.radialRingAngle - seat.midAngle) < 0.0001)
    }

    @Test("Moving the selection across the top of the ring takes the short arc")
    func selectionFollowsTheShortArc() {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = .circular
        subject.load(
            entries: (0..<8).map { Fixture.entry(id: CGWindowID($0 + 1), zOrder: $0) },
            selectedIndex: 7
        )
        let last = subject.radialRingAngle
        subject.setSelection(0)
        let hop = subject.radialRingAngle - last
        #expect(abs(hop) < .pi / 2, "crossing the top should be a short step, got \(hop)")
    }
}
