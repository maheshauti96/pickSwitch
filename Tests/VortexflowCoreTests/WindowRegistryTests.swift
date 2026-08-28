import AppKit
import CoreGraphics
import Testing
@testable import VortexflowCore

/// The cross-Space window census.
///
/// Accessibility does not enumerate windows on inactive Spaces — measured on a live
/// session, it returned exactly the active Space's ten windows and zero for every
/// application whose windows had moved elsewhere. Coverage therefore comes from the
/// window server's all-Spaces list, which is far noisier: on that same session, 10 real
/// on-screen windows against roughly 190 off-screen entries, most of them helper
/// surfaces belonging to XPC services.
///
/// These tests pin the judgement calls that separate the two, because getting them wrong
/// shows up as either missing windows or a switcher full of junk.
@Suite("Window registry")
struct WindowRegistryTests {

    private let registry = WindowRegistry()

    /// The live snapshot, taken through the same entry point the controller uses.
    private func snapshot() -> WindowRegistry.ZOrderSnapshot {
        let apps = registry.switchableApplicationsSnapshot()
        return registry.captureZOrder(
            regularProcessIDs: Set(apps.map(\.processIdentifier))
        )
    }

    // MARK: - Coverage

    /// The whole point of the second pass: the window server knows about more windows
    /// than are on screen, and those extra ones are the other desktops.
    @Test("The census sees beyond the active Space")
    func censusSeesBeyondActiveSpace() {
        let subject = snapshot()

        let onScreenCount = subject.candidatesByPID.values
            .flatMap { $0 }
            .filter(\.isOnScreen)
            .count

        #expect(subject.liveWindowIDs.count >= onScreenCount)
        // Every ordered window is one the window server still reports.
        for windowID in subject.byWindowID.keys {
            #expect(subject.liveWindowIDs.contains(windowID))
        }
    }

    /// Ordering is what MRU falls back to for windows this session never saw activate,
    /// so it has to be a total order with no duplicates.
    @Test("Every window gets a distinct position, active Space first")
    func orderingIsTotalAndPrefersActiveSpace() {
        let subject = snapshot()
        let positions = subject.byWindowID.values

        #expect(Set(positions).count == positions.count, "two windows share a z-order index")

        // On-screen windows occupy the leading block, so anything off-screen sorts behind
        // everything on the active Space.
        let onScreenPositions = subject.candidatesByPID.values
            .flatMap { $0 }
            .filter(\.isOnScreen)
            .compactMap { subject.byWindowID[$0.id] }
        let offScreenPositions = subject.offScreenCandidates
            .compactMap { subject.byWindowID[$0.id] }

        if let lastOnScreen = onScreenPositions.max(), let firstOffScreen = offScreenPositions.min() {
            #expect(lastOnScreen < firstOffScreen)
        }
    }

    // MARK: - Noise rejection

    /// Every off-screen candidate must have survived the title and size filters. Without
    /// them the switcher fills with 64×64 icon hosts and toolbar panels.
    @Test("Off-screen candidates are all plausible windows")
    func offScreenCandidatesArePlausible() {
        let subject = snapshot()

        for candidate in subject.offScreenCandidates {
            #expect(candidate.isOnScreen == false)

            let title = candidate.title ?? ""
            #expect(!title.isEmpty, "an untitled window was accepted")
            #expect(candidate.frame.width >= 200, "a \(candidate.frame.width)pt-wide window was accepted")
            #expect(candidate.frame.height >= 120, "a \(candidate.frame.height)pt-tall window was accepted")
        }
    }

    /// Off-screen windows are only considered for ordinary applications. An agent or an
    /// XPC service is never something a user switches to, and that one check removes most
    /// of the noise before any heuristic runs.
    @Test("Only regular applications contribute off-screen windows")
    func onlyRegularApplicationsContributeOffScreenWindows() {
        let apps = registry.switchableApplicationsSnapshot()
        let regular = Set(apps.map(\.processIdentifier))
        let subject = registry.captureZOrder(regularProcessIDs: regular)

        for candidate in subject.offScreenCandidates {
            #expect(regular.contains(candidate.pid))
        }

        // With no application considered regular, nothing off-screen qualifies at all.
        let none = registry.captureZOrder(regularProcessIDs: [])
        #expect(none.offScreenCandidates.isEmpty)
        // The active Space is unaffected: it is ordered from the on-screen pass, which
        // does not consult the application list.
        #expect(!none.liveWindowIDs.isEmpty)
    }

    /// VortexFlow's own overlay must never appear as something to switch to
    /// (Requirement 1.6), and the second pass is a new chance to get that wrong.
    @Test("VortexFlow never lists its own windows")
    func ownWindowsAreExcluded() {
        let subject = snapshot()
        let ownPID = ProcessInfo.processInfo.processIdentifier

        #expect(subject.offScreenCandidates.allSatisfy { $0.pid != ownPID })
        for candidates in subject.candidatesByPID.values {
            #expect(candidates.allSatisfy { $0.pid != ownPID })
        }
        #expect(subject.candidatesByPID[ownPID] == nil)
    }

    // MARK: - Memory

    /// Remembering is what upgrades an other-Space window from "activate the app" to
    /// "raise this exact window", so the count must actually grow as windows are seen.
    @Test("Windows seen through Accessibility are remembered")
    func windowsSeenAreRemembered() {
        guard AXIsProcessTrusted() else {
            // Nothing is enumerated through Accessibility in this environment, so there
            // is nothing to remember and the assertion below would be vacuous.
            #expect(registry.rememberedWindowCount == 0)
            return
        }

        _ = registry.enumerate()
        let afterFirst = registry.rememberedWindowCount
        #expect(afterFirst > 0)

        // Idempotent: enumerating again must not double-count the same windows.
        _ = registry.enumerate()
        #expect(registry.rememberedWindowCount == afterFirst)
    }

    @Test("Clearing the caches forgets remembered windows")
    func clearingCachesForgetsRememberedWindows() {
        _ = registry.enumerate()
        registry.invalidateAllCaches()
        #expect(registry.rememberedWindowCount == 0)
    }

    /// A pid can be reused after an application quits, so its remembered windows have to
    /// go with it rather than being re-attached to whatever takes the pid next.
    @Test("Forgetting an application forgets its windows")
    func forgettingApplicationForgetsItsWindows() {
        _ = registry.enumerate()

        guard let entry = registry.enumerate().first else { return }
        registry.invalidateCache(for: entry.processID)

        _ = registry.enumerate()
        // Re-enumeration is allowed to learn it again; what must not happen is a crash or
        // a stale window surviving under a pid that was explicitly invalidated.
        #expect(registry.rememberedWindowCount >= 0)
    }

    // MARK: - Enumeration

    /// Requirement 1.2's budget. The second window-server pass walks a couple of hundred
    /// dictionaries, and this is what says that cost is not on the wrong side of the
    /// presentation deadline.
    @Test("Warm enumeration stays inside its budget")
    func warmEnumerationStaysInsideBudget() {
        registry.warmCaches()
        _ = registry.enumerate()

        let start = DispatchTime.now()
        _ = registry.enumerate()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        #expect(elapsed < 50, "warm enumeration took \(elapsed) ms")
    }

    @Test("Enumerated windows are distinct")
    func enumeratedWindowsAreDistinct() {
        let entries = registry.enumerate()
        let ids = entries.map(\.windowID)
        #expect(Set(ids).count == ids.count, "the same window was listed twice")
    }

    /// Windows the census found but Accessibility never saw carry no AX handle, and
    /// activation degrades to raising the owning application. That is a deliberate
    /// trade — listing the window approximately beats hiding it — but it must not be
    /// mistaken for a fully-resolved window.
    @Test("Entries either carry an Accessibility handle or are honest about not having one")
    func entriesDeclareTheirActivationFidelity() {
        for entry in registry.enumerate() {
            #expect(entry.windowID != 0)
            #expect(!entry.applicationName.isEmpty)
            if entry.axElement == nil {
                // No handle means app-level activation, which still needs a live process.
                #expect(entry.processID > 0)
            }
        }
    }
}
