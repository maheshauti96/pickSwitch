import AppKit
import Testing
@testable import VortexflowCore

/// Holds the two things that decide whether a browser window's site is actually identifiable.
///
/// Both were got wrong once, and both failed the same way: the numbers looked defensible in the
/// source and the composition was unreadable on screen. Neither is the kind of mistake a
/// rendering test catches, because the image draws perfectly either way.
@Suite("Browser window icon")
struct BrowserWindowIconTests {

    // MARK: - Geometry

    /// The site icon's centre must not be under the browser icon.
    ///
    /// The first version put the browser at 0.78 and the site at 0.64, which left more than half
    /// the site icon's *area* visible — and only as an L-shaped sliver of its outer edges, with
    /// the middle, the part that says which site it is, covered. Area is the wrong measure.
    @Test("the site icon's centre is clear of the browser icon")
    func centreIsClearOfForeground() {
        #expect(BrowserWindowIcon.centreIsClearOfForeground)
    }

    /// Both icons stay inside the canvas, and each is large enough to recognise.
    @Test("both icons are substantial and fit the canvas")
    func scalesAreSane() {
        #expect(BrowserWindowIcon.foregroundScale > 0.5)
        #expect(BrowserWindowIcon.foregroundScale <= 1)
        #expect(BrowserWindowIcon.backgroundScale > 0.5)
        #expect(BrowserWindowIcon.backgroundScale <= 1)
    }

    /// The composition is square, so every existing icon renderer can size it like any other icon.
    @Test("the composition is square")
    func compositionIsSquare() {
        let composed = BrowserWindowIcon.layered(
            siteIcon: Self.filled(.systemBlue),
            browserIcon: Self.filled(.systemRed)
        )
        #expect(composed.size.width == composed.size.height)
        #expect(composed.size.width > 0)
    }

    // MARK: - Backing plate

    /// A dark glyph on transparency is the common favicon shape, because favicons are drawn for a
    /// light tab strip. Without a plate it vanishes into the overlay's dark container.
    @Test("a dark glyph on transparency gets a plate")
    func darkGlyphOnTransparencyIsPlated() {
        #expect(BrowserWindowIcon.siteIconNeedsPlate(Self.glyph(.black)))
    }

    /// A light glyph already reads on a dark container, and a light plate would erase it. This is
    /// why low coverage alone cannot be the test.
    @Test("a light glyph on transparency is left alone")
    func lightGlyphOnTransparencyIsNotPlated() {
        #expect(!BrowserWindowIcon.siteIconNeedsPlate(Self.glyph(.white)))
    }

    /// Sites that ship their own opaque background — X, Hacker News, Wikipedia — must not have a
    /// second one drawn behind it, dark artwork included.
    @Test("artwork that fills its own square is left alone", arguments: [
        NSColor.black, .white, .systemOrange, .systemBlue
    ])
    func opaqueArtworkIsNotPlated(colour: NSColor) {
        #expect(!BrowserWindowIcon.siteIconNeedsPlate(Self.filled(colour)))
    }

    /// An empty image says nothing, and inventing a plate for it would put a white square next to
    /// every browser icon whose favicon failed to decode.
    @Test("a fully transparent image gets no plate")
    func transparentImageIsNotPlated() {
        let empty = NSImage(size: NSSize(width: 32, height: 32))
        empty.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        empty.unlockFocus()

        #expect(!BrowserWindowIcon.siteIconNeedsPlate(empty))
    }

    // MARK: - Fixtures

    /// Artwork that covers its whole square, the way a site shipping its own background plate does.
    private static func filled(_ colour: NSColor) -> NSImage {
        let side = 32.0
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        colour.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return image
    }

    /// A mark on transparency, covering roughly half its square — the shape of a bare favicon.
    private static func glyph(_ colour: NSColor) -> NSImage {
        let side = 32.0
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        colour.setFill()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: side - 8, height: side - 8)).fill()
        image.unlockFocus()
        return image
    }
}
