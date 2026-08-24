import AppKit

/// Builds the browser-window identity shown throughout the overlay.
///
/// The browser application leads in the lower-left, and the verified active-site icon sits behind
/// it in the upper-right: the window is a browser window first, and the site says which one.
/// Returning one scalable `NSImage` keeps every existing icon renderer — cards, rows, previews,
/// radial wedges and transition ghosts — visually consistent without changing their geometry.
enum BrowserWindowIcon {

    private static let canvas = NSSize(width: 256, height: 256)
    /// The icon in front. Larger, because it is the one that should read first.
    private static let foregroundScale: CGFloat = 0.78
    /// The icon behind, offset to the upper-right so both silhouettes stay legible at the small
    /// sizes a row or a shrunken radial wedge draws them at.
    private static let backgroundScale: CGFloat = 0.64

    static func layered(siteIcon: NSImage, browserIcon: NSImage) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { bounds in
            let side = min(bounds.width, bounds.height)
            guard side > 0 else { return false }

            NSGraphicsContext.current?.imageInterpolation = .high

            // Painted back to front: the site icon first, then the browser over it.
            let backgroundSide = side * backgroundScale
            siteIcon.draw(
                in: NSRect(
                    x: bounds.maxX - backgroundSide,
                    y: bounds.maxY - backgroundSide,
                    width: backgroundSide,
                    height: backgroundSide
                ),
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
