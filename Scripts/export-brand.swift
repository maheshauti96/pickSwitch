#!/usr/bin/env swift
import AppKit
import Foundation

// Mechanical packaging of approved image assets, never a procedural logo drawing.
// PNG masters are the source of truth; SVG files are compatibility wrappers.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Scripts/export-brand.swift <repository-root>")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let imageRoot = root.appendingPathComponent("site/img", isDirectory: true)
let pngRoot = imageRoot.appendingPathComponent("brand/png", isDirectory: true)
let svgRoot = imageRoot.appendingPathComponent("brand/svg", isDirectory: true)
let ink = NSColor(srgbRed: 32/255, green: 30/255, blue: 29/255, alpha: 1)
let paper = NSColor(srgbRed: 246/255, green: 244/255, blue: 241/255, alpha: 1)

func write(_ data: Data, _ url: URL) throws { try data.write(to: url, options: .atomic) }
func write(_ text: String, _ url: URL) throws { try write(Data(text.utf8), url) }

func loadMaster(_ name: String) throws -> NSImage {
    let data = try Data(contentsOf: pngRoot.appendingPathComponent(name))
    guard let rep = NSBitmapImageRep(data: data), rep.pixelsWide == 1024,
          rep.pixelsHigh == 1024, rep.hasAlpha,
          let corner = rep.colorAt(x: 0, y: 0), corner.alphaComponent < 0.01,
          let image = NSImage(data: data), image.isValid else {
        fatalError("\(name) must be a valid 1024-square PNG with transparent corners")
    }
    return image
}

func png(width: Int, height: Int, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
        pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill(using: .copy)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func square(_ image: NSImage, size: Int, tint: NSColor? = nil) -> Data {
    png(width: size, height: size) {
        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        if let tint { tint.setFill(); bounds.fill(using: .sourceIn) }
    }
}

func svg(_ data: Data, width: Int, height: Int) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
    <!-- Compatibility wrapper around approved raster artwork, not vector outlines. -->
    <image width="\(width)" height="\(height)" href="data:image/png;base64,\(data.base64EncodedString())"/>
    </svg>
    """
}

let mark = try loadMaster("vortexflow-mark-1024.png")
let appIcon = try loadMaster("app-icon-1024.png")
let mark512 = square(mark, size: 512)
let mark256 = square(mark, size: 256)
let monoInk = square(mark, size: 512, tint: ink)
let monoPaper = square(mark, size: 512, tint: paper)
try write(mark512, pngRoot.appendingPathComponent("vortexflow-mark-512.png"))
try write(mark256, imageRoot.appendingPathComponent("mark.png"))
try write(monoInk, pngRoot.appendingPathComponent("vortexflow-mark-mono-ink.png"))
try write(monoPaper, pngRoot.appendingPathComponent("vortexflow-mark-mono-paper.png"))
for name in ["vortexflow-mark.svg", "vortexflow-mark-pastel.svg", "vortexflow-mark-reverse.svg"] {
    try write(svg(mark512, width: 512, height: 512), svgRoot.appendingPathComponent(name))
}
try write(svg(monoInk, width: 512, height: 512), svgRoot.appendingPathComponent("vortexflow-mark-mono-ink.svg"))
try write(svg(monoPaper, width: 512, height: 512), svgRoot.appendingPathComponent("vortexflow-mark-mono-paper.svg"))
try write(svg(mark256, width: 64, height: 64), imageRoot.appendingPathComponent("mark.svg"))
for name in ["app-icon.png", "icon.png"] {
    try write(square(appIcon, size: 256), imageRoot.appendingPathComponent(name))
}
let touch = square(appIcon, size: 180)
try write(touch, imageRoot.appendingPathComponent("apple-touch.png"))
try write(touch, pngRoot.appendingPathComponent("apple-touch-icon.png"))
try write(svg(square(appIcon, size: 512), width: 512, height: 512), svgRoot.appendingPathComponent("vortexflow-appicon.svg"))

var iconFrames: [(Int, Data)] = []
for size in [16, 32, 48] {
    let data = square(mark, size: size)
    iconFrames.append((size, data))
    try write(data, pngRoot.appendingPathComponent("favicon-\(size).png"))
    try write(data, imageRoot.appendingPathComponent("favicon-\(size).png"))
}
let faviconSVG = svg(square(mark, size: 64), width: 64, height: 64)
try write(faviconSVG, imageRoot.appendingPathComponent("favicon.svg"))
try write(faviconSVG, svgRoot.appendingPathComponent("favicon.svg"))
func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 255), UInt8(value >> 8)] }
func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 255) } }
var ico = Data([0, 0, 1, 0] + le16(UInt16(iconFrames.count)))
var offset = UInt32(6 + iconFrames.count * 16)
for (size, data) in iconFrames {
    ico.append(contentsOf: [UInt8(size), UInt8(size), 0, 0] + le16(1) + le16(32)
        + le32(UInt32(data.count)) + le32(offset))
    offset += UInt32(data.count)
}
for (_, data) in iconFrames { ico.append(data) }
try write(ico, root.appendingPathComponent("site/favicon.ico"))

// The editable wordmark text uses the website's system sans-serif font.
func lockup(color: NSColor, includeMark: Bool = true) -> (Data, Int, Int) {
    let text = NSAttributedString(string: "VortexFlow", attributes: [
        .font: NSFont.systemFont(ofSize: 128, weight: .semibold), .foregroundColor: color])
    let x: CGFloat = includeMark ? 264 : 16
    let width = Int(ceil(x + text.size().width + 16))
    let height = 256
    let data = png(width: width, height: height) {
        if includeMark { mark.draw(in: NSRect(x: 8, y: 8, width: 240, height: 240)) }
        text.draw(at: NSPoint(x: x, y: (256 - text.size().height) / 2))
    }
    return (data, width, height)
}
let (lock, lockWidth, lockHeight) = lockup(color: ink)
let (reverse, _, _) = lockup(color: paper)
try write(lock, pngRoot.appendingPathComponent("vortexflow-lockup-2x.png"))
try write(reverse, pngRoot.appendingPathComponent("vortexflow-lockup-reverse-2x.png"))
try write(svg(lock, width: lockWidth, height: lockHeight), imageRoot.appendingPathComponent("lockup.svg"))
try write(svg(lock, width: lockWidth, height: lockHeight), svgRoot.appendingPathComponent("vortexflow-lockup-horizontal.svg"))
try write(svg(reverse, width: lockWidth, height: lockHeight), svgRoot.appendingPathComponent("vortexflow-lockup-horizontal-reverse.svg"))
let (word, wordWidth, wordHeight) = lockup(color: ink, includeMark: false)
try write(svg(word, width: wordWidth, height: wordHeight), svgRoot.appendingPathComponent("vortexflow-wordmark.svg"))

// Sharing card: approved homepage copy and actual mark, not a drawn substitute.
let og = png(width: 1200, height: 630) {
    paper.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
    mark.draw(in: NSRect(x: 790, y: 140, width: 345, height: 345))
    mark.draw(in: NSRect(x: 76, y: 512, width: 44, height: 44))
    NSAttributedString(string: "VortexFlow", attributes: [
        .font: NSFont.systemFont(ofSize: 29, weight: .semibold), .foregroundColor: ink
    ]).draw(at: NSPoint(x: 134, y: 516))
    let sage = NSColor(srgbRed: 73/255, green: 119/255, blue: 103/255, alpha: 1)
    for (copy, y, color) in [("Find the right", 359.0, ink), ("window.", 281.0, ink),
                           ("Stay in your flow.", 191.0, sage)] {
        NSAttributedString(string: copy, attributes: [
            .font: NSFont.systemFont(ofSize: 65, weight: .semibold), .foregroundColor: color
        ]).draw(at: NSPoint(x: 80, y: y))
    }
    NSAttributedString(string: "Windows, tabs, and favorites. Within reach.", attributes: [
        .font: NSFont.systemFont(ofSize: 22), .foregroundColor: ink.withAlphaComponent(0.72)
    ]).draw(at: NSPoint(x: 84, y: 116))
}
try write(og, pngRoot.appendingPathComponent("og-image.png"))
try write(og, imageRoot.appendingPathComponent("og-image.png"))
try write(svg(og, width: 1200, height: 630), svgRoot.appendingPathComponent("og-image.svg"))
print("Exported approved logos, lockups, favicons and sharing card.")
