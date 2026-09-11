import AppKit
import SwiftUI

extension WedgeShape {
    /// Glass effects are anchored to their view bounds, not the path's bounds.
    /// Localizing preserves the visible/hit-test geometry without allocating a
    /// panel-sized glass surface for every small wedge.
    var materialBounds: CGRect { path(in: .zero).boundingRect.insetBy(dx: -2, dy: -2).integral }

    func localized(to bounds: CGRect) -> WedgeShape {
        WedgeShape(centre: CGPoint(x: centre.x - bounds.minX, y: centre.y - bounds.minY),
            startAngle: startAngle, endAngle: endAngle, innerRadius: innerRadius,
            outerRadius: outerRadius, cornerRadius: cornerRadius)
    }
}

/// Real behind-window blur, shaped by the visual-effect view's own alpha mask.
/// SwiftUI material alone can sample the clear panel instead of the desktop.
struct WedgeGlassBackdrop: NSViewRepresentable {
    let shape: WedgeShape
    let dark: Bool
    let emphasized: Bool

    func makeNSView(context: Context) -> MaskedWedgeEffect {
        let view = MaskedWedgeEffect()
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        // No rectangular flash while the first layout is waiting for bounds.
        view.maskImage = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            return true
        }
        configure(view)
        return view
    }

    func updateNSView(_ view: MaskedWedgeEffect, context: Context) { configure(view) }

    private func configure(_ view: MaskedWedgeEffect) {
        view.material = dark ? .hudWindow : .popover
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.isEmphasized = emphasized
        view.shape = shape
        view.needsLayout = true
    }

    final class MaskedWedgeEffect: NSVisualEffectView {
        var shape: WedgeShape?
        private var maskKey: [Double] = []

        override func layout() {
            super.layout()
            guard let shape, bounds.width > 1, bounds.height > 1 else { return }
            let key = [Double(bounds.width), Double(bounds.height), Double(shape.centre.x),
                Double(shape.centre.y), shape.startAngle, shape.endAngle,
                Double(shape.innerRadius), Double(shape.outerRadius), Double(shape.cornerRadius)]
            guard key != maskKey else { return }
            maskKey = key
            maskImage = WedgeGlassBackdrop.mask(shape: shape, size: bounds.size)
        }
    }

    static func mask(shape: WedgeShape, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.addPath(shape.path(in: rect).cgPath)
            context.fillPath()
            return true
        }
    }
}
