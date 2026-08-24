import AppKit
import SwiftUI

/// The dominant colour of a window's icon, used to tint the container that holds it.
///
/// ## Why a hue rather than a colour
///
/// Three Chrome windows are three identical icons, and a ring of identical white wedges is
/// exactly as hard to scan. Tinting each container by its icon gives every window a second,
/// pre-attentive identifier that costs no space — but it must not be the icon's *actual* colour.
/// A card carries text, and `OverlayPalette` exists because contrast here is a property of the
/// card rather than a lucky consequence of what is behind it. Painting Chrome's red onto a card
/// would undo that.
///
/// So only the hue survives sampling. The palette owns how far its fill is pushed toward that
/// hue, and how vivid the hue is allowed to be, which keeps the composite within a narrow
/// luminance band whatever the icon looks like. `OverlayPaletteTests` sweeps the whole colour
/// wheel against both themes to hold that guarantee.
///
/// ## Why averaging does not work
///
/// Chrome's icon is red, yellow, green and blue in roughly equal measure and averages to a muddy
/// brown; Slack's does the same. The sample therefore buckets pixels by hue and takes the
/// heaviest bucket, weighting each pixel by how opaque and how vivid it is. Greys, near-black and
/// near-white pixels are skipped outright, so a monochrome icon reports no tint at all rather
/// than an arbitrary one — which is the right answer for it.
struct IconTint: Equatable, Sendable {

    /// Position on the colour wheel, `0...1`.
    let hue: Double
    /// How vivid the icon's dominant colour is, `0...1`.
    ///
    /// Only used to scale the tint down for a washed-out icon. The upper bound is the palette's
    /// to set, never the icon's.
    let vividness: Double

    // MARK: - Sampling

    /// Pixels per side of the downsample.
    ///
    /// Not smaller, and that is not a guess: at 8 per side the downscale blends neighbouring
    /// colours into grey, and Slack and Figma — two of the most colourful icons on any Mac —
    /// sampled as having no colour at all. 32 keeps their shapes separable and still costs well
    /// under a millisecond per icon.
    private static let sampleSide = 32
    /// Below this, a pixel is icon edge or transparent padding rather than icon.
    private static let minimumAlpha = 0.35
    /// Below this, a pixel is grey and says nothing about hue.
    private static let minimumSaturation = 0.20
    /// Below this a pixel is effectively black, where hue is rounding noise.
    ///
    /// There is deliberately no upper bound. An earlier one rejected anything brighter than 0.98
    /// to skip white — but white is already excluded by having no saturation, and a fully vivid
    /// colour like `#0080FF` has a brightness of exactly 1. Bounding the top threw away precisely
    /// the most colourful pixels in an icon: Safari lost 200 of them and reported no colour.
    private static let minimumBrightness = 0.12
    /// 15° buckets. Fine enough to separate neighbouring brand colours, coarse enough that one
    /// gradient does not split across several.
    private static let hueBuckets = 24
    /// Share of the sampled area the winning bucket must account for, as fully-opaque
    /// fully-saturated pixels, before it counts as the icon's colour identity. Keeps a small
    /// coloured badge on an otherwise grey icon from tinting a whole card.
    private static let minimumColourFraction = 0.02

    /// The dominant hue of `image`, or `nil` when it has no usable colour.
    static func sampled(from image: NSImage) -> IconTint? {
        let side = sampleSide
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposed,
            context: nil,
            hints: nil
        ) else { return nil }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
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

        // Circular accumulation per bucket: a hue is an angle, so summing 0.02 and 0.98 as
        // numbers would land on grey-green instead of red.
        var sine = [Double](repeating: 0, count: hueBuckets)
        var cosine = [Double](repeating: 0, count: hueBuckets)
        var saturationWeight = [Double](repeating: 0, count: hueBuckets)
        var weights = [Double](repeating: 0, count: hueBuckets)

        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= minimumAlpha else { continue }

            // Premultiplied, so recover the original channels before judging saturation.
            let red = Double(pixels[offset]) / 255 / alpha
            let green = Double(pixels[offset + 1]) / 255 / alpha
            let blue = Double(pixels[offset + 2]) / 255 / alpha

            let (hue, saturation, brightness) = hsb(
                red: min(1, red),
                green: min(1, green),
                blue: min(1, blue)
            )
            guard saturation >= minimumSaturation,
                  brightness >= minimumBrightness
            else { continue }

            let weight = alpha * saturation
            let bucket = min(hueBuckets - 1, Int(hue * Double(hueBuckets)))
            let angle = hue * 2 * .pi
            sine[bucket] += sin(angle) * weight
            cosine[bucket] += cos(angle) * weight
            saturationWeight[bucket] += saturation * weight
            weights[bucket] += weight
        }

        guard let winner = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[winner] >= Double(side * side) * minimumColourFraction
        else { return nil }

        var angle = atan2(sine[winner], cosine[winner])
        if angle < 0 { angle += 2 * .pi }

        return IconTint(
            hue: angle / (2 * .pi),
            vividness: min(1, saturationWeight[winner] / weights[winner])
        )
    }

    /// Hue, saturation and brightness for one sRGB pixel, all `0...1`.
    private static func hsb(
        red: Double,
        green: Double,
        blue: Double
    ) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        guard delta > 0, maximum > 0 else {
            return (0, 0, maximum)
        }

        let hue: Double
        switch maximum {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }

        var normalized = hue / 6
        if normalized < 0 { normalized += 1 }
        return (normalized, delta / maximum, maximum)
    }
}

extension OverlayPalette {

    /// A card fill nudged toward `tint`, or the untinted fill when there is nothing to nudge it
    /// toward.
    func cardFill(tintedBy tint: IconTint?) -> Color {
        blend(cardFill, toward: tint)
    }

    /// The hovered and selected card fill, tinted to match. Selection on the radial and list
    /// styles is drawn with `accentFill` instead, which is deliberately never tinted: it is the
    /// one thing on screen that must not be ambiguous.
    func selectedCardFill(tintedBy tint: IconTint?) -> Color {
        blend(selectedCardFill, toward: tint)
    }

    private func blend(_ base: Color, toward tint: IconTint?) -> Color {
        guard let tint else { return base }

        let hueColor = NSColor(
            hue: CGFloat(tint.hue),
            saturation: CGFloat(tintSaturation),
            brightness: CGFloat(tintBrightness),
            alpha: 1
        )
        guard let vivid = hueColor.usingColorSpace(.sRGB),
              let neutral = NSColor(base).usingColorSpace(.sRGB)
        else { return base }

        // A washed-out icon gets proportionally less tint, so a pastel app does not end up
        // looking as emphatic as a vivid one.
        let strength = tintStrength * min(1, max(0.4, tint.vividness))

        return Color(
            .sRGB,
            red: Double(neutral.redComponent) * (1 - strength)
                + Double(vivid.redComponent) * strength,
            green: Double(neutral.greenComponent) * (1 - strength)
                + Double(vivid.greenComponent) * strength,
            blue: Double(neutral.blueComponent) * (1 - strength)
                + Double(vivid.blueComponent) * strength,
            // The fill's own opacity is untouched: `OverlayPaletteTests` pins it at near-opaque
            // so that contrast cannot depend on the desktop behind the overlay.
            opacity: Double(neutral.alphaComponent)
        )
    }
}
