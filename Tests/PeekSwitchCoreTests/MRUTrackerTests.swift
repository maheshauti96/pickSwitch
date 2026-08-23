import CoreGraphics
import Foundation
import Testing
@testable import PeekSwitchCore

/// Requirement 2: per-window MRU ordering, frontmost pinning, history truncation.
@Suite("MRU tracker")
struct MRUTrackerTests {

    /// Controllable clock so ordering is deterministic and fast.
    private final class Clock {
        var now: TimeInterval = 1000
        func advance(_ delta: TimeInterval = 1) { now += delta }
    }

    private func makeTracker() -> (MRUTracker, Clock) {
        let clock = Clock()
        return (MRUTracker(now: { clock.now }), clock)
    }

    private func ids(_ entries: [WindowEntry]) -> [CGWindowID] {
        entries.map(\.windowID)
    }

    // MARK: - Ordering

    /// Requirement 2.6: with nothing observed yet, z-order is the order.
    @Test("Unseen windows fall back to z-order")
    func unseenWindowsUseZOrder() {
        let (tracker, _) = makeTracker()
        let entries = [
            Fixture.entry(id: 3, zOrder: 2),
            Fixture.entry(id: 1, zOrder: 0),
            Fixture.entry(id: 2, zOrder: 1),
        ]
        #expect(ids(tracker.ordered(entries, historyDepth: 10)) == [1, 2, 3])
    }

    /// Requirement 2.3 combined with 2.4.
    @Test("Observed activations outrank z-order for non-frontmost windows")
    func activationsOutrankZOrder() {
        let (tracker, clock) = makeTracker()
        let entries = [
            Fixture.entry(id: 1, zOrder: 0),
            Fixture.entry(id: 2, zOrder: 1),
            Fixture.entry(id: 3, zOrder: 2),
        ]

        tracker.recordActivation(windowID: 3)
        clock.advance()
        tracker.recordActivation(windowID: 2)

        // 1 is frontmost so it is pinned leftmost; 2 and 3 follow in MRU order.
        #expect(ids(tracker.ordered(entries, historyDepth: 10)) == [1, 2, 3])
    }

    @Test("The most recently activated window leads the non-frontmost group")
    func mostRecentComesFirst() {
        let (tracker, clock) = makeTracker()
        // z-orders start at 5 so frontmost-pinning does not mask the MRU result.
        let entries = [
            Fixture.entry(id: 1, zOrder: 5),
            Fixture.entry(id: 2, zOrder: 6),
            Fixture.entry(id: 3, zOrder: 7),
        ]

        tracker.recordActivation(windowID: 1)
        clock.advance()
        tracker.recordActivation(windowID: 3)
        clock.advance()
        tracker.recordActivation(windowID: 2)

        let result = ids(tracker.ordered(entries, historyDepth: 10))
        #expect(result.first == 1, "frontmost window must be leftmost")
        #expect(Array(result.dropFirst()) == [2, 3])
    }

    /// Requirement 2.4.
    @Test("The frontmost window is pinned leftmost")
    func frontmostIsPinnedLeftmost() {
        let (tracker, clock) = makeTracker()
        let entries = [
            Fixture.entry(id: 1, zOrder: 3),
            Fixture.entry(id: 2, zOrder: 0),
            Fixture.entry(id: 3, zOrder: 1),
        ]
        tracker.recordActivation(windowID: 1)
        clock.advance()
        tracker.recordActivation(windowID: 3)

        #expect(ids(tracker.ordered(entries, historyDepth: 10)).first == 2)
    }

    @Test("Ordering is stable across repeated calls")
    func orderingIsStable() {
        let (tracker, _) = makeTracker()
        let entries = Fixture.entries(count: 6)
        #expect(ids(tracker.ordered(entries, historyDepth: 10)) == ids(tracker.ordered(entries, historyDepth: 10)))
    }

    @Test("Empty input produces empty output")
    func emptyInput() {
        let (tracker, _) = makeTracker()
        #expect(tracker.ordered([], historyDepth: 10).isEmpty)
    }

    // MARK: - History depth

    /// Requirement 2.7.
    @Test("History depth truncates the list")
    func historyDepthTruncates() {
        let (tracker, _) = makeTracker()
        let result = tracker.ordered(Fixture.entries(count: 20), historyDepth: 7)
        #expect(result.count == 7)
        #expect(ids(result) == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("A history depth above the window count keeps everything")
    func historyDepthAboveCount() {
        let (tracker, _) = makeTracker()
        #expect(tracker.ordered(Fixture.entries(count: 4), historyDepth: 25).count == 4)
    }

    /// Truncation must not be able to drop the window the user is currently in.
    @Test("The frontmost window survives truncation")
    func frontmostSurvivesTruncation() {
        let (tracker, clock) = makeTracker()

        // Windows 1...19 sit behind window 20. Only window 20 has z-order 0, so it
        // is unambiguously the frontmost one.
        var entries = (1...19).map { Fixture.entry(id: CGWindowID($0), zOrder: $0) }
        entries.append(Fixture.entry(id: 20, zOrder: 0))

        // Give every other window a newer activation stamp, so MRU order alone would
        // push window 20 to the very back and a naive truncation would drop it.
        for id in 1...19 {
            tracker.recordActivation(windowID: CGWindowID(id))
            clock.advance()
        }

        let result = ids(tracker.ordered(entries, historyDepth: 5))
        #expect(result.count == 5)
        #expect(result.first == 20)
    }

    // MARK: - Lifecycle

    /// Requirement 2.8.
    @Test("Forgetting a window drops its timestamp")
    func forgetDropsTimestamp() {
        let (tracker, _) = makeTracker()
        tracker.recordActivation(windowID: 42)
        #expect(tracker.timestamp(for: 42) != nil)
        tracker.forget(windowID: 42)
        #expect(tracker.timestamp(for: 42) == nil)
    }

    @Test("Pruning keeps only living windows")
    func pruneKeepsLivingWindows() {
        let (tracker, _) = makeTracker()
        tracker.recordActivation(windowID: 1)
        tracker.recordActivation(windowID: 2)
        tracker.recordActivation(windowID: 3)

        tracker.prune(livingWindowIDs: [1, 3])

        #expect(tracker.timestamp(for: 1) != nil)
        #expect(tracker.timestamp(for: 2) == nil)
        #expect(tracker.timestamp(for: 3) != nil)
    }

    @Test("Reactivating a window refreshes its timestamp")
    func reactivationRefreshesTimestamp() {
        let (tracker, clock) = makeTracker()
        tracker.recordActivation(windowID: 2)
        clock.advance()
        tracker.recordActivation(windowID: 1)
        clock.advance()
        tracker.recordActivation(windowID: 2)

        let first = tracker.timestamp(for: 1)
        let second = tracker.timestamp(for: 2)
        #expect(first != nil)
        #expect(second != nil)
        if let first, let second {
            #expect(second > first)
        }
    }

    // MARK: - Minimized windows

    /// Minimized windows have no CGWindowList row, so the registry gives them a
    /// back-of-the-list z-order. They must still be listed (Requirement 1.4).
    @Test("Minimized windows sort to the back but stay in the list")
    func minimizedWindowsSortToBack() {
        let (tracker, _) = makeTracker()
        let entries = [
            Fixture.entry(id: 1, zOrder: Int.max - 1, minimized: true),
            Fixture.entry(id: 2, zOrder: 0),
            Fixture.entry(id: 3, zOrder: 1),
        ]
        let result = ids(tracker.ordered(entries, historyDepth: 10))
        #expect(result == [2, 3, 1])
        #expect(result.contains(1))
    }
}

// MARK: - Last seen

/// The "seen but never used" tier.
///
/// It exists because of cross-Space enumeration: Accessibility only reports the active
/// Space, so a window on another desktop has no focus history from this session. Without a
/// second signal it would be ordered by its slot in the window server's all-Spaces list,
/// which bears no relation to how recently the user was working in it.
extension MRUTrackerTests {

    private func seen(
        id: CGWindowID,
        at lastSeen: TimeInterval,
        zOrder: Int = 500,
        app: String = "TestApp"
    ) -> WindowEntry {
        var entry = Fixture.entry(id: id, app: app, zOrder: zOrder)
        entry.lastSeenOnActiveSpace = lastSeen
        return entry
    }

    @Test("A window seen more recently sorts first")
    func moreRecentlySeenSortsFirst() {
        let (tracker, _) = makeTracker()

        // Equal z-order on purpose. Requirement 2.4 pins the frontmost window leftmost
        // regardless of recency, so varying z-order here would test the pin rather than the
        // ordering under examination.
        let older = seen(id: 1, at: 100)
        let newer = seen(id: 2, at: 200)

        #expect(ids(tracker.ordered([older, newer], historyDepth: 10)) == [2, 1])
    }

    /// A window the user actually switched to always beats one merely seen, however long
    /// ago the switch was.
    @Test("Having been used outranks having been seen")
    func usedOutranksSeen() {
        let (tracker, clock) = makeTracker()

        let used = Fixture.entry(id: 1, zOrder: 500)
        // Seen far in the future relative to the activation, to prove the tiers cannot
        // interleave on raw timestamp value.
        let justSeen = seen(id: 2, at: clock.now + 10_000)

        tracker.recordActivation(windowID: 1)

        #expect(ids(tracker.ordered([justSeen, used], historyDepth: 10)) == [1, 2])
    }

    /// And a window that was seen at some point beats one never seen at all, whatever its
    /// z-order.
    @Test("Having been seen outranks never having been seen")
    func seenOutranksNeverSeen() {
        let (tracker, _) = makeTracker()

        let neverSeen = Fixture.entry(id: 1, zOrder: 500)
        // Seen a long time ago, and still ahead of a window never seen at all.
        let longAgo = seen(id: 2, at: -50_000)

        #expect(ids(tracker.ordered([neverSeen, longAgo], historyDepth: 10)) == [2, 1])
    }

    /// The three tiers together, which is the ordering a user with several desktops sees.
    @Test("Used, then seen, then never seen")
    func tiersAreOrdered() {
        let (tracker, clock) = makeTracker()

        let used = Fixture.entry(id: 1, zOrder: 500)
        let seenRecently = seen(id: 2, at: clock.now - 10)
        let seenEarlier = seen(id: 3, at: clock.now - 100)
        let neverSeen = Fixture.entry(id: 4, zOrder: 500)

        tracker.recordActivation(windowID: 1)

        let order = ids(tracker.ordered([neverSeen, seenEarlier, seenRecently, used], historyDepth: 10))
        #expect(order == [1, 2, 3, 4])
    }

    /// Switching to a window supersedes whatever the seen stamp said, so a window used once
    /// does not keep sorting by when it was last visible.
    @Test("Using a seen window promotes it out of the seen tier")
    func usingASeenWindowPromotesIt() {
        let (tracker, clock) = makeTracker()

        let seenLater = seen(id: 1, at: clock.now)
        let seenEarlier = seen(id: 2, at: clock.now - 500)

        #expect(ids(tracker.ordered([seenLater, seenEarlier], historyDepth: 10)) == [1, 2])

        // The user switches to the older one.
        clock.advance()
        tracker.recordActivation(windowID: 2)
        #expect(ids(tracker.ordered([seenLater, seenEarlier], historyDepth: 10)) == [2, 1])
    }

    /// Ordering must not shuffle between presentations when nothing has changed.
    @Test("Seen ordering is stable across repeated calls")
    func seenOrderingIsStable() {
        let (tracker, _) = makeTracker()
        let entries = [
            seen(id: 1, at: 300, zOrder: 30),
            seen(id: 2, at: 200, zOrder: 20),
            seen(id: 3, at: 100, zOrder: 10),
        ]

        let first = ids(tracker.ordered(entries, historyDepth: 10))
        #expect(first == ids(tracker.ordered(entries, historyDepth: 10)))
        #expect(first == ids(tracker.ordered(entries.reversed(), historyDepth: 10)))
    }

    /// Two windows seen in the same enumeration share a stamp, so something else has to
    /// break the tie or the strip would reorder at random.
    @Test("Windows seen at the same moment keep a stable order")
    func simultaneouslySeenWindowsAreStable() {
        let (tracker, _) = makeTracker()
        let entries = [
            seen(id: 7, at: 500, zOrder: 2),
            seen(id: 3, at: 500, zOrder: 1),
            seen(id: 5, at: 500, zOrder: 3),
        ]

        let order = ids(tracker.ordered(entries, historyDepth: 10))
        #expect(order == ids(tracker.ordered(entries.shuffled(), historyDepth: 10)))
    }
}

// MARK: - Pinned applications

/// Applications the user has asked to always see first.
///
/// Pinning is a coarser key than recency, which is the whole point: a pinned window that
/// has not been touched in an hour should still beat an unpinned one from a minute ago.
extension MRUTrackerTests {

    private func owned(
        id: CGWindowID,
        bundle: String?,
        zOrder: Int = 500,
        app: String = "TestApp"
    ) -> WindowEntry {
        var entry = Fixture.entry(id: id, app: app, zOrder: zOrder)
        entry.bundleIdentifier = bundle
        return entry
    }

    @Test("A pinned application's windows come first")
    func pinnedWindowsComeFirst() {
        let (tracker, clock) = makeTracker()

        let pinned = owned(id: 1, bundle: "com.slack", app: "Slack")
        let recent = owned(id: 2, bundle: "com.other", app: "Other")

        // The unpinned window was used far more recently.
        tracker.recordActivation(windowID: 1)
        clock.advance(1000)
        tracker.recordActivation(windowID: 2)

        let order = ids(tracker.ordered([pinned, recent], historyDepth: 10, pinnedApplications: ["com.slack"]))
        #expect(order == [1, 2])

        // Without the pin, recency decides and the order reverses.
        #expect(ids(tracker.ordered([pinned, recent], historyDepth: 10)) == [2, 1])
    }

    /// Pinning reorders groups; it does not throw away the ordering inside them.
    @Test("Recency still orders windows within the pinned group")
    func recencyOrdersWithinPinnedGroup() {
        let (tracker, clock) = makeTracker()

        let older = owned(id: 1, bundle: "com.slack")
        let newer = owned(id: 2, bundle: "com.slack")
        let unpinned = owned(id: 3, bundle: "com.other")

        tracker.recordActivation(windowID: 1)
        clock.advance()
        tracker.recordActivation(windowID: 2)
        clock.advance()
        tracker.recordActivation(windowID: 3)

        let order = ids(tracker.ordered(
            [older, newer, unpinned],
            historyDepth: 10,
            pinnedApplications: ["com.slack"]
        ))
        #expect(order == [2, 1, 3])
    }

    /// Requirement 2.4 still wins the leftmost slot. Keeping the current window there is
    /// what preserves the switcher's core gesture: the initial selection is the second card,
    /// so pinned windows become the first thing you can switch *to*.
    @Test("The current window keeps the leftmost slot")
    func currentWindowKeepsLeftmostSlot() {
        let (tracker, _) = makeTracker()

        let current = owned(id: 1, bundle: "com.other", zOrder: 0)
        let pinned = owned(id: 2, bundle: "com.slack", zOrder: 5)

        let order = ids(tracker.ordered([current, pinned], historyDepth: 10, pinnedApplications: ["com.slack"]))
        #expect(order == [1, 2])
    }

    @Test("Pinning several applications keeps them all ahead")
    func severalPinnedApplicationsStayAhead() {
        let (tracker, clock) = makeTracker()

        let slack = owned(id: 1, bundle: "com.slack")
        let notes = owned(id: 2, bundle: "com.notes")
        let other = owned(id: 3, bundle: "com.other")

        tracker.recordActivation(windowID: 3)
        clock.advance()
        tracker.recordActivation(windowID: 1)
        clock.advance()
        tracker.recordActivation(windowID: 2)

        let order = ids(tracker.ordered(
            [slack, notes, other],
            historyDepth: 10,
            pinnedApplications: ["com.slack", "com.notes"]
        ))
        #expect(order == [2, 1, 3])
    }

    /// Pinning must not resurrect windows of an application that has none open.
    @Test("Pinning an application with no windows changes nothing")
    func pinningApplicationWithoutWindowsChangesNothing() {
        let (tracker, _) = makeTracker()
        let entries = [owned(id: 1, bundle: "com.other"), owned(id: 2, bundle: "com.another")]

        #expect(
            ids(tracker.ordered(entries, historyDepth: 10, pinnedApplications: ["com.absent"]))
                == ids(tracker.ordered(entries, historyDepth: 10))
        )
    }

    /// Some processes have no bundle identifier at all; they must not crash or accidentally
    /// match a pin.
    @Test("A window with no bundle identifier is never pinned")
    func windowWithoutBundleIdentifierIsNeverPinned() {
        let (tracker, _) = makeTracker()

        let anonymous = owned(id: 1, bundle: nil)
        let pinned = owned(id: 2, bundle: "com.slack")

        let order = ids(tracker.ordered([anonymous, pinned], historyDepth: 10, pinnedApplications: ["com.slack"]))
        #expect(order == [2, 1])
    }

    /// Because pinned windows sort first, a small history depth cannot drop them.
    @Test("Truncation keeps the pinned windows")
    func truncationKeepsPinnedWindows() {
        let (tracker, clock) = makeTracker()

        var entries: [WindowEntry] = []
        for index in 1...10 {
            entries.append(owned(id: CGWindowID(index), bundle: "com.other"))
            tracker.recordActivation(windowID: CGWindowID(index))
            clock.advance()
        }
        // Pinned, and deliberately the least recently used of the lot.
        var pinned = owned(id: 99, bundle: "com.slack")
        pinned.lastSeenOnActiveSpace = nil
        entries.append(pinned)

        let order = ids(tracker.ordered(entries, historyDepth: 3, pinnedApplications: ["com.slack"]))
        #expect(order.count == 3)
        #expect(order.contains(99))
    }

    @Test("Pinned ordering is stable across repeated calls")
    func pinnedOrderingIsStable() {
        let (tracker, clock) = makeTracker()
        let entries = [
            owned(id: 1, bundle: "com.slack"),
            owned(id: 2, bundle: "com.other"),
            owned(id: 3, bundle: "com.slack"),
        ]
        for entry in entries {
            tracker.recordActivation(windowID: entry.windowID)
            clock.advance()
        }

        let pins: Set<String> = ["com.slack"]
        let first = ids(tracker.ordered(entries, historyDepth: 10, pinnedApplications: pins))
        #expect(first == ids(tracker.ordered(entries, historyDepth: 10, pinnedApplications: pins)))
        #expect(first == ids(tracker.ordered(entries.reversed(), historyDepth: 10, pinnedApplications: pins)))
    }
}
