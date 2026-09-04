import AppKit
import Carbon.HIToolbox

/// Something the user pinned into a slot in the seam between the hub and the first turn.
enum PinnedShortcut: Codable, Equatable, Sendable {
    case link(URL)
    case app(URL)
    case keys(HotKeyShortcut)

    var title: String {
        switch self {
        case .link(let url): return url.host ?? url.absoluteString
        case .app(let url): return url.deletingPathExtension().lastPathComponent
        case .keys(let shortcut): return shortcut.displayName
        }
    }

    /// The hub caption's eyebrow line while this slot is under the pointer.
    var kindLabel: String {
        switch self {
        case .link: return "Pinned link"
        case .app: return "Pinned app"
        case .keys: return "Keyboard shortcut"
        }
    }

    // MARK: - Storage

    /// How many pins the first turn holds. A second turn is only laid out once the user
    /// actually has more than this — an empty sixth slot is not a reason to open a layer.
    static let firstLayerCount = 5
    /// Storage cap. The seam usually seats eight or nine — the first turn plus an inner
    /// turn under the deepest seats — and this is a little above that so a generous
    /// display is not the thing that refuses the tenth pin.
    static let slotCount = 10
    static let defaultsKey = "pinnedShortcuts"

    /// How many pin tiles to draw. The plus is a separate mark in the leftover gap, not a tile.
    static func visibleSlotCount(forPins count: Int) -> Int {
        min(slotCount, count)
    }

    /// One ordered JSON array; the order *is* the layout. An earlier format stored `null`
    /// for empty positions, which decoding as optionals and compacting still accepts.
    static func load(from defaults: UserDefaults = .standard) -> [PinnedShortcut] {
        let stored = defaults.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode([PinnedShortcut?].self, from: $0) } ?? []
        return Array(stored.compactMap { $0 }.prefix(slotCount))
    }

    static func save(_ pins: [PinnedShortcut], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(pins), forKey: defaultsKey)
    }

    // MARK: - Running

    /// Keystrokes go out after a beat so the overlay's dismissal has returned focus to the
    /// window they are meant for.
    func perform() {
        switch self {
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .app(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .keys(let shortcut):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                for isDown in [true, false] {
                    let event = CGEvent(
                        keyboardEventSource: nil, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: isDown
                    )
                    event?.flags = shortcut.eventFlags
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    }
}

/// A menu item target that runs a closure. `NSMenuItem.target` is weak, so the caller
/// keeps these alive for the length of the menu's tracking loop.
@MainActor
final class MenuAction: NSObject {
    private let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// A URL field that still accepts Cut / Copy / Paste / Select All.
///
/// VortexFlow is an accessory app: it has no menu bar, so ⌘V is a key equivalent
/// with no Edit menu to land on. The field editor can type, but paste never arrives
/// unless the field claims those chords itself.
final class PinLinkField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command),
              !mods.contains(.option),
              !mods.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector
        switch key {
        case "v": action = #selector(NSText.paste(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        default:
            return super.performKeyEquivalent(with: event)
        }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}

/// A read-only field that records the next key combination pressed into it.
///
/// Not editable, so there is no field editor in the way and `keyDown` reaches the field
/// itself. Command combinations arrive as key equivalents and are claimed there.
final class ShortcutCaptureField: NSTextField {
    private(set) var captured: HotKeyShortcut?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isEditable = false
        isSelectable = false
        alignment = .center
        placeholderString = "Press a shortcut"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { record(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { record(event); return true }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let keyCode = UInt32(event.keyCode)
        captured = HotKeyShortcut(
            keyCode: keyCode,
            carbonModifiers: carbon,
            displayName: KeyNaming.description(keyCode: keyCode, carbonModifiers: carbon)
        )
        stringValue = captured?.displayName ?? ""
    }
}

extension RadialLayout {

    /// Radial gap between a tile and the seat above it — the same 8pt the ring uses between
    /// turns, so a second layer of pins reads as another turn, not as a stack.
    static let baseShortcutBandGap: CGFloat = 8
    /// How deep a pin tile wants to be.
    ///
    /// Capped so a deep seat leaves room for a second layer inward. Filling the whole
    /// crescent made the first five tiles tall and refused a sixth; 40pt is an icon with
    /// a little air, and under the three deepest seats it leaves a second 40pt behind.
    static let baseShortcutTileDepth: CGFloat = 40
    /// Shallowest tile that can still carry a 16pt favicon with a margin.
    static let minimumShortcutTileDepth: CGFloat = 24

    /// The first `count` pin tiles in the seam. Panel-content coordinates, top-left origin.
    ///
    /// Five or fewer fill the crescent — hub gap to the wedge above — so the first turn is
    /// one band of cards, not a short band with an empty ring reserved behind it. A sixth
    /// pin is what shrinks that turn and opens an inner one. The plus is not a tile; it
    /// lives in the leftover angular gap after the last first-turn card.
    func shortcutSeats(count: Int) -> [Seat] {
        guard count > 0, winding == .spiral else { return [] }
        let gap = Self.baseShortcutBandGap * scale
        let floor = firstRingRadius
        let margin = 4 * scale
        let cap = count > PinnedShortcut.firstLayerCount
        let first = firstLayerSeats(
            count: min(count, PinnedShortcut.firstLayerCount),
            capDepth: cap,
            gap: gap,
            floor: floor,
            margin: margin
        )
        guard count > PinnedShortcut.firstLayerCount else { return number(first) }
        let inner = innerLayerSeats(
            count: count - PinnedShortcut.firstLayerCount,
            under: first,
            gap: gap,
            floor: floor,
            margin: margin
        )
        return number(first + inner)
    }

    /// A small plus in the leftover seam after the last first-turn card — the gap that
    /// used to sit empty past the fifth tile. Not a sixth card and not a second turn.
    func shortcutPlusFrame(pinCount: Int) -> CGRect? {
        guard winding == .spiral, pinCount < PinnedShortcut.slotCount else { return nil }
        let firstLayer = min(pinCount, PinnedShortcut.firstLayerCount)
        let offset = Self.seatsPerTurn - 1 - firstLayer
        guard offset >= 1 else { return nil }
        let gap = Self.baseShortcutBandGap * scale
        let outer = innerRadius(atSeat: offset) - gap
        let inner = firstRingRadius
        let available = outer - inner
        guard available >= 16 else { return nil }
        let diameter = min(26 * scale, max(16, available * 0.65))
        let mid = seat(at: offset).midAngle
        let radius = (inner + outer) / 2
        return CGRect(
            x: centre.x + radius * CGFloat(cos(mid)) - diameter / 2,
            y: centre.y + radius * CGFloat(sin(mid)) - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    private func firstLayerSeats(
        count: Int, capDepth: Bool, gap: CGFloat, floor: CGFloat, margin: CGFloat
    ) -> [Seat] {
        var tiles: [Seat] = []
        for offset in stride(from: Self.seatsPerTurn - 1, through: 1, by: -1) {
            guard tiles.count < count else { break }
            let outer = innerRadius(atSeat: offset) - gap
            let available = outer - floor
            guard available >= Self.minimumShortcutTileDepth else { break }
            let depth = capDepth ? min(Self.baseShortcutTileDepth * scale, available) : available
            guard depth >= Self.minimumShortcutTileDepth else { break }
            let inner = outer - depth
            let angles = seat(at: offset)
            tiles.append(makeTile(
                start: angles.startAngle, end: angles.endAngle, inner: inner, outer: outer, margin: margin
            ))
        }
        return tiles
    }

    private func innerLayerSeats(
        count: Int, under outer: [Seat], gap: CGFloat, floor: CGFloat, margin: CGFloat
    ) -> [Seat] {
        var tiles: [Seat] = []
        for above in outer {
            guard tiles.count < count else { break }
            let ceiling = above.innerRadius - gap
            let available = ceiling - floor
            guard available >= Self.minimumShortcutTileDepth else { continue }
            let depth = min(Self.baseShortcutTileDepth * scale, available)
            guard depth >= Self.minimumShortcutTileDepth else { continue }
            tiles.append(makeTile(
                start: above.startAngle, end: above.endAngle,
                inner: ceiling - depth, outer: ceiling, margin: margin
            ))
        }
        return tiles
    }

    private func makeTile(
        start: Double, end: Double, inner: CGFloat, outer: CGFloat, margin: CGFloat
    ) -> Seat {
        Seat(
            offset: 0,
            startAngle: start,
            endAngle: end,
            innerRadius: inner,
            outerRadius: outer,
            contentFrame: tileContentFrame(start: start, end: end, inner: inner, outer: outer, margin: margin)
        )
    }

    private func number(_ tiles: [Seat]) -> [Seat] {
        tiles.enumerated().map { index, tile in
            Seat(
                offset: index,
                startAngle: tile.startAngle,
                endAngle: tile.endAngle,
                innerRadius: tile.innerRadius,
                outerRadius: tile.outerRadius,
                contentFrame: tile.contentFrame
            )
        }
    }

    /// The upright box a tile's icon and label live in.
    ///
    /// Sized the way a wedge's is — against the circle inscribed in the sector — because an
    /// upright box meets a sector at a different angle at every seat: at six o'clock its
    /// height runs radially, at nine it runs along the arc. The circle does not care.
    private func tileContentFrame(
        start: Double, end: Double, inner: CGFloat, outer: CGFloat, margin: CGFloat
    ) -> CGRect {
        let size = Self.contentSize(
            hubRadius: inner, ringThickness: outer - inner, margin: margin, preferredHeight: 64 * scale
        )
        let (width, height) = (size.width, size.height)
        let midAngle = (start + end) / 2
        let midRadius = (inner + outer) / 2
        return CGRect(
            x: centre.x + midRadius * CGFloat(cos(midAngle)) - width / 2,
            y: centre.y + midRadius * CGFloat(sin(midAngle)) - height / 2,
            width: width,
            height: height
        )
    }

    /// Which tile a content point falls in, by angle and radius.
    func shortcutSlot(atContentPoint point: CGPoint, count: Int) -> Int? {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let radius = (dx * dx + dy * dy).squareRoot()
        let angle = atan2(Double(dy), Double(dx))
        if let tile = shortcutSeats(count: count).first(where: {
            radius >= $0.innerRadius && radius <= $0.outerRadius
                && Self.angle(angle, isWithin: $0.startAngle, and: $0.endAngle)
        }) {
            return tile.offset
        }
        if let plus = shortcutPlusFrame(pinCount: count), plus.insetBy(dx: -4, dy: -4).contains(point) {
            return count
        }
        return nil
    }
}
