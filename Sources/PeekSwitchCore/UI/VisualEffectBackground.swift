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
