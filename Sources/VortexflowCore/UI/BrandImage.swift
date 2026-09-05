import AppKit
import SwiftUI

/// The VortexFlow colour mark, loaded from the same files the website brand pack produced.
///
/// In-app chrome uses the three-colour spiral on a clear field. The dark squircle
/// is the Finder / Dock icon only — it is a plate, and windows already have one.
///
/// Looked up in `Bundle.main` first (the assembled `.app`) and `Bundle.module`
/// second (`swift run` and the test suite). The two copies are the same files;
/// `Scripts/build-app.sh` copies them into `Contents/Resources` because the
/// SwiftPM resource bundle is not part of that assembly.
enum BrandImage {

    static let menuBarPointSize: CGFloat = 18

    /// Colour mark for windows and menu items.
    static func mark() -> NSImage? {
        load(baseName: "VortexflowMark", pointSize: 256, template: false)
    }

    /// The same mark at status-item size, in colour.
    static func menuBarMark() -> NSImage? {
        load(baseName: "MenuBarMark", pointSize: menuBarPointSize, template: false)
    }

    /// What the status item actually draws, with SF Symbols only as a last resort.
    ///
    /// A `variableLength` item with no image and no title collapses to zero width
    /// and the app disappears from the menu bar. That has happened; this path
    /// must not return nil just because a PNG failed to load.
    static func statusItemImage(hasWarning: Bool) -> NSImage? {
        if let mark = menuBarMark() {
            return mark
        }
        return symbolFallback(hasWarning: hasWarning)
    }

    // MARK: - Loading

    private static func load(baseName: String, pointSize: CGFloat, template: Bool) -> NSImage? {
        // The assembled app puts every scale in Contents/Resources, which is
        // exactly what `NSImage(named:)` is for — it builds the @1x/@2x/@3x stack.
        if let named = NSImage(named: NSImage.Name(baseName)), named.isValid {
            configure(named, pointSize: pointSize, template: template)
            return named
        }

        let image = NSImage()
        image.size = NSSize(width: pointSize, height: pointSize)
        var found = false
        for scale in [1, 2, 3] {
            let resource = scale == 1 ? baseName : "\(baseName)@\(scale)x"
            guard let url = url(forResource: resource, extension: "png"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data)
            else { continue }
            representation.size = NSSize(
                width: CGFloat(representation.pixelsWide) / CGFloat(scale),
                height: CGFloat(representation.pixelsHigh) / CGFloat(scale)
            )
            image.addRepresentation(representation)
            found = true
        }

        if !found, let url = url(forResource: baseName, extension: "png") {
            return NSImage(contentsOf: url).map {
                configure($0, pointSize: pointSize, template: template)
                return $0
            }
        }

        guard found else { return nil }
        configure(image, pointSize: pointSize, template: template)
        return image
    }

    @discardableResult
    private static func configure(_ image: NSImage, pointSize: CGFloat, template: Bool) -> NSImage {
        image.isTemplate = template
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }

    private static func url(forResource name: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
        // `.copy("Resources")` keeps the folder; `.process` usually does not.
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    /// Same candidate list the status item used before the brand mark shipped, so a
    /// missing PNG cannot hide the app.
    private static func symbolFallback(hasWarning: Bool) -> NSImage? {
        let candidates = hasWarning
            ? [
                "exclamationmark.triangle.fill",
                "exclamationmark.triangle",
                "exclamationmark.circle.fill",
                "exclamationmark.circle",
                "exclamationmark",
            ]
            : [
                "rectangle.on.rectangle",
                "macwindow.on.rectangle",
                "square.on.square",
                "macwindow",
            ]
        let description = hasWarning ? "VortexFlow needs attention" : "VortexFlow"
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: description) {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }
}

/// The colour mark, sized for a window header.
struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        if let image = BrandImage.mark() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
