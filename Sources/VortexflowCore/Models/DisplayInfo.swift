import AppKit
import CoreGraphics
import Foundation

/// One active display, numbered the way a person would number it.
struct DisplayInfo: Equatable, Identifiable, Sendable {

    /// 1-based, numbered left to right and then top to bottom across the arrangement.
    ///
    /// Spatial order rather than "the menu bar display first". Those differ more often
    /// than you would think — a laptop with an external monitor set as the primary
    /// display puts the menu bar on the external while the laptop sits to its left — and
    /// when they differ, spatial order is the one that matches what the user sees on
    /// their desk. Numbering by primary would have called the external monitor Screen 1
    /// and the laptop to its left Screen 2, which is backwards from how anyone would
    /// describe that setup.
    let number: Int
    /// Bounds in Quartz global display coordinates — origin at the top-left of the
    /// main display, y increasing downward.
    ///
    /// This is the same space `WindowEntry.frame` uses, whether it came from
    /// `kAXPositionAttribute` or `kCGWindowBounds`, which is why window-to-display
    /// matching needs no coordinate conversion. `NSScreen.frame` is *not* this space,
    /// so it is deliberately not the source here.
    let bounds: CGRect
    let isBuiltIn: Bool
    /// The display's own name, e.g. "Built-in Retina Display" or "DELL U2720Q".
    /// Empty when macOS does not offer one.
    let name: String

    var id: Int { number }

    /// Short form for a card, where there is room for two or three characters.
    var shortLabel: String { "\(number)" }

    /// Spoken and long form.
    var label: String { "Screen \(number)" }

    /// Label plus the display's name, when it has one worth showing.
    var detailedLabel: String {
        name.isEmpty ? label : "\(label) · \(name)"
    }
}

/// The current display arrangement, and which display a given window sits on.
///
/// The matching logic is pure so it can be tested against synthetic arrangements —
/// side-by-side, stacked, negative origins, and windows dragged half-way between two
/// displays — none of which are reproducible on a single test machine.
struct DisplayLayout: Equatable, Sendable {

    let displays: [DisplayInfo]

    init(displays: [DisplayInfo]) {
        self.displays = displays
    }

    static let empty = DisplayLayout(displays: [])

    /// Whether it is worth labelling windows at all. On one display every window is on
    /// the same screen, and a badge saying so on every card is noise.
    var isMultiDisplay: Bool { displays.count > 1 }

    func display(number: Int) -> DisplayInfo? {
        displays.first { $0.number == number }
    }

    /// Which display a window is on.
    ///
    /// A window can straddle two displays, and macOS itself considers a window to be
    /// "on" whichever display holds most of it, so the largest-overlap rule is both
    /// correct and what the user expects. The centre-point fallback covers a window
    /// with an empty or degenerate frame — a minimized window whose reported size is
    /// zero, for instance — and windows entirely outside every display return `nil`
    /// rather than being attributed to a screen they are not on.
    func display(for windowFrame: CGRect) -> DisplayInfo? {
        guard !displays.isEmpty else { return nil }

        var best: DisplayInfo?
        var bestArea: CGFloat = 0

        for display in displays {
            let overlap = display.bounds.intersection(windowFrame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = display
            }
        }
        if let best, bestArea > 0 { return best }

        // Zero-area windows never produce an overlap, so fall back to where the window
        // claims to be.
        let centre = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return displays.first { $0.bounds.contains(centre) }
    }
}

extension DisplayLayout {

    /// Read the live arrangement.
    ///
    /// `NSScreen` is touched only for display names, so this should be called from the
    /// main thread. The controller captures it alongside the other screen geometry it
    /// already reads on main before handing off to the enumeration queue.
    @MainActor
    static func current() -> DisplayLayout {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return .empty
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return .empty
        }

        let namesByID = displayNames()

        // A mirrored display shows the same content as the one it mirrors, so listing
        // it separately would offer the user a "Screen 3" that is really Screen 1.
        let distinct = ids.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        let ordered = distinct.sorted { orderedBefore($0, $1) }

        let displays = ordered.enumerated().map { index, id in
            DisplayInfo(
                number: index + 1,
                bounds: CGDisplayBounds(id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                name: namesByID[id] ?? ""
            )
        }
        return DisplayLayout(displays: displays)
    }

    /// Left to right, then top to bottom, with the display ID as a final tie-break so
    /// the order is total and cannot shuffle between presentations.
    private static func orderedBefore(_ lhs: CGDirectDisplayID, _ rhs: CGDirectDisplayID) -> Bool {
        let left = CGDisplayBounds(lhs)
        let right = CGDisplayBounds(rhs)
        if left.minX != right.minX { return left.minX < right.minX }
        if left.minY != right.minY { return left.minY < right.minY }
        return lhs < rhs
    }

    @MainActor
    private static func displayNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            names[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }
        return names
    }
}
