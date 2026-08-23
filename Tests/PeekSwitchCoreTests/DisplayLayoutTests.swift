import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// Mapping windows onto the display they are actually on.
///
/// All of this is arrangement-dependent, and a test machine has whatever displays it
/// has — so the geometry is pure and driven by synthetic arrangements, including the
/// awkward ones: a secondary display at a negative origin, stacked displays, a window
/// dragged half-way across a boundary, and a window that is nowhere at all.
@Suite("Display layout")
struct DisplayLayoutTests {

    /// The arrangement this was developed against: an external monitor at the origin
    /// carrying the menu bar, with the laptop placed to its left. Worth pinning as a
    /// fixture because it is the case where "primary display" and "leftmost display"
    /// disagree.
    private static let laptopLeftOfExternal = DisplayLayout(displays: [
        DisplayInfo(
            number: 1,
            bounds: CGRect(x: -1512, y: 36, width: 1512, height: 982),
            isBuiltIn: true,
            name: "Built-in Retina Display"
        ),
        DisplayInfo(
            number: 2,
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isBuiltIn: false,
            name: "SAMSUNG"
        ),
    ])

    private static let single = DisplayLayout(displays: [
        DisplayInfo(
            number: 1,
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isBuiltIn: true,
            name: "Built-in Retina Display"
        )
    ])

    // MARK: - Matching

    @Test("A window sitting on one display is attributed to it")
    func windowOnOneDisplay() {
        let layout = Self.laptopLeftOfExternal

        let onLaptop = CGRect(x: -1400, y: 100, width: 800, height: 600)
        #expect(layout.display(for: onLaptop)?.number == 1)
        #expect(layout.display(for: onLaptop)?.isBuiltIn == true)

        let onExternal = CGRect(x: 200, y: 150, width: 900, height: 700)
        #expect(layout.display(for: onExternal)?.number == 2)
        #expect(layout.display(for: onExternal)?.name == "SAMSUNG")
    }

    /// macOS treats a straddling window as belonging to whichever display holds most of
    /// it, and so does the badge.
    @Test("A window straddling two displays follows the larger share")
    func straddlingWindowFollowsLargerShare() {
        let layout = Self.laptopLeftOfExternal

        // 700pt on the laptop, 100pt on the external.
        let mostlyLaptop = CGRect(x: -700, y: 200, width: 800, height: 600)
        #expect(layout.display(for: mostlyLaptop)?.number == 1)

        // 100pt on the laptop, 700pt on the external.
        let mostlyExternal = CGRect(x: -100, y: 200, width: 800, height: 600)
        #expect(layout.display(for: mostlyExternal)?.number == 2)
    }

    /// A minimized window can report a zero size, which produces no overlap with
    /// anything. Its position still says where it lives.
    @Test("A zero-sized window falls back to where its centre is")
    func zeroSizedWindowUsesCentre() {
        let layout = Self.laptopLeftOfExternal

        let collapsedOnLaptop = CGRect(x: -800, y: 400, width: 0, height: 0)
        #expect(layout.display(for: collapsedOnLaptop)?.number == 1)

        let collapsedOnExternal = CGRect(x: 900, y: 500, width: 0, height: 0)
        #expect(layout.display(for: collapsedOnExternal)?.number == 2)
    }

    /// Better to show no label than a confidently wrong one.
    @Test("A window on no display is not attributed to one")
    func windowOnNoDisplayIsUnattributed() {
        let layout = Self.laptopLeftOfExternal
        let nowhere = CGRect(x: 9000, y: 9000, width: 400, height: 300)
        #expect(layout.display(for: nowhere) == nil)
    }

    @Test("An empty arrangement attributes nothing")
    func emptyLayoutAttributesNothing() {
        #expect(DisplayLayout.empty.display(for: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
        #expect(DisplayLayout.empty.isMultiDisplay == false)
    }

    @Test("Stacked displays are told apart vertically")
    func stackedDisplaysAreDistinguished() {
        let layout = DisplayLayout(displays: [
            DisplayInfo(number: 1, bounds: CGRect(x: 0, y: -1080, width: 1920, height: 1080), isBuiltIn: false, name: "Top"),
            DisplayInfo(number: 2, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080), isBuiltIn: true, name: "Bottom"),
        ])

        #expect(layout.display(for: CGRect(x: 100, y: -900, width: 400, height: 300))?.number == 1)
        #expect(layout.display(for: CGRect(x: 100, y: 200, width: 400, height: 300))?.number == 2)
    }

    // MARK: - Labelling policy

    /// On one display, every window is on the same screen and a badge saying so on
    /// every card is pure noise.
    @Test("Labelling is off with a single display")
    func singleDisplayIsNotLabelled() {
        #expect(Self.single.isMultiDisplay == false)
        #expect(Self.laptopLeftOfExternal.isMultiDisplay == true)
    }

    @Test("Labels are short on cards and spelled out for assistive tech")
    func labelsSuitTheirPlace() {
        guard let laptop = Self.laptopLeftOfExternal.display(number: 1),
              let external = Self.laptopLeftOfExternal.display(number: 2) else {
            Issue.record("fixture is missing a display")
            return
        }

        #expect(laptop.shortLabel == "1")
        #expect(laptop.label == "Screen 1")
        #expect(laptop.detailedLabel == "Screen 1 · Built-in Retina Display")

        #expect(external.shortLabel == "2")
        #expect(external.label == "Screen 2")
        #expect(external.detailedLabel == "Screen 2 · SAMSUNG")
    }

    @Test("A display with no name still gets a label")
    func unnamedDisplayStillHasALabel() {
        let display = DisplayInfo(number: 3, bounds: .zero, isBuiltIn: false, name: "")
        #expect(display.label == "Screen 3")
        #expect(display.detailedLabel == "Screen 3")
    }

    @Test("Looking up a display by number")
    func lookupByNumber() {
        #expect(Self.laptopLeftOfExternal.display(number: 1)?.isBuiltIn == true)
        #expect(Self.laptopLeftOfExternal.display(number: 2)?.isBuiltIn == false)
        #expect(Self.laptopLeftOfExternal.display(number: 3) == nil)
    }

    // MARK: - State integration

    /// The lookup is precomputed once per presentation, so it has to survive a reload
    /// and it has to stay silent on a single-display machine.
    @Test("Overlay state resolves each window's display once")
    @MainActor
    func overlayStateResolvesDisplays() {
        let state = OverlayState()
        state.displayLayout = Self.laptopLeftOfExternal

        let onLaptop = Fixture.entry(
            id: 1,
            app: "Xcode",
            frame: CGRect(x: -1400, y: 100, width: 800, height: 600)
        )
        let onExternal = Fixture.entry(
            id: 2,
            app: "Safari",
            frame: CGRect(x: 300, y: 200, width: 900, height: 700)
        )
        let nowhere = Fixture.entry(
            id: 3,
            app: "Ghost",
            frame: CGRect(x: 9000, y: 9000, width: 10, height: 10)
        )

        state.load(entries: [onLaptop, onExternal, nowhere], selectedIndex: 0)

        #expect(state.display(for: onLaptop)?.number == 1)
        #expect(state.display(for: onExternal)?.number == 2)
        #expect(state.display(for: nowhere) == nil)
    }

    @Test("Overlay state labels nothing on a single display")
    @MainActor
    func overlayStateSuppressesLabelsOnOneDisplay() {
        let state = OverlayState()
        state.displayLayout = Self.single
        let entry = Fixture.entry(id: 1, frame: CGRect(x: 10, y: 10, width: 400, height: 300))
        state.load(entries: [entry], selectedIndex: 0)

        #expect(state.display(for: entry) == nil)
    }

    /// Reloading with a different arrangement must not leave stale badges behind.
    @Test("Reloading refreshes the resolved displays")
    @MainActor
    func reloadRefreshesResolvedDisplays() {
        let state = OverlayState()
        state.displayLayout = Self.laptopLeftOfExternal
        let entry = Fixture.entry(id: 7, frame: CGRect(x: -1400, y: 100, width: 800, height: 600))
        state.load(entries: [entry], selectedIndex: 0)
        #expect(state.display(for: entry)?.number == 1)

        // The external monitor is unplugged; one display left, so no labels.
        state.displayLayout = Self.single
        state.load(entries: [entry], selectedIndex: 0)
        #expect(state.display(for: entry) == nil)
    }
}
