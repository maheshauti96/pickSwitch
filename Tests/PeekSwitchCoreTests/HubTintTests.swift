import AppKit
import SwiftUI
import Testing
@testable import PeekSwitchCore

/// The spiral's middle takes the colour of the window currently under the pointer.
///
/// Tested by rendering the real overlay and reading the pixels in the disc, rather than by checking
/// which palette function is called. The wiring is the part that breaks: the hub's fill is one
/// modifier among several on a view that also animates its entrance and its caption, and a fill that
/// silently stopped tracking selection would leave every other assertion about the hub passing.
///
/// Icons are synthetic solid colours, so the expected hue is known and the test does not depend on
/// which applications happen to be installed.
@Suite("Hub tint")
@MainActor
struct HubTintTests {

    private static func solidIcon(_ colour: NSColor) -> NSImage {
        let side = 32.0
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        colour.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return image
    }

    private static func state(selected: Int) -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1400
        state.availableContentHeight = 860
        state.layoutStyle = .spiral
        state.displayLayout = DisplayLayout(displays: [
            DisplayInfo(
                number: 1,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                isBuiltIn: true,
                name: "Built-in"
            )
        ])
        let palette: [(String, NSColor)] = [
            ("Scarlet", .systemRed),
            ("Emerald", .systemGreen)
        ]
        state.load(
            entries: palette.enumerated().map { index, app in
                WindowEntry(
                    windowID: CGWindowID(900 + index),
                    processID: pid_t(index + 1),
                    applicationName: app.0,
                    applicationIcon: solidIcon(app.1),
                    title: "Window of \(app.0)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: selected
        )
        return state
    }

    /// Mean colour of a patch inside the hub disc, clear of the caption text.
    ///
    /// Sampled below the middle: the caption occupies the centre band, and averaging over text would
    /// measure the type as much as the fill.
    private static func hubFill(selected: Int) throws -> NSColor {
        let state = state(selected: selected)
        let hosting = NSHostingView(rootView: OverlayView(state: state, hoveredIndex: selected))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: state.layout.panelSize)
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = state.layout.radialHubFrame
        // A patch between the caption and the disc's lower edge, inset enough to stay off the border.
        let patch = NSRect(
            x: hub.midX - hub.width * 0.08,
            y: hub.midY + hub.height * 0.32,
            width: hub.width * 0.16,
            height: hub.height * 0.06
        )

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0
        // `rep` is in pixels, the layout in points; scale between them rather than assuming 1:1.
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)
        for x in stride(from: patch.minX, to: patch.maxX, by: 1) {
            for y in stride(from: patch.minY, to: patch.maxY, by: 1) {
                guard let colour = rep.colorAt(
                    x: Int(Double(x) * scaleX),
                    y: Int(Double(y) * scaleY)
                )?.usingColorSpace(.sRGB) else { continue }
                red += Double(colour.redComponent)
                green += Double(colour.greenComponent)
                blue += Double(colour.blueComponent)
                count += 1
            }
        }
        try #require(count > 0, "sampled no pixels inside the hub")
        return NSColor(
            srgbRed: CGFloat(red / count),
            green: CGFloat(green / count),
            blue: CGFloat(blue / count),
            alpha: 1
        )
    }

    @Test("the hub leans toward the selected window's own hue")
    func hubTakesTheSelectedWindowsHue() throws {
        let onRed = try Self.hubFill(selected: 0)
        let onGreen = try Self.hubFill(selected: 1)

        // Against a red icon the disc must be redder than it is against a green one, and vice versa.
        // Stated as a comparison between the two rather than as absolute values, because the palette
        // owns how far the fill travels toward a hue and is free to change that.
        #expect(
            onRed.redComponent > onGreen.redComponent,
            "red-selected hub \(onRed.redComponent) vs green-selected \(onGreen.redComponent)"
        )
        #expect(
            onGreen.greenComponent > onRed.greenComponent,
            "green-selected hub \(onGreen.greenComponent) vs red-selected \(onRed.greenComponent)"
        )
    }

    /// The two must be far enough apart to be seen, not merely different in the last bit.
    @Test("the two hub colours are visibly different")
    func hubColoursAreDistinguishable() throws {
        let onRed = try Self.hubFill(selected: 0)
        let onGreen = try Self.hubFill(selected: 1)

        let distance = abs(onRed.redComponent - onGreen.redComponent)
            + abs(onRed.greenComponent - onGreen.greenComponent)
            + abs(onRed.blueComponent - onGreen.blueComponent)
        #expect(distance > 0.06, "hub colours are too close to tell apart: \(distance)")
    }
}
