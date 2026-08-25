import AppKit

/// Marks a private browsing window on its own icon.
///
/// ## Why the marker moved onto the icon
///
/// This started as a 9-point glyph in the badge row beneath the title, in the palette's *secondary*
/// text colour. That is the treatment given to "minimized" — a detail you read once you have already
/// found the window — and private browsing is not that kind of fact. It is the first thing you need
/// to know about a window, because acting on the wrong one means typing into a session that is not
/// the one you meant. At 9 points in a muted colour, next to two other glyphs, it went unnoticed.
///
/// Composited onto the icon instead, it is adjacent to the thing it describes, it survives every
/// arrangement — cards, rows, radial wedges, the list preview, the transition ghost — because they
/// all take their icon from the same place, and it needs no room in a label line that the radial
/// layout in particular does not have to spare.
///
/// The corner is free for exactly this: a private window never gets a site icon, since fetching one
/// would put a private destination on the network. So the space the active-site icon would occupy
/// is available, and only on the windows that need this marker.
enum PrivateWindowIcon {

    private static let canvas = NSSize(width: 256, height: 256)

    /// Badge diameter as a fraction of the icon's side.
    ///
    /// Large. A marker that changes what a keystroke will do has to be readable at the smallest
    /// size any arrangement draws an icon, which is around 22 points in a scaled-down radial wedge:
    /// this leaves the badge about 10 points there, roughly the size the old glyph was at full size.
    private static let badgeScale: CGFloat = 0.46

    /// The glasses inside the badge, as a fraction of the badge's diameter.
    private static let glyphScale: CGFloat = 0.62

    /// Ring width as a fraction of the badge's diameter. Separates the badge from whatever icon
    /// colour happens to sit behind it, so it reads on Chrome's red and Edge's teal alike.
    private static let ringScale: CGFloat = 0.075

    /// `applicationIcon` with a private-browsing badge in its lower-trailing corner.
    ///
    /// Spectacles, because that is the metaphor Chromium uses for the mode itself, so it is the one
    /// already learned. Not a lock: a lock means HTTPS everywhere else in a browser.
    static func badged(_ applicationIcon: NSImage) -> NSImage {
        let glyph = glyphImage()

        let image = NSImage(size: canvas, flipped: false) { bounds in
            let side = min(bounds.width, bounds.height)
            guard side > 0 else { return false }

            NSGraphicsContext.current?.imageInterpolation = .high
            applicationIcon.draw(
                in: NSRect(x: bounds.minX, y: bounds.minY, width: side, height: side),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )

            let badgeSide = side * badgeScale
            let badgeRect = NSRect(
                x: bounds.maxX - badgeSide,
                y: bounds.minY,
                width: badgeSide,
                height: badgeSide
            )

            // Light ring first, then the dark disc inside it. Drawn as two filled circles rather
            // than a stroke so the ring cannot straddle the disc's edge and soften it.
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            let disc = badgeRect.insetBy(
                dx: badgeSide * ringScale,
                dy: badgeSide * ringScale
            )
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            NSBezierPath(ovalIn: disc).fill()

            if let glyph {
                let glyphSide = badgeSide * glyphScale
                let aspect = glyph.size.height > 0
                    ? glyph.size.width / glyph.size.height
                    : 1
                // The glasses are much wider than they are tall. Fitting them to the badge's width
                // and keeping their aspect ratio stops them being stretched into goggles.
                let glyphWidth = glyphSide
                let glyphHeight = aspect > 0 ? glyphSide / aspect : glyphSide
                glyph.draw(
                    in: NSRect(
                        x: badgeRect.midX - glyphWidth / 2,
                        y: badgeRect.midY - glyphHeight / 2,
                        width: glyphWidth,
                        height: glyphHeight
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The spectacles, already white, so the badge does not depend on the drawing context's tint.
    private static func glyphImage() -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: "eyeglasses",
            accessibilityDescription: "Private browsing window"
        ) else { return nil }

        let configuration = NSImage.SymbolConfiguration(pointSize: 96, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        return symbol.withSymbolConfiguration(configuration) ?? symbol
    }
}
