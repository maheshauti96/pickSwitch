import CoreGraphics
import Foundation
import Testing
@testable import VortexflowCore

@Suite("Pinned shortcut slots")
struct PinnedShortcutTests {

    private func layout(_ winding: RadialLayout.Winding, cards: Int) -> RadialLayout {
        RadialLayout(
            winding: winding,
            cardCount: cards,
            selectedIndex: 0,
            availableContentWidth: 1400,
            availableContentHeight: 860
        )
    }

    private func point(_ radial: RadialLayout, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: radial.centre.x + radius * CGFloat(cos(angle)), y: radial.centre.y + radius * CGFloat(sin(angle)))
    }

    @Test("tiles sit in the seam: clear of the hub and of every wedge", arguments: [8, 12, 20, 25])
    func tilesClearHubAndWedges(cards: Int) {
        let radial = layout(.spiral, cards: cards)
        let tiles = radial.shortcutSeats(count: PinnedShortcut.slotCount)
        #expect(tiles.count >= 8 && tiles.count <= PinnedShortcut.slotCount)

        for tile in tiles {
            #expect(tile.innerRadius > radial.hubRadius)
            // Walk the tile's outline — both arcs and both rays — and land on no wedge.
            for i in 0...12 {
                let angle = tile.startAngle + (tile.endAngle - tile.startAngle) * Double(i) / 12
                for radius in [tile.innerRadius, tile.outerRadius] {
                    let p = point(radial, radius: radius, angle: angle)
                    #expect(radial.seatOffset(atContentPoint: p) == nil, "tile \(tile.offset) touches a wedge at \(p)")
                }
                let radius = tile.innerRadius + (tile.outerRadius - tile.innerRadius) * CGFloat(i) / 12
                for angle in [tile.startAngle, tile.endAngle] {
                    let p = point(radial, radius: radius, angle: angle)
                    #expect(radial.seatOffset(atContentPoint: p) == nil, "tile \(tile.offset) touches a wedge at \(p)")
                }
            }
            // The content box is inside the tile.
            for corner in [CGPoint(x: tile.contentFrame.minX, y: tile.contentFrame.minY),
                           CGPoint(x: tile.contentFrame.maxX, y: tile.contentFrame.minY),
                           CGPoint(x: tile.contentFrame.minX, y: tile.contentFrame.maxY),
                           CGPoint(x: tile.contentFrame.maxX, y: tile.contentFrame.maxY)] {
                let dx = corner.x - radial.centre.x, dy = corner.y - radial.centre.y
                let r = (dx * dx + dy * dy).squareRoot()
                #expect(r >= tile.innerRadius - 0.01 && r <= tile.outerRadius + 0.01)
                #expect(RadialLayout.angle(atan2(Double(dy), Double(dx)), isWithin: tile.startAngle, and: tile.endAngle))
            }
        }
    }

    @Test("the outer turn shares its angles with the wedge above it and sits one hub gap beneath it")
    func outerTurnSharesTheRingsGrid() {
        let radial = layout(.spiral, cards: 20)
        let gap = RadialLayout.baseShortcutBandGap * radial.scale
        let outer = radial.shortcutSeats(count: PinnedShortcut.slotCount).filter { tile in
            (1..<RadialLayout.seatsPerTurn).contains { offset in
                abs(radial.innerRadius(atSeat: offset) - tile.outerRadius - gap) < 0.01
            }
        }
        #expect(outer.count >= 5)
        for tile in outer {
            let above = (1..<RadialLayout.seatsPerTurn).map { radial.seat(at: $0) }.first {
                abs($0.innerRadius - tile.outerRadius - gap) < 0.01
            }
            #expect(above != nil)
            #expect(tile.startAngle == above?.startAngle)
            #expect(tile.endAngle == above?.endAngle)
        }
    }

    @Test("five or fewer fill the crescent on one turn; a sixth is what opens the inner turn")
    func secondTurnWaitsForASixthPin() {
        let radial = layout(.spiral, cards: 20)
        let four = radial.shortcutSeats(count: 4)
        let five = radial.shortcutSeats(count: 5)
        let six = radial.shortcutSeats(count: 6)
        #expect(four.count == 4)
        #expect(five.count == 5)
        #expect(Set(four.map(\.startAngle)).count == 4)
        #expect(Set(five.map(\.startAngle)).count == 5)
        #expect(five.allSatisfy { abs($0.innerRadius - radial.firstRingRadius) < 0.01 })
        #expect(six.count == 6)
        #expect(Set(six.map(\.startAngle)).count < six.count)
        // Capping the first turn to make room is a sixth-pin change; five stay tall.
        #expect(six[0].innerRadius > five[0].innerRadius)
    }

    @Test("the plus sits in the leftover gap after the last first-turn card, not on a second turn")
    func plusSitsInTheGapAfterTheLastCard() {
        let radial = layout(.spiral, cards: 20)
        let five = radial.shortcutSeats(count: 5)
        let plus = radial.shortcutPlusFrame(pinCount: 5)
        #expect(plus != nil)
        let last = five[4]
        let plusAngle = atan2(Double(plus!.midY - radial.centre.y), Double(plus!.midX - radial.centre.x))
        #expect(!RadialLayout.angle(plusAngle, isWithin: last.startAngle, and: last.endAngle))
        #expect(radial.shortcutSeats(count: 4).count == 4)
        #expect(radial.shortcutPlusFrame(pinCount: 4) != nil)
        // A click on the plus appends, and does not invent a sixth tile.
        #expect(radial.shortcutSlot(atContentPoint: CGPoint(x: plus!.midX, y: plus!.midY), count: 5) == 5)
    }

    @Test("a second turn stacks under the deepest seats and does not overlap the first")
    func secondTurnStacksInward() {
        let radial = layout(.spiral, cards: 20)
        let tiles = radial.shortcutSeats(count: PinnedShortcut.slotCount)
        let inner = tiles.filter { tile in
            tiles.contains {
                $0.offset != tile.offset
                    && $0.startAngle == tile.startAngle
                    && $0.innerRadius > tile.outerRadius
            }
        }
        #expect(inner.count >= 2)
        let gap = RadialLayout.baseShortcutBandGap * radial.scale
        for tile in inner {
            let above = tiles.first { $0.startAngle == tile.startAngle && $0.innerRadius > tile.outerRadius }!
            #expect(abs(above.innerRadius - tile.outerRadius - gap) < 0.01)
            #expect(tile.innerRadius >= radial.firstRingRadius - 0.01)
        }
    }

    @Test("the run starts at the deepest seat beside twelve o'clock and a short run is its head")
    func outerTurnStartsAtTheTop() {
        let radial = layout(.spiral, cards: 20)
        let tiles = radial.shortcutSeats(count: 5)
        #expect(tiles.last!.outerRadius - tiles.last!.innerRadius >= RadialLayout.minimumShortcutTileDepth)
        // First tile ends at twelve o'clock, less the wedge gap; its content box is upper-left.
        #expect(abs(tiles[0].endAngle - (RadialLayout.startAngle + 2 * .pi - RadialLayout.wedgeGap / 2)) < 1e-9)
        #expect(tiles[0].contentFrame.midX < radial.centre.x && tiles[0].contentFrame.midY < radial.centre.y)
        // A short run is the head of the five-card turn: adding a pin moves nothing.
        #expect(Array(tiles.prefix(3)) == radial.shortcutSeats(count: 3))
    }

    @Test("the circular winding has no seam and shows no tiles")
    func circularHasNoTiles() {
        #expect(layout(.circular, cards: 12).shortcutSeats(count: PinnedShortcut.slotCount).isEmpty)
        #expect(layout(.circular, cards: 5).shortcutSeats(count: PinnedShortcut.slotCount).isEmpty)
    }

    @Test("every pin shows, plus one empty slot while there is room")
    func visibleCount() {
        #expect(PinnedShortcut.visibleSlotCount(forPins: 0) == 0)
        #expect(PinnedShortcut.visibleSlotCount(forPins: 2) == 2)
        #expect(PinnedShortcut.visibleSlotCount(forPins: 5) == 5)
        #expect(PinnedShortcut.visibleSlotCount(forPins: 6) == 6)
        #expect(PinnedShortcut.visibleSlotCount(forPins: PinnedShortcut.slotCount) == PinnedShortcut.slotCount)
    }

    @Test("the layout resolves a click on a slot before the hub claims it")
    func slotWinsHitTest() {
        let overlay = OverlayLayout(
            style: .spiral,
            cardCount: 20,
            selectedIndex: 0,
            availableContentWidth: 1400,
            availableContentHeight: 860,
            shortcutSlotCount: 3
        )
        #expect(overlay.shortcutSlots.count == 3)
        let box = overlay.shortcutSlots[2].contentFrame
        let appKitPoint = CGPoint(x: box.midX, y: overlay.panelSize.height - box.midY)
        #expect(overlay.target(atPanelPoint: appKitPoint, scrollOffset: 0, selectedScale: 1) == .shortcutSlot(2))
        // The hub is still the hub.
        let hub = overlay.radialHubFrame
        let hubPoint = CGPoint(x: hub.midX, y: overlay.panelSize.height - hub.midY)
        #expect(overlay.target(atPanelPoint: hubPoint, scrollOffset: 0, selectedScale: 1) == .confirmSelection)
    }

    @Test("pins round-trip through defaults in order, and the old null-padded format still loads")
    func persistenceRoundTrip() throws {
        let defaults = UserDefaults(suiteName: "PinnedShortcutTests-\(UUID().uuidString)")!
        let pins: [PinnedShortcut] = [
            .link(URL(string: "https://example.com")!),
            .app(URL(fileURLWithPath: "/Applications/Safari.app")),
            .keys(.hyperSpace),
        ]
        PinnedShortcut.save(pins, to: defaults)
        #expect(PinnedShortcut.load(from: defaults) == pins)

        let legacy: [PinnedShortcut?] = [nil, pins[0], nil, pins[2], nil, nil]
        defaults.set(try JSONEncoder().encode(legacy), forKey: PinnedShortcut.defaultsKey)
        #expect(PinnedShortcut.load(from: defaults) == [pins[0], pins[2]])
        #expect(PinnedShortcut.load(from: .init(suiteName: "empty-\(UUID())")!).isEmpty)
    }
}
