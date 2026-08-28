import AppKit
import SwiftUI
import Testing
@testable import VortexflowCore

/// The middle of the spiral: a neutral plate for the caption, lit by a glow that takes its hue
/// from the window under the pointer, with that window's icon as a watermark behind the type.
///
/// Two things pull against each other here, which is why these are pixel tests on the real
/// overlay rather than assertions about which palette function got called. The hub is now the
/// overlay's loudest colour signal — the ambience follows the pointer, and so does the watermark.
/// But it is also the one surface carrying 9 and 10pt type, and the plate under that type has to
/// stay a plate whatever colour is being thrown at it. Both halves are measured: that the colour
/// really does track the icon, and that the caption keeps its 4.5:1 while it does.
@Suite("Hub well")
@MainActor
struct HubTintTests {

    /// WCAG normal-text minimum, the same bar `OverlayPaletteTests` holds the palette to.
    private static let minimumRatio: Double = 4.5

    private static func luminance(_ colour: NSColor) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(Double(colour.redComponent))
            + 0.7152 * channel(Double(colour.greenComponent))
            + 0.0722 * channel(Double(colour.blueComponent))
    }

    /// Contrast of the caption's smallest line against a background actually sampled from the
    /// render, so the watermark's contribution is included rather than assumed away.
    /// Contrast of the hub's *own* secondary weight over a sampled surface.
    ///
    /// `hubSecondaryText` rather than `secondaryText`, which is not a detail: the hub caption is the
    /// one place that uses the heavier weight, because it is the one place whose background is partly
    /// the wallpaper. Measuring the card weight here reports a ratio no pixel on screen has.
    private static func captionRatio(over background: NSColor, scheme: ColorScheme) throws -> Double {
        let palette = OverlayPalette.forScheme(scheme)
        let text = try #require(NSColor(palette.hubSecondaryText).usingColorSpace(.sRGB))
        let alpha = Double(text.alphaComponent)
        let composed = NSColor(
            srgbRed: text.redComponent * alpha + background.redComponent * (1 - alpha),
            green: text.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: text.blueComponent * alpha + background.blueComponent * (1 - alpha),
            alpha: 1
        )
        let first = luminance(composed)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// A spiral with one strongly coloured window under the pointer, rendered for sampling.
    private static func renderHub(
        iconColour: NSColor?,
        appearance: NSAppearance.Name,
        increaseContrast: Bool = false
    ) throws -> (rep: NSBitmapImageRep, state: OverlayState, bounds: CGRect) {
        let state = OverlayState()
        state.availableContentWidth = 1400
        state.availableContentHeight = 860
        state.layoutStyle = .spiral
        state.increaseContrast = increaseContrast
        state.load(
            entries: (0..<10).map { index in
                WindowEntry(
                    windowID: CGWindowID(700 + index),
                    processID: pid_t(index + 1),
                    applicationName: "App \(index)",
                    // Only the hovered window is coloured, so anything measured can only have
                    // come from it.
                    applicationIcon: index == 1 ? iconColour.map(solidIcon) : nil,
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 1
        )

        let size = state.layout.panelSize
        let hosting = NSHostingView(rootView: ZStack {
            Color.black
            OverlayView(state: state, hoveredIndex: 1)
        }.frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return (rep, state, hosting.bounds)
    }

    /// Colour on the ring's centreline, opposite the coupling so the tongue's white core cannot
    /// be mistaken for the ambience, and at the hub's dead centre where the watermark is strongest.
    private static func ringAndCentre(
        iconColour: NSColor?,
        appearance: NSAppearance.Name,
        increaseContrast: Bool = false
    ) throws -> (ring: NSColor, centre: NSColor, wellBody: NSColor) {
        let (rep, state, bounds) = try renderHub(
            iconColour: iconColour,
            appearance: appearance,
            increaseContrast: increaseContrast
        )
        let hub = state.layout.radialHubFrame
        let geometry = try #require(state.layout.radial)
        let scaleX = Double(rep.pixelsWide) / Double(bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(bounds.height)
        func pixel(radius: CGFloat, angle: Double) throws -> NSColor {
            let x = hub.midX + radius * CGFloat(cos(angle))
            let y = hub.midY + radius * CGFloat(sin(angle))
            return try #require(
                rep.colorAt(x: Int(Double(x) * scaleX), y: Int(Double(y) * scaleY))?
                    .usingColorSpace(.sRGB)
            )
        }
        return (
            try pixel(
                radius: geometry.hubRadius - HubChrome.ringInset,
                angle: state.radialRingAngle + .pi
            ),
            try pixel(radius: 0, angle: 0),
            // Well interior: out past the watermark's strongest point and the caption, but well
            // inside the rim, so it is the void the ring has to stay lighter than.
            try pixel(radius: geometry.hubRadius * 0.34, angle: state.radialRingAngle + .pi)
        )
    }

    private static func solidIcon(_ colour: NSColor) -> NSImage {
        let side = 32.0
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        colour.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return image
    }

    private static func state(selected: Int, icons: Bool = true) -> OverlayState {
        let state = OverlayState()
        state.availableContentWidth = 1400
        state.availableContentHeight = 860
        state.layoutStyle = .spiral
        state.displayLayout = DisplayLayout(displays: [
            DisplayInfo(
                number: 1,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                isBuiltIn: true,
                name: "Built-in"
            )
        ])
        let palette: [(String, NSColor)] = [
            ("Scarlet", .systemRed),
            ("Emerald", .systemGreen)
        ]
        state.load(
            entries: palette.enumerated().map { index, app in
                WindowEntry(
                    windowID: CGWindowID(900 + index),
                    processID: pid_t(index + 1),
                    applicationName: app.0,
                    applicationIcon: icons ? solidIcon(app.1) : nil,
                    title: "Window of \(app.0)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: selected
        )
        return state
    }

    /// Mean colour of a patch inside the hub disc, clear of the caption text and the ring.
    ///
    /// Defaults to windows with no icon, which is what isolates the plate itself: with an icon the
    /// watermark is deliberately painted across this patch, so a render that included one would be
    /// measuring the watermark rather than the fill underneath it.
    private static func hubFill(
        selected: Int,
        appearance: NSAppearance.Name,
        icons: Bool = false
    ) throws -> NSColor {
        let state = state(selected: selected, icons: icons)
        let hosting = NSHostingView(rootView: OverlayView(state: state, hoveredIndex: selected))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = CGRect(origin: .zero, size: state.layout.panelSize)
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = state.layout.radialHubFrame
        let patch = NSRect(
            x: hub.midX - hub.width * 0.08,
            y: hub.midY + hub.height * 0.28,
            width: hub.width * 0.16,
            height: hub.height * 0.06
        )

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)
        for x in stride(from: patch.minX, to: patch.maxX, by: 1) {
            for y in stride(from: patch.minY, to: patch.maxY, by: 1) {
                guard let colour = rep.colorAt(
                    x: Int(Double(x) * scaleX),
                    y: Int(Double(y) * scaleY)
                )?.usingColorSpace(.sRGB) else { continue }
                red += Double(colour.redComponent)
                green += Double(colour.greenComponent)
                blue += Double(colour.blueComponent)
                count += 1
            }
        }
        try #require(count > 0, "sampled no pixels inside the hub")
        return NSColor(
            srgbRed: CGFloat(red / count),
            green: CGFloat(green / count),
            blue: CGFloat(blue / count),
            alpha: 1
        )
    }

    /// Hue of a sampled pixel, and the short way round between two hues.
    ///
    /// Everything about the ambience is asserted in hue rather than in channels, because that is
    /// the only thing the ambience is allowed to move — and because `HubRing` breathes on a live
    /// `TimelineView`, so the ring's absolute brightness differs between two renders taken a
    /// moment apart while its colour does not.
    private static func hue(of colour: NSColor) -> Double {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        colour.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(hue)
    }

    private static func hueDistance(_ first: Double, _ second: Double) -> Double {
        let drift = abs(first - second)
        return min(drift, 1 - drift)
    }

    /// The hub's light is the pointer's colour. Sampled on the ring's centreline opposite the
    /// coupling, so what is measured is the loop of light itself rather than the tongue.
    ///
    /// Pinned against the hue `IconTint` actually reports for each icon, not merely "these two
    /// differ": a ring that went grey for one window and stayed mint for the other would satisfy
    /// a difference check while following nothing.
    @Test("the ambience takes the hue of the window under the pointer")
    func ambienceFollowsTheHoveredWindow() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            for colour in [NSColor.systemRed, .systemGreen, .systemPurple] {
                let expected = try #require(
                    IconTint.sampled(from: Self.solidIcon(colour)),
                    "fixture icon reported no hue"
                )
                let sampled = try Self.ringAndCentre(
                    iconColour: colour,
                    appearance: appearance
                ).ring
                let drift = Self.hueDistance(Self.hue(of: sampled), expected.hue)
                #expect(
                    drift < 0.06,
                    "\(appearance) ring hue \(Self.hue(of: sampled)) is \(drift) from the icon's \(expected.hue)"
                )
            }
        }
    }

    /// The hue has to arrive as *colour*, not merely as a hue angle — which is the gap that let a
    /// colourless Light Mode hub ship.
    ///
    /// `ambienceFollowsTheHoveredWindow` measures hue drift and passed the whole time the light hub
    /// was grey, because a near-white pixel still reports a hue: rendered, its rim measured chroma 3
    /// against Dark Mode's 16–39. Hue was pinned and visibility was not, so this pins visibility.
    ///
    /// Chroma as peak-minus-trough in 8-bit rather than HSB saturation, because that is what "does
    /// this look coloured" depends on and it is the quantity that exposed the defect.
    @Test("the ambience arrives as visible colour, not just a hue angle")
    func ambienceIsVisiblyChromatic() throws {
        // Per scheme, because the two carry colour by different means and are not comparable on one
        // number. Dark puts a pale rim against a near-black well, so 16–39 of chroma reads loudly off
        // a luminance difference of about 130. Light has no such difference available — its well
        // renders around 200 of 255 — so the hue itself has to do the work, and it needs far more of
        // it. Measured, light lands at 49–69 and dark at 16–39.
        let floors: [NSAppearance.Name: Double] = [.darkAqua: 15, .aqua: 40]
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let floor = try #require(floors[appearance])
            for colour in [
                NSColor.systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple,
            ] {
                let sampled = try Self.ringAndCentre(iconColour: colour, appearance: appearance)
                let ring = sampled.ring
                let red = Double(ring.redComponent) * 255
                let green = Double(ring.greenComponent) * 255
                let blue = Double(ring.blueComponent) * 255
                let chroma = max(red, green, blue) - min(red, green, blue)

                #expect(
                    chroma >= floor,
                    """
                    \(appearance) ring for \(colour) has chroma \(Int(chroma)), under \(Int(floor)): \
                    rgb(\(Int(red)),\(Int(green)),\(Int(blue)))
                    """
                )

                // The rim must not turn into a dark crater around the well.
                //
                // Deliberately not "lighter than the well", which is what this asserted first and is
                // a Dark Mode idea in disguise. In Light Mode there is no lightness to spare — the
                // well is already at 200 of 255 — so a rim carrying real colour necessarily sits at
                // or slightly below it: measured, between 13 under and 11 over. That reads correctly,
                // as a coloured band on a pale void. What would not read is the rim continuing down
                // until it became an outline, so that is what is bounded.
                let well = sampled.wellBody
                let ringLuma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let wellLuma = 0.2126 * Double(well.redComponent) * 255
                    + 0.7152 * Double(well.greenComponent) * 255
                    + 0.0722 * Double(well.blueComponent) * 255
                #expect(
                    ringLuma >= wellLuma - 25,
                    """
                    \(appearance) ring for \(colour) has sunk below its well: \
                    ring \(Int(ringLuma)) vs well \(Int(wellLuma))
                    """
                )
            }
        }
    }

    /// A monochrome icon reports no hue at all, and the hub has to fall back to the brand rather
    /// than pick an arbitrary colour out of rounding noise.
    @Test("a colourless icon leaves the ambience at the brand colour")
    func ambienceFallsBackWithoutAHue() throws {
        let brand = try #require(NSColor(OverlayPalette.dark.hubRing).usingColorSpace(.sRGB))
        for colourless in [NSColor.white, .black, nil] {
            #expect(
                colourless.flatMap { IconTint.sampled(from: Self.solidIcon($0)) } == nil,
                "fixture icon was supposed to have no usable hue"
            )
            let sampled = try Self.ringAndCentre(
                iconColour: colourless,
                appearance: .darkAqua
            ).ring
            let drift = Self.hueDistance(Self.hue(of: sampled), Self.hue(of: brand))
            #expect(drift < 0.04, "\(String(describing: colourless)) moved the hue by \(drift)")
        }
    }

    /// The watermark is the second answer to "which window is this?", ahead of reading the title.
    ///
    /// Measured as chroma rather than as a single channel, because the two schemes move in
    /// opposite directions: over the near-black dark plate a red icon *raises* red, while over the
    /// near-white light plate it can only *lower* green and blue. Red-minus-green rises either way.
    @Test("the hovered window's icon is drawn behind the caption")
    func backdropShowsTheHoveredIcon() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            func chroma(_ colour: NSColor) -> Double {
                Double(colour.redComponent) - Double(colour.greenComponent)
            }
            let bare = chroma(try Self.ringAndCentre(iconColour: nil, appearance: appearance).centre)
            let red = chroma(
                try Self.ringAndCentre(iconColour: .systemRed, appearance: appearance).centre
            )
            let green = chroma(
                try Self.ringAndCentre(iconColour: .systemGreen, appearance: appearance).centre
            )

            #expect(
                red > bare + 0.03,
                "\(appearance) no red watermark: bare chroma \(bare) vs red \(red)"
            )
            #expect(
                green < bare - 0.03,
                "\(appearance) no green watermark: bare chroma \(bare) vs green \(green)"
            )
        }
    }

    /// The one thing the watermark may not cost. It is painted directly beneath the caption's 9pt
    /// line, so its opacity is a contrast budget: raising `HubChrome.backdropIconOpacity*` or
    /// widening its fade until the type stops clearing 4.5:1 has to fail here.
    ///
    /// Worst case is a uniformly white icon in Dark Mode and a uniformly black one in Light —
    /// maximum luminance shift in the direction that hurts, and by construction no hue to soften
    /// it. Measured from the render, not from the constants.
    @Test("the caption keeps its contrast over the watermark")
    func captionStaysLegibleOverTheWatermark() throws {
        for (appearance, scheme, worst) in [
            (NSAppearance.Name.darkAqua, ColorScheme.dark, NSColor.white),
            (.aqua, .light, .black),
        ] {
            for icon in [worst, .systemRed, .systemGreen] {
                let centre = try Self.ringAndCentre(iconColour: icon, appearance: appearance).centre
                let ratio = try Self.captionRatio(over: centre, scheme: scheme)
                #expect(
                    ratio >= Self.minimumRatio,
                    "\(scheme) caption over \(icon) watermark: \(ratio) < \(Self.minimumRatio)"
                )
            }
        }
    }

    /// Increase Contrast asks for the opposite of decorative colour under small type. The hue goes
    /// back to the brand — that route is shared with the wedges, through `OverlayState.tint(for:)` —
    /// and the watermark disappears entirely, because unlike the ambience it cannot express itself
    /// as hue alone.
    @Test("Increase Contrast drops both the hue and the watermark")
    func increaseContrastDropsTheDecoration() throws {
        let resting = try Self.ringAndCentre(iconColour: nil, appearance: .darkAqua)
        let plain = try Self.ringAndCentre(
            iconColour: .systemRed,
            appearance: .darkAqua,
            increaseContrast: true
        )

        let ringDrift = Self.hueDistance(Self.hue(of: plain.ring), Self.hue(of: resting.ring))
        #expect(ringDrift < 0.04, "ambience still hued under Increase Contrast: \(ringDrift)")

        let centreDistance = abs(plain.centre.redComponent - resting.centre.redComponent)
            + abs(plain.centre.greenComponent - resting.centre.greenComponent)
            + abs(plain.centre.blueComponent - resting.centre.blueComponent)
        #expect(centreDistance < 0.03, "watermark still drawn under Increase Contrast: \(centreDistance)")
    }

    /// The well is on the palette's side of the middle, and no longer exactly the palette's colour.
    ///
    /// These two used to require the rendered well to *equal* `hubWellFill` within a tolerance, which
    /// was the right test while the well was two opaque circles of it. It is now a behind-window blur
    /// under a partial scrim, so its colour is deliberately a function of the wallpaper — and a test
    /// that pins it to one value would be asserting that the feature is absent.
    ///
    /// What still has to hold is the direction and the bound: a dark well must stay dark enough to
    /// read as a hole rather than a plate, and a light one light enough. The bound that actually
    /// protects the caption is arithmetic rather than rendered, and lives in
    /// `OverlayPaletteTests.captionSurvivesAnyWallpaperThroughTheWell` — it can be stated exactly
    /// there, where here it cannot.
    ///
    /// Here it cannot because `NSVisualEffectView(.behindWindow)` has no desktop to sample inside
    /// `cacheDisplay`: offscreen it resolves to a bright fallback rather than to the wallpaper, so
    /// this render measures neither the real transmission nor the real interior. It is a sanity
    /// bound, not a measurement, and it is written to be honest about that.
    @Test("the well stays on its own side of the middle")
    func wellStaysOnItsOwnSideOfTheMiddle() throws {
        let light = try Self.hubFill(selected: 0, appearance: .aqua)
        #expect(
            light.redComponent > 0.55,
            "light well has gone dark enough to lose its near-black caption: \(light.redComponent)"
        )

        let dark = try Self.hubFill(selected: 0, appearance: .darkAqua)
        #expect(
            dark.redComponent < 0.45,
            "dark well is too light to read as a hole: \(dark.redComponent)"
        )
        #expect(
            dark.redComponent < light.redComponent,
            "the two schemes' wells are the same value: \(dark.redComponent) / \(light.redComponent)"
        )
    }

    /// Turn-0 wedges sit at exactly `hubRadius` and their shadow blurs inward. The well has
    /// to draw *in front* of them so that bleed cannot darken the caption. Measured on a
    /// full circular first turn in Light Mode, with no icons, so any radial darkening can
    /// only come from wedge paint.
    @Test("wedge shadows do not veil the well in Light Mode")
    func wellIsNotVeiledByWedgeShadows() throws {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = .circular
        subject.load(
            entries: (0..<8).map { index in
                WindowEntry(
                    windowID: CGWindowID(800 + index),
                    processID: pid_t(index + 1),
                    applicationName: "App \(index)",
                    applicationIcon: nil,
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 1
        )

        let hosting = NSHostingView(rootView: OverlayView(state: subject, hoveredIndex: nil))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: subject.layout.panelSize)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = subject.layout.radialHubFrame
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)

        func luminance(atRadiusFraction fraction: CGFloat) throws -> Double {
            // 3 o'clock, past the caption column (~78pt) and inside the rim, so the sample
            // cannot be type and cannot be the ring stroke.
            let radius = hub.width / 2 * fraction
            let x = hub.midX + radius
            let y = hub.midY
            let colour = try #require(
                rep.colorAt(
                    x: Int(Double(x) * scaleX),
                    y: Int(Double(y) * scaleY)
                )?.usingColorSpace(.sRGB)
            )
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(Double(colour.redComponent))
                + 0.7152 * channel(Double(colour.greenComponent))
                + 0.0722 * channel(Double(colour.blueComponent))
        }

        // Inside the opaque core, short of the fade (core ends at wellOpaqueFraction).
        // 3 o'clock, past the caption column (~78pt) so the sample cannot be type.
        let inner = try luminance(atRadiusFraction: 0.45)
        let outer = try luminance(atRadiusFraction: 0.58)
        #expect(
            abs(inner - outer) < 0.02,
            "caption band darkened relative to the well: r=45% L=\(inner) vs r=58% L=\(outer)"
        )
    }

    /// The ring has to sit on the well as a visible band of cyan, not as a 3pt seam
    /// lost under the wedges. Sampled at the inset centre-line.
    @Test("the inset ring is painted on the well")
    func ringIsVisibleOnTheWell() throws {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = .circular
        subject.load(
            entries: (0..<8).map { index in
                WindowEntry(
                    windowID: CGWindowID(800 + index),
                    processID: pid_t(index + 1),
                    applicationName: "App \(index)",
                    applicationIcon: nil,
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 1
        )

        let hosting = NSHostingView(rootView: OverlayView(state: subject, hoveredIndex: nil))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: subject.layout.panelSize)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = subject.layout.radialHubFrame
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)
        func pixel(dx: CGFloat, dy: CGFloat) throws -> NSColor {
            try #require(
                rep.colorAt(
                    x: Int((Double(hub.midX) + Double(dx)) * scaleX),
                    y: Int((Double(hub.midY) + Double(dy)) * scaleY)
                )?.usingColorSpace(.sRGB)
            )
        }

        let hubR = hub.width / 2
        let ringR = hubR - HubChrome.ringInset
        let interior = try pixel(dx: 0, dy: hubR * 0.32)
        #expect(
            Double(interior.redComponent) < 0.35,
            "expected a dark well, got R=\(interior.redComponent)"
        )

        // On the selected lobe — the opposite side of the halo is supposed to be gone.
        let angle = subject.radialRingAngle
        let rim = try pixel(
            dx: ringR * CGFloat(cos(angle)),
            dy: ringR * CGFloat(sin(angle))
        )
        #expect(
            Double(rim.blueComponent) > Double(interior.blueComponent) + 0.04,
            "halo is no brighter than the well: well B=\(interior.blueComponent) rim B=\(rim.blueComponent)"
        )
    }

    /// The mock hub is a void, not a cream disc with a stroke around it. A Light Mode
    /// hosting view composites onto white, which is the same colour as the well, so the
    /// desktop behind the overlay has to be a colour the plate cannot be — then the
    /// fade is the green showing through past `wellClearFraction`.
    @Test("the well has no outlined plate in Light Mode")
    func wellRimIsNotAPlate() throws {
        let subject = OverlayState()
        subject.availableContentWidth = 1400
        subject.availableContentHeight = 860
        subject.layoutStyle = .circular
        subject.load(
            entries: (0..<8).map { index in
                WindowEntry(
                    windowID: CGWindowID(800 + index),
                    processID: pid_t(index + 1),
                    applicationName: "App \(index)",
                    applicationIcon: nil,
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 1
        )

        let size = subject.layout.panelSize
        let hosting = NSHostingView(rootView: ZStack {
            Color.green
            OverlayView(state: subject, hoveredIndex: nil)
        }.frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = subject.layout.radialHubFrame
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)
        let hubR = hub.width / 2

        func sample(dx: CGFloat, dy: CGFloat) throws -> NSColor {
            try #require(
                rep.colorAt(
                    x: Int((Double(hub.midX) + Double(dx)) * scaleX),
                    y: Int((Double(hub.midY) + Double(dy)) * scaleY)
                )?.usingColorSpace(.sRGB)
            )
        }

        let corner = try #require(
            rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB)
        )
        let core = try sample(dx: hubR * 0.30, dy: 0)
        // Past the fade, short of the ring, on the side opposite the selection lobe
        // so a peaked halo cannot masquerade as a plate.
        //
        // Derived from the two constants that bound that band rather than from a fraction, because
        // the fraction was wrong. `(wellClearFraction + 1) / 2` is 0.94 of the hub radius, and the
        // ring's centreline sits at `1 - ringInset / hubRadius`, which is 0.927 here: the "void"
        // sample was landing *on the rim*, one percent outside its centre. It passed only while the
        // rim was too dim to cover the desktop there, and started failing the moment the rim was
        // brightened to the reference's measured luminance — reporting a plate because the ring had
        // become properly visible, which is the opposite of what this guards.
        let fadeEnd = hubR * HubChrome.wellClearFraction
        let ringInnerEdge = hubR - HubChrome.ringInset - HubChrome.ringGlowThickness / 2
        let voidR = (fadeEnd + ringInnerEdge) / 2
        let opposite = subject.radialRingAngle + .pi
        let through = try sample(
            dx: voidR * CGFloat(cos(opposite)),
            dy: voidR * CGFloat(sin(opposite))
        )
        let coreChroma = Double(core.greenComponent) - Double(core.redComponent)
        let voidChroma = Double(through.greenComponent) - Double(through.redComponent)
        let cornerChroma = Double(corner.greenComponent) - Double(corner.redComponent)
        let report = """
            corner R=\(corner.redComponent) G=\(corner.greenComponent) B=\(corner.blueComponent) chroma=\(cornerChroma)
            core R=\(core.redComponent) G=\(core.greenComponent) B=\(core.blueComponent) chroma=\(coreChroma)
            void R=\(through.redComponent) G=\(through.greenComponent) B=\(through.blueComponent) chroma=\(voidChroma)
            """

        // Stated against the wallpaper's own chroma rather than as a fixed margin over the caption
        // surface, because the fixed margin stopped measuring what this test is for.
        //
        // The void sample sits 5.6pt inside the rim, which is inside the rim's *glow* — necessarily,
        // since the glow now crests on the centreline and decays inward, and the well's fade and
        // that decay overlap by design. Glow is near-white in Light Mode, so it dilutes whatever hue
        // is behind it, and a bound of "0.20 of chroma above the caption surface" was really a bound
        // on how bright the rim was allowed to be. The references do the same thing and it is
        // invisible in them only because their canvas is already light: at this radius the light
        // reference is 74% of the way from its interior to its rim, and ours is 68%.
        //
        // What still distinguishes a void from a plate is that the wallpaper is *there* — a plate
        // would pass none of it, and the caption surface next to it passes only what the scrim
        // allows. So: a quarter of the desktop's own hue survives in the annulus, and the annulus is
        // clearly more chromatic than the surface the type sits on.
        #expect(voidChroma > cornerChroma * 0.22, "hub rim reads as a plate\n\(report)")
        #expect(voidChroma > coreChroma + 0.12, "hub rim reads as a plate\n\(report)")
    }

    /// The reference halo has comparable radial reach on both sides of the rim. Render the real
    /// high-count overlay on black, away from the coupling, and require both the replacement
    /// inward bloom and real outward blur to rise above quiet regions. The outward quiet sample
    /// runs through an angular wedge seam because the halo intentionally continues under turn 0.
    @Test("the crowded dark hub glows inward and outward")
    func crowdedHubHasBilateralGlow() throws {
        let subject = OverlayState()
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        subject.availableContentWidth = OverlayPlacement.availableContentWidth(
            visibleFrame: visibleFrame
        )
        subject.availableContentHeight = OverlayPlacement.availableContentHeight(
            visibleFrame: visibleFrame,
            style: .spiral
        )
        subject.layoutStyle = .spiral
        subject.load(
            entries: (0..<20).map { index in
                WindowEntry(
                    windowID: CGWindowID(1_200 + index),
                    processID: pid_t(index + 1),
                    applicationName: "App \(index)",
                    applicationIcon: nil,
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 1
        )

        let size = subject.layout.panelSize
        let hosting = NSHostingView(rootView: ZStack {
            Color.black
            OverlayView(state: subject, hoveredIndex: nil)
        }.frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = subject.layout.radialHubFrame
        let geometry = try #require(subject.layout.radial)
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)
        func sample(radius: CGFloat, angle: Double) throws -> NSColor {
            let x = hub.midX + radius * CGFloat(cos(angle))
            let y = hub.midY + radius * CGFloat(sin(angle))
            return try #require(
                rep.colorAt(
                    x: Int(Double(x) * scaleX),
                    y: Int(Double(y) * scaleY)
                )?.usingColorSpace(.sRGB)
            )
        }

        let hubR = hub.width / 2
        let ringR = hubR - HubChrome.ringInset
        // Horizontal samples are outside the caption and unaffected by AppKit's flipped bitmap
        // coordinates. Seat 1's coupling is centred at −22.5°. The 0° ray is the angular seam
        // between seats 1 and 2, so it provides a quiet comparison within the wedge stack even
        // though there is intentionally no radial clear annulus before turn 0.
        let core = try sample(radius: hubR * 0.50, angle: .pi / 2)
        let inward = try sample(radius: ringR - HubChrome.ringGlowBlur, angle: 0)
        let outward = try sample(radius: hubR + 4, angle: 0)
        let outerQuiet = try sample(
            radius: geometry.firstRingRadius + geometry.ringThickness * 0.65,
            angle: 0
        )

        #expect(
            Double(inward.greenComponent) > Double(core.greenComponent) + 0.025,
            "inward half missing: core G=\(core.greenComponent), inward G=\(inward.greenComponent)"
        )
        #expect(
            Double(outward.greenComponent) > Double(outerQuiet.greenComponent) + 0.02,
            "outward half missing: seam G=\(outerQuiet.greenComponent), outward G=\(outward.greenComponent)"
        )
    }

    /// The void between the ring and the first card has to read as lit atmosphere, not as a hole.
    ///
    /// This is the regression a blurred stroke could not hold. Its glow reached only the band's
    /// own outer edge — the blur did not survive rasterisation — so the render carried a measured
    /// pure-black annulus roughly 12pt wide directly in front of the cards, while the reference
    /// decays smoothly from about L=130 at the rim to L=20 at the wedge's inner arc.
    ///
    /// Nothing is seated inside `seat(at: 0).innerRadius`, so every radius sampled here is void
    /// at every angle; 180° keeps the probe off the coupling and the caption.
    @Test("the void between the ring and the first card is lit the whole way across")
    func voidCarriesGlowToTheFirstCard() throws {
        let subject = OverlayState()
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 950)
        subject.availableContentWidth = OverlayPlacement.availableContentWidth(
            visibleFrame: visibleFrame
        )
        subject.availableContentHeight = OverlayPlacement.availableContentHeight(
            visibleFrame: visibleFrame,
            style: .spiral
        )
        subject.layoutStyle = .spiral
        subject.load(
            entries: (0..<16).map { index in
                WindowEntry(
                    windowID: CGWindowID(1_400 + index),
                    processID: pid_t(index + 1),
                    applicationName: "App \(index)",
                    applicationIcon: nil,
                    title: "Window \(index)",
                    frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                    isMinimized: false,
                    zOrder: index,
                    axElement: nil
                )
            },
            selectedIndex: 1
        )

        let size = subject.layout.panelSize
        let hosting = NSHostingView(rootView: ZStack {
            Color.black
            OverlayView(state: subject, hoveredIndex: nil)
        }.frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let hub = subject.layout.radialHubFrame
        let geometry = try #require(subject.layout.radial)
        let scaleX = Double(rep.pixelsWide) / Double(hosting.bounds.width)
        let scaleY = Double(rep.pixelsHigh) / Double(hosting.bounds.height)
        func green(atRadius radius: CGFloat) throws -> Double {
            let x = hub.midX + radius * CGFloat(cos(Double.pi))
            let y = hub.midY + radius * CGFloat(sin(Double.pi))
            let colour = try #require(
                rep.colorAt(
                    x: Int(Double(x) * scaleX),
                    y: Int(Double(y) * scaleY)
                )?.usingColorSpace(.sRGB)
            )
            return Double(colour.greenComponent)
        }

        let seat0 = geometry.seat(at: 0).innerRadius
        #expect(seat0 > geometry.hubRadius, "fixture must leave a void to sample")

        let justOutsideHub = try green(atRadius: geometry.hubRadius + 2)
        let middle = try green(atRadius: (geometry.hubRadius + seat0) / 2)
        let atCardEdge = try green(atRadius: seat0 - 1)

        // Lit, not black — the whole point.
        #expect(atCardEdge > 0.04, "void goes dark before the cards: G=\(atCardEdge)")
        #expect(middle > 0.07, "void is unlit mid-gap: G=\(middle)")
        #expect(justOutsideHub > 0.12, "no bloom outside the rim: G=\(justOutsideHub)")
        // And decaying outward, so it reads as glow rather than as a painted collar.
        #expect(justOutsideHub > middle)
        #expect(middle > atCardEdge)
    }
}
