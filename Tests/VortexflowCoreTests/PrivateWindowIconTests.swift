import AppKit
import Testing
@testable import VortexflowCore

/// The private-browsing marker, checked by looking at the pixels.
///
/// Worth testing this way rather than by asserting on constants. The marker's whole job is to be
/// noticed, and the version this replaced satisfied every structural expectation you could write
/// about it — it existed, it had a size, it was in the view tree — while being invisible in practice.
/// So these tests render the composite and read it back.
@Suite("Private window icon")
struct PrivateWindowIconTests {

    /// A white square, so anything the badge draws is unambiguously the badge.
    private static func whiteIcon(side: CGFloat = 128) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return image
    }

    /// Mean luminance and alpha of a fractional sub-rectangle of `image`, in unit coordinates with
    /// the origin at the bottom-left, matching the AppKit rectangles the icon is drawn with.
    ///
    /// The row index is flipped on the way in. Measured, not assumed: rendering a white icon and
    /// reading back the four quadrants put the badge in the *high* row indices, so row zero is the
    /// top of the buffer while `y` here is measured from the bottom.
    private static func sample(
        _ image: NSImage,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) throws -> (luminance: Double, alpha: Double) {
        let side = 128
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        let cgImage = try #require(
            image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        )
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        let raw = try #require(context.data)
        let pixels = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)

        let minX = max(0, Int(x * Double(side)))
        let maxX = min(side, Int((x + width) * Double(side)))
        let minY = max(0, side - Int((y + height) * Double(side)))
        let maxY = min(side, side - Int(y * Double(side)))

        var luminanceTotal = 0.0
        var alphaTotal = 0.0
        var count = 0
        for row in minY..<maxY {
            for column in minX..<maxX {
                let offset = (row * side + column) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                let red = Double(pixels[offset]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let blue = Double(pixels[offset + 2]) / 255
                luminanceTotal += 0.2126 * red + 0.7152 * green + 0.0722 * blue
                alphaTotal += alpha
                count += 1
            }
        }
        let divisor = Double(max(count, 1))
        return (luminanceTotal / divisor, alphaTotal / divisor)
    }

    @Test("the badge darkens the lower-trailing corner of a white icon")
    func badgeIsDrawnInTheLowerTrailingCorner() throws {
        let badged = PrivateWindowIcon.badged(Self.whiteIcon())

        // The badge's own middle, where the dark disc is.
        let corner = try Self.sample(badged, x: 0.62, y: 0.06, width: 0.3, height: 0.3)
        #expect(corner.luminance < 0.5, "the badge should darken its corner, got \(corner.luminance)")
        #expect(corner.alpha > 0.9)
    }

    @Test("the badge leaves the rest of the icon alone")
    func badgeDoesNotCoverTheIcon() throws {
        let badged = PrivateWindowIcon.badged(Self.whiteIcon())

        // Upper-leading half, well clear of a lower-trailing badge.
        let body = try Self.sample(badged, x: 0.0, y: 0.55, width: 0.5, height: 0.4)
        #expect(body.luminance > 0.9, "the icon should survive, got \(body.luminance)")
    }

    /// The reason the size was chosen: the smallest icon any arrangement draws is around 22 points,
    /// and the marker has to survive that. Checked as a share of the icon rather than in points,
    /// because every renderer scales the same composite.
    @Test("the badge is a large enough share of the icon to survive being scaled down")
    func badgeIsLargeRelativeToTheIcon() throws {
        let badged = PrivateWindowIcon.badged(Self.whiteIcon())

        // Across the full bottom-trailing quadrant, a majority of pixels should be badge, not icon.
        let quadrant = try Self.sample(badged, x: 0.5, y: 0.0, width: 0.5, height: 0.5)
        #expect(quadrant.luminance < 0.75, "badge too small in its quadrant: \(quadrant.luminance)")
    }

    @Test("the composite is square, so every renderer can size it like any other icon")
    func compositeIsSquare() {
        let badged = PrivateWindowIcon.badged(Self.whiteIcon())
        #expect(badged.size.width == badged.size.height)
        #expect(badged.size.width > 0)
    }
}
