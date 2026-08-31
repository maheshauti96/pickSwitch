import AppKit
import Testing
@testable import VortexflowCore

/// The brand mark has to load from the resource bundle. The status item is the
/// only permanent affordance, and a missing image once made it vanish.
@Suite("Brand images")
struct BrandImageTests {

    @Test("The colour mark loads")
    func markLoads() {
        let image = BrandImage.mark()
        #expect(image != nil)
        #expect(image?.isValid == true)
        #expect(image?.isTemplate == false)
    }

    @Test("The window mark is a ring on a clear field, not a plated squircle")
    func markHasTransparentField() {
        guard let image = BrandImage.mark(),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff)
        else {
            Issue.record("colour mark did not load")
            return
        }

        let maxX = CGFloat(representation.pixelsWide - 1)
        let maxY = CGFloat(representation.pixelsHigh - 1)
        #expect(representation.hasAlpha, "a white plate would sit on the sidebar")
        #expect(alpha(at: .zero, in: representation) < 0.05)
        #expect(
            alpha(at: CGPoint(x: maxX / 2, y: maxY / 2), in: representation) < 0.05,
            "the hub should stay hollow"
        )
    }

    @Test("The menu bar icon is the colour mark at 18 pt")
    func menuBarMarkIsColourIcon() {
        let image = BrandImage.menuBarMark()
        #expect(image != nil)
        #expect(image?.isTemplate == false)
        #expect(image?.size.width == BrandImage.menuBarPointSize)
        #expect(image?.size.height == BrandImage.menuBarPointSize)
    }

    @Test("The status item prefers the brand mark over a generic symbol")
    func statusItemUsesBrandMark() {
        let image = BrandImage.statusItemImage(hasWarning: false)
        let mark = BrandImage.menuBarMark()
        #expect(image != nil)
        #expect(mark != nil)
        #expect(image?.size == mark?.size)
        #expect(image?.isTemplate == false)
    }

    @Test("A warning does not replace the mark with a different image")
    func warningKeepsTheMark() {
        let normal = BrandImage.statusItemImage(hasWarning: false)
        let warning = BrandImage.statusItemImage(hasWarning: true)
        #expect(normal != nil)
        #expect(warning != nil)
        #expect(normal?.size == warning?.size)
    }

    @Test("The menu bar icon is a ring on a clear field, not a plated squircle")
    func menuBarMarkHasTransparentField() {
        guard let image = BrandImage.menuBarMark(),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff)
        else {
            Issue.record("menu bar mark did not load")
            return
        }

        let maxX = CGFloat(representation.pixelsWide - 1)
        let maxY = CGFloat(representation.pixelsHigh - 1)
        #expect(representation.hasAlpha, "a plate with no alpha fills the status item")
        #expect(alpha(at: .zero, in: representation) < 0.05)
        #expect(alpha(at: CGPoint(x: maxX, y: 0), in: representation) < 0.05)
        #expect(alpha(at: CGPoint(x: maxX, y: maxY), in: representation) < 0.05)
        #expect(
            alpha(at: CGPoint(x: maxX / 2, y: maxY / 2), in: representation) < 0.05,
            "the hub should stay hollow"
        )
    }

    private func alpha(at point: CGPoint, in representation: NSBitmapImageRep) -> CGFloat {
        var alpha: CGFloat = 1
        representation.colorAt(x: Int(point.x), y: Int(point.y))?
            .getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha
    }
}
