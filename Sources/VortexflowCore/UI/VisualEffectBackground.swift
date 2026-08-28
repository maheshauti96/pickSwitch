import AppKit
import SwiftUI

/// `NSVisualEffectView` bridge for the panel's translucent backing
/// (Requirement 3.9).
///
/// SwiftUI's `.ultraThinMaterial` is not equivalent here: inside a borderless
/// non-activating `NSPanel` it renders against the panel's own (clear) backing rather
/// than sampling the desktop behind it, so the blur comes out flat. Going through
/// `NSVisualEffectView` with `blendingMode = .behindWindow` gets the real vibrancy.
struct VisualEffectBackground: NSViewRepresentable {

    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 16

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // `.active` rather than `.followsWindowActiveState`: the panel is never key,
        // so following window state would leave it permanently desaturated.
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}

/// The same behind-window blur, as a disc whose edge fades out instead of ending.
///
/// The hub needs both halves of that. It needs the *blur* because the alternative is showing the
/// desktop through 10pt type unsoftened: the well transmits some of the wallpaper on purpose now, and
/// a blurred wallpaper is legible underneath type where a sharp one is not. And it needs the **fade**
/// because a hard-edged disc is the outlined plate the hub has spent `wellClearFraction` avoiding —
/// the whole point of the middle is that it is a void with a lit rim, not a circle drawn on the
/// screen.
///
/// Faded through `NSVisualEffectView.maskImage` rather than a SwiftUI `.mask`. The blur is produced
/// by the window server behind this layer rather than by the layer itself, so it is the view's own
/// mask that is guaranteed to shape it; the same reason `VisualEffectBackground` above exists at all.
struct FrostedDisc: NSViewRepresentable {

    var material: NSVisualEffectView.Material = .hudWindow

    /// Fraction of the radius that stays fully opaque before the edge begins to fade.
    var solidFraction: CGFloat = 0.82

    func makeNSView(context: Context) -> DiscEffectView {
        let view = DiscEffectView()
        view.material = material
        view.solidFraction = solidFraction
        view.blendingMode = .behindWindow
        // `.active` for the reason given above: the panel is never key.
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: DiscEffectView, context: Context) {
        view.material = material
        view.solidFraction = solidFraction
    }

    /// Builds its own mask in `layout()`, which is the only place the size is known.
    ///
    /// Doing it from `updateNSView` looked equivalent and was not. SwiftUI runs the update pass
    /// before the representable has been given a frame, so `bounds` is still zero there on the first
    /// pass — and a `NSVisualEffectView` with no mask is a *rectangle*. The hub shipped a square
    /// frosted patch that painted straight over the void the ring is supposed to sit in, which
    /// `HubTintTests.wellRimIsNotAPlate` caught by measuring the desktop's own colour at zero where
    /// it had been 0.16. `layout()` is called whenever the bounds change and never before they exist.
    final class DiscEffectView: NSVisualEffectView {

        var solidFraction: CGFloat = 0.82 {
            didSet { if solidFraction != oldValue { maskedSide = nil; needsLayout = true } }
        }

        private var maskedSide: CGFloat?

        override func layout() {
            super.layout()
            let side = min(bounds.width, bounds.height)
            guard side > 1 else { return }
            guard maskedSide != side else { return }
            maskedSide = side
            maskImage = FrostedDisc.mask(side: side, solidFraction: solidFraction)
        }
    }

    fileprivate static func mask(side: CGFloat, solidFraction: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let space = CGColorSpaceCreateDeviceRGB()
            let stops: [CGFloat] = [0, max(0, min(1, solidFraction)), 1]
            guard let gradient = CGGradient(
                colorsSpace: space,
                colors: [
                    CGColor(colorSpace: space, components: [1, 1, 1, 1])!,
                    CGColor(colorSpace: space, components: [1, 1, 1, 1])!,
                    CGColor(colorSpace: space, components: [1, 1, 1, 0])!,
                ] as CFArray,
                locations: stops
            ) else { return false }
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            context.drawRadialGradient(
                gradient,
                startCenter: centre,
                startRadius: 0,
                endCenter: centre,
                endRadius: side / 2,
                options: []
            )
            return true
        }
    }
}
