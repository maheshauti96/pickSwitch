import AppKit

/// Builds the browser-window identity shown throughout the overlay.
///
/// The browser application leads in the lower-left, and the verified active-site icon sits behind
/// it in the upper-right: the window is a browser window first, and the site says which one.
/// The two are close to the same size, so that the site is identifiable rather than merely present.
/// Returning one scalable `NSImage` keeps every existing icon renderer — cards, rows, previews,
/// radial wedges and transition ghosts — visually consistent without changing their geometry.
enum BrowserWindowIcon {

    private static let canvas = NSSize(width: 256, height: 256)

    /// The icon in front, anchored to the lower-left corner.
    static let foregroundScale: CGFloat = 0.64

    /// The icon behind, anchored to the upper-right corner.
    ///
    /// Larger than it was, and the front icon is smaller, because the first version measured
    /// generously and read as almost nothing. At 0.78 in front and 0.64 behind, the site icon's
    /// *centre* landed at 174 of 256 while the browser covered everything below 200 — so the part
    /// that identifies a site was underneath, and only an L-shaped sliver of its edges showed. More
    /// than half its area was technically visible, which is why the numbers looked reasonable and
    /// the result did not.
    ///
    /// The rule that actually matters is `centreIsClearOfForeground` below: a recognisable icon is
    /// its middle, not its area.
    static let backgroundScale: CGFloat = 0.66

    /// Whether the icon behind has its centre outside the icon in front.
    ///
    /// Encoded rather than left to the two numbers above, because getting it wrong produces a
    /// composition that looks fine in a diff and illegible on screen. A test holds it.
    static var centreIsClearOfForeground: Bool {
        1 - backgroundScale / 2 > foregroundScale
    }

    // MARK: - Backing plate

    /// Off-white rather than white, so the plate reads as a surface instead of a hole.
    private static let plateWhite: CGFloat = 0.94
    /// Corner radius as a fraction of the plate's side.
    private static let plateCornerFraction: CGFloat = 0.22

    /// Below this share of opaque pixels, the icon is a glyph with transparent surround rather
    /// than artwork that fills its own square.
    private static let maximumPlatelessCoverage = 0.92
    /// Above this mean luminance the glyph is light enough to read on the overlay's own dark
    /// container, and a light plate would hurt rather than help.
    private static let maximumPlatelessLuminance = 0.42
    /// Pixels per side of the coverage sample. Cheap, and the question is about broad areas.
    private static let plateSampleSide = 24
    /// Below this, a pixel is transparent surround rather than glyph.
    private static let plateMinimumAlpha = 0.5

    /// Whether `siteIcon` needs an opaque plate behind it to be visible.
    ///
    /// Favicons are drawn for a browser tab strip, which is light in the default macOS
    /// appearance, so a great many of them are a dark glyph on transparency: GitHub's mark is the
    /// obvious one. Composited straight onto the overlay's dark container that glyph disappears
    /// entirely, and no amount of resizing fixes it — the version before this was measured
    /// carefully and still rendered GitHub as a faint smudge. Sites that would otherwise have the
    /// same problem solve it themselves by shipping an opaque background in the icon: X's black
    /// square, Hacker News' orange, Wikipedia's white. This gives that same treatment to the ones
    /// that do not.
    ///
    /// Both conditions are required. Low coverage alone would plate a white-on-transparent glyph,
    /// which already reads on a dark container and would be destroyed by a light backing.
    static func siteIconNeedsPlate(_ siteIcon: NSImage) -> Bool {
        guard let sample = luminanceSample(of: siteIcon) else { return false }
        return sample.coverage < maximumPlatelessCoverage
            && sample.luminance <= maximumPlatelessLuminance
    }

    /// The share of `image` that is opaque, and the mean perceived luminance of that part.
    private static func luminanceSample(
        of image: NSImage
    ) -> (coverage: Double, luminance: Double)? {
        let side = plateSampleSide
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .medium
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        guard let raw = context.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var opaqueCount = 0
        var luminanceTotal = 0.0
        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= plateMinimumAlpha else { continue }

            // Premultiplied, so recover the original channels before weighting them.
            let red = min(1, Double(pixels[offset]) / 255 / alpha)
            let green = min(1, Double(pixels[offset + 1]) / 255 / alpha)
            let blue = min(1, Double(pixels[offset + 2]) / 255 / alpha)

            opaqueCount += 1
            luminanceTotal += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }

        guard opaqueCount > 0 else { return nil }
        return (
            coverage: Double(opaqueCount) / Double(side * side),
            luminance: luminanceTotal / Double(opaqueCount)
        )
    }

    static func layered(siteIcon: NSImage, browserIcon: NSImage) -> NSImage {
        let needsPlate = siteIconNeedsPlate(siteIcon)

        let image = NSImage(size: canvas, flipped: false) { bounds in
            let side = min(bounds.width, bounds.height)
            guard side > 0 else { return false }

            NSGraphicsContext.current?.imageInterpolation = .high

            // Painted back to front: the site icon first, then the browser over it.
            let backgroundSide = side * backgroundScale
            let backgroundRect = NSRect(
                x: bounds.maxX - backgroundSide,
                y: bounds.maxY - backgroundSide,
                width: backgroundSide,
                height: backgroundSide
            )

            if needsPlate {
                NSColor(calibratedWhite: plateWhite, alpha: 1).setFill()
                NSBezierPath(
                    roundedRect: backgroundRect,
                    xRadius: backgroundSide * plateCornerFraction,
                    yRadius: backgroundSide * plateCornerFraction
                ).fill()
            }

            siteIcon.draw(
                in: backgroundRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )

            let foregroundSide = side * foregroundScale
            browserIcon.draw(
                in: NSRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: foregroundSide,
                    height: foregroundSide
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            return true
        }
        image.isTemplate = false
        return image
    }
}
