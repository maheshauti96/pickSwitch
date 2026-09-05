import AppKit
import SwiftUI
import Testing
@testable import VortexflowCore

@Suite("Rendered hub motion")
@MainActor
struct HubMotionRenderingTests {
    private func render(time: TimeInterval, reduced: Bool = false, visible: Bool = true) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: ZStack {
            Color.black
            HubRing(frame: CGRect(x: 50, y: 50, width: 180, height: 180),
                ambience: .cyan, angle: 0, isRevealed: true, reduceMotion: reduced, isVisible: visible)
            Text("Window title").font(.system(size: 13)).foregroundStyle(.white)
                .position(x: 140, y: 140)
        }.environment(\.colorScheme, .dark).environment(\.hubMotionTime, time)
            .frame(width: 280, height: 280))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(x: 0, y: 0, width: 280, height: 280)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    private func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, rim: Bool) throws -> Double {
        let scale = Double(a.pixelsWide) / 280
        var delta = 0.0, count = 0.0
        for x in stride(from: 25.0, through: 255, by: 2) {
            for y in stride(from: 25.0, through: 255, by: 2) {
                let radius = hypot(x - 140, y - 140)
                guard rim ? (65...105).contains(radius) : radius < 45 else { continue }
                let first = try #require(a.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
                let second = try #require(b.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
                delta += abs(first.redComponent - second.redComponent)
                    + abs(first.greenComponent - second.greenComponent)
                    + abs(first.blueComponent - second.blueComponent)
                count += 3
            }
        }
        return delta / count
    }

    @Test("The native rim moves while its caption pixels remain still")
    func animatedRimAndStillCaption() throws {
        let first = try render(time: 0)
        let second = try render(time: 1.1)
        #expect(try difference(first, second, rim: true) > 0.015)
        #expect(try difference(first, second, rim: false) < 0.002)
    }

    @Test("Reduce Motion and hidden panels do not change between frames")
    func staticFallbacks() throws {
        for (reduced, visible) in [(true, true), (false, false)] {
            let first = try render(time: 0, reduced: reduced, visible: visible)
            let second = try render(time: 1.1, reduced: reduced, visible: visible)
            #expect(try difference(first, second, rim: true) < 0.001)
        }
    }
}
