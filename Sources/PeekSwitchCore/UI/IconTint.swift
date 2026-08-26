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

    // MARK: - Separation

    /// Closest two hues may sit before they are pushed apart, as a fraction of the wheel. ≈20°.
    private static let minimumSeparation = 0.055
    /// Furthest a hue may be moved from the one its icon actually has. ≈22°.
    ///
    /// This is the honesty limit. Beyond it the tint stops describing the icon — a blue application
    /// would end up green — and the feature would be inventing identities rather than surfacing
    /// them. A cluster too dense to separate within this bound stays partly clustered on purpose.
    private static let maximumDrift = 0.06

    /// Spread hues that are too close together to tell apart.
    ///
    /// Icons are not distributed evenly around the colour wheel: on a typical Mac a third of them
    /// are the same blue, and Safari, Figma and VS Code all sample within six degrees of one
    /// another. Reporting that faithfully produces a row of containers that look identical, which
    /// defeats the point of tinting them at all.
    ///
    /// The order is by hue and then by key, never by how recently a window was used. That matters
    /// more than it looks: keyed off recency, an application's colour would change every time you
    /// switched windows. Keyed off the hue and a stable identifier, a given set of applications
    /// always resolves the same way.
    ///
    /// - Parameter tints: one entry per thing being told apart, keyed by a stable identifier.
    static func separated(_ tints: [String: IconTint]) -> [String: IconTint] {
        guard tints.count > 1 else { return tints }

        let ordered = tints.sorted { ($0.value.hue, $0.key) < ($1.value.hue, $1.key) }
        var separated = tints

        // Clusters are resolved as a group rather than one hue at a time. Nudging each hue forward
        // off the one before it does not work: in a dense cluster the drift limit binds on every
        // member, so all of them shift by the same amount, keep their original spacing, and end up
        // exactly as indistinguishable as they started. Seven blue icons on a real desktop moved
        // 21.6° each and stayed 0.2° apart.
        var clusterStart = 0
        while clusterStart < ordered.count {
            var clusterEnd = clusterStart
            while clusterEnd + 1 < ordered.count,
                  ordered[clusterEnd + 1].value.hue - ordered[clusterEnd].value.hue
                      < minimumSeparation {
                clusterEnd += 1
            }

            let cluster = ordered[clusterStart...clusterEnd]
            if cluster.count > 1 {
                for (key, hue) in distribute(cluster) {
                    guard let vividness = tints[key]?.vividness else { continue }
                    separated[key] = IconTint(hue: hue - floor(hue), vividness: vividness)
                }
            }
            clusterStart = clusterEnd + 1
        }
        return separated
    }

    /// Positions for one cluster, spread symmetrically about its own centre.
    ///
    /// Members move in both directions, which is what makes the drift limit a budget rather than a
    /// wall: a cluster of `n` has `2 × maximumDrift` of room to work with instead of one drift's
    /// worth in a single direction. When that is still not enough to reach full separation — seven
    /// icons inside twenty degrees cannot all be twenty degrees apart — the cluster spreads evenly
    /// across whatever room it does have rather than giving up.
    private static func distribute(
        _ cluster: ArraySlice<(key: String, value: IconTint)>
    ) -> [(key: String, hue: Double)] {
        let hues = cluster.map(\.value.hue)
        guard let lowest = hues.first, let highest = hues.last else { return [] }

        let lowerBound = lowest - maximumDrift
        let upperBound = highest + maximumDrift
        let steps = Double(cluster.count - 1)
        // Never spread further than needed: a cluster with room to spare gets exactly the minimum
        // separation, centred, rather than being fanned across the whole budget.
        let step = min(minimumSeparation, (upperBound - lowerBound) / steps)
        let start = (lowerBound + upperBound) / 2 - step * steps / 2

        return cluster.enumerated().map { offset, member in
            let ideal = start + step * Double(offset)
            // Clamped per member against its own icon's hue. Both bounds rise with the sorted
            // order, so clamping cannot reorder the cluster or cross two members over.
            let bounded = min(
                max(ideal, member.value.hue - maximumDrift),
                member.value.hue + maximumDrift
            )
            return (member.key, bounded)
        }
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

    /// The hovered card fill, tinted to match. List selection still uses `accentFill`, which is
    /// never tinted: a selected row carries inverted text and must not shift hue. Radial
    /// selection uses `radialSelectedFill(tintedBy:)` instead — a stronger self, not a recolor.
    func selectedCardFill(tintedBy tint: IconTint?) -> Color {
        blend(selectedCardFill, toward: tint)
    }

    /// A selected radial wedge: the same hue as the unselected tile, pushed further.
    ///
    /// Still not the brand. The wedge is a surface that carries text, so it is bound by the same
    /// luminance band as every other fill; the hub's light is what takes the window's colour, via
    /// `hubAmbience(for:)`.
    func radialSelectedFill(tintedBy tint: IconTint?) -> Color {
        blend(selectedCardFill, toward: tint, strengthScale: radialSelectedStrengthScale)
    }

    private func blend(
        _ base: Color,
        toward tint: IconTint?,
        strengthScale: Double = 1
    ) -> Color {
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
        let strength = min(1, tintStrength * strengthScale * min(1, max(0.4, tint.vividness)))

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
