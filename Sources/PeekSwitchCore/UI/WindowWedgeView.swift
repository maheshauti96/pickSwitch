import AppKit
import SwiftUI

/// One window as a wedge of the spiral.
///
/// ## Why this is not `WindowCardView`
///
/// A card is a rectangle that contains its own contents. A wedge is an annular sector whose
/// position is an angle, and whose contents sit in an upright box inside it — the box is not
/// the shape, and the shape is not the layout unit. Bending the card view to draw both would
/// mean a rectangle that is sometimes not a rectangle.
///
/// The view is sized to the whole panel and paints only its own sector, for the reason given
/// on `WedgeShape`: drawing and hit-testing are then computed from one description of the
/// ring instead of two.
///
/// ## Why there is no thumbnail
///
/// A rectangular screenshot clipped to a wedge is unreadable, so the spiral shows application
/// icons in both view modes and nothing is captured for it — see
/// `OverlayLayoutStyle.canShowThumbnails`. The window's *title* is not shown here either;
/// there is no room for it at roughly 76pt of arc. The hub carries it instead.
struct WindowWedgeView: View {

    let entry: WindowEntry
    /// Favicon for a matched browser window, otherwise the application's own icon.
    let displayIcon: NSImage?
    let seat: RadialLayout.Seat
    /// Centre of the arrangement in panel coordinates.
    let centre: CGPoint
    /// Size of the panel, which is also this view's size.
    let panelSize: CGSize
    let isSelected: Bool
    let isHovered: Bool
    let badgeCount: Int?
    let reduceMotion: Bool
    var metrics: OverlayCardMetrics = .spiral
    /// Which screen this window is on, when there is more than one. Spoken by VoiceOver only.
    var display: DisplayInfo?
    /// Whether this is a private browsing window.
    var isIncognito: Bool = false
    /// Hue taken from this window's icon, so a ring of same-application wedges is still
    /// distinguishable. `nil` leaves the flat palette fill.
    var tint: IconTint?
    /// The spiral draws no plate, so each wedge lifts itself off the desktop.
    var shadowRadius: CGFloat = 9
    var shadowOpacity: Double = 0.34
    /// Increase Contrast drops the glass and paints an opaque card: a decorative
    /// material is the opposite of what that setting asked for.
    var increaseContrast: Bool = false

    @Environment(\.overlayPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        // Selected is a stronger self, not a recolor to the brand. The brand lives on the hub
        // ring, which is the one signal that does not shift hue with the window under the pointer.
        if isSelected { return palette.radialSelectedFill(tintedBy: tint) }
        if isHovered { return palette.selectedCardFill(tintedBy: tint) }
        return palette.cardFill(tintedBy: tint)
    }

    private var borderColor: Color {
        if isSelected { return palette.accent }
        if isHovered { return palette.strongBorder }
        return palette.border
    }

    private var borderWidth: CGFloat {
        if isSelected { return reduceMotion ? 3 : 2 }
        return 1
    }

    /// The selected fill is still a card, not the accent, so type stays on the palette's
    /// text colours. Switching to `onAccentText` here would be the previous treatment,
    /// when this wedge was painted `#00789b`.
    private var textColor: Color {
        palette.text
    }

    private var secondaryColor: Color {
        palette.secondaryText
    }

    /// The selected wedge pops its icon rather than scaling the wedge.
    ///
    /// Scaling the wedge would move it: a sector is positioned by angle and radius, and
    /// growing it about the centre of its bounding box slides it off the ring and over its
    /// neighbours, while hit-testing carried on using the un-scaled angles. Growing only the
    /// contents gives the same "this one is live" read and moves no geometry.
    private var iconScale: CGFloat {
        guard isSelected, !reduceMotion else { return 1 }
        return 1.12
    }

    private var shape: WedgeShape {
        WedgeShape(seat: seat, centre: centre, cornerRadius: metrics.cornerRadius)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Only the glass casts a shadow. Shadowing the whole stack would blur the
            // specular and the label along with it.
            glass
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: shadowRadius,
                    y: shadowRadius / 2
                )

            glassLighting
            glassRims

            content
                .frame(width: seat.contentFrame.width, height: seat.contentFrame.height)
                .position(x: seat.contentFrame.midX, y: seat.contentFrame.midY)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Tinted liquid glass, or an opaque card when Increase Contrast is on.
    ///
    /// The mock's wedges are stained-glass volumes, not grey material with a 1px border.
    /// Native `glassEffect` tint is only a hint, so the wash is painted on top in both
    /// the macOS 26 path and the fallback — without it Dark Mode tiles read as slate.
    @ViewBuilder
    private var glass: some View {
        if increaseContrast {
            shape.fill(fill)
            shape.stroke(borderColor, lineWidth: borderWidth)
        } else {
            if #available(macOS 26.0, *) {
                NativeWedgeGlass(shape: shape, tint: glassTint, panelSize: panelSize)
            } else {
                shape.fill(.ultraThinMaterial)
            }
            shape.fill(glassTint.opacity(glassWash))
            if isSelected {
                shape.fill(palette.hubRing.opacity(colorScheme == .dark ? 0.22 : 0.10))
            }
        }
    }

    private var glassWash: Double {
        palette.glassWashOpacity(selected: isSelected, scheme: colorScheme)
    }

    /// Thickness lighting: a glass slab lit on both of its arcs, darkest through the middle.
    ///
    /// Traced from the references rather than chosen. Sampling a dark reference card along its own
    /// radius, normalised to the darkest part of its body, gives 5.1x at the inner arc, 2.0x a
    /// eighth of the way out, a floor from about 0.3 to 0.7 of the depth, then back up through
    /// 1.9x to 4.4x at the outer arc.
    ///
    /// The outer half is the part that was missing. This gradient used to end on
    /// `black.opacity(0.28)` — actively darkening the outer edge — so the cards were lit from one
    /// side only, which is how a pane of glass does not behave and is most of why they read as flat
    /// tinted plates with a bright line on the inside rather than as volumes.
    ///
    /// Light Mode is deliberately much flatter. The light reference's cards measure essentially
    /// constant across their depth (luminance 238, chroma 16) with only a soft edge at the rim: on
    /// a near-white plate a strong catch has nowhere to go but blown-out white, so the edge does the
    /// separating there and the body stays even.
    private var glassLighting: some View {
        shape
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: colorScheme == .light
                        ? [
                            .init(color: .white.opacity(0.26), location: 0),
                            .init(color: .white.opacity(0.10), location: 0.13),
                            .init(color: .white.opacity(0.04), location: 0.38),
                            .init(color: .white.opacity(0.03), location: 0.68),
                            .init(color: .white.opacity(0.10), location: 1),
                        ]
                        : [
                            .init(color: .white.opacity(0.46), location: 0),
                            .init(color: .white.opacity(0.16), location: 0.13),
                            .init(color: .white.opacity(0.05), location: 0.34),
                            .init(color: .white.opacity(0.02), location: 0.62),
                            .init(color: .white.opacity(0.10), location: 0.86),
                            .init(color: .white.opacity(0.32), location: 1),
                        ]
                    ),
                    center: UnitPoint(
                        x: centre.x / max(1, panelSize.width),
                        y: centre.y / max(1, panelSize.height)
                    ),
                    startRadius: seat.innerRadius,
                    endRadius: seat.outerRadius
                )
            )
            .blendMode(.overlay)
            .opacity(increaseContrast ? 0 : 1)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var glassRims: some View {
        let inner = WedgeInnerArc(seat: seat, centre: centre, cornerRadius: metrics.cornerRadius)
        let outer = WedgeOuterArc(seat: seat, centre: centre, cornerRadius: metrics.cornerRadius)
        let rim = palette.glassRim(for: tint, selected: isSelected, scheme: colorScheme)
        // Wider in Dark Mode, and the two schemes want opposite things here.
        //
        // Measured with one routine over both references — inner-arc peak against the darkest point
        // of the same card's own body — the dark reference catches 6.81x its body on the inner arc
        // and 4.02x on the outer, while the light one catches 1.05x and 1.03x. That is not a
        // difference of degree: a dark card is lit by its edges, and a light card is a pale plate
        // whose edges only just separate it from its neighbour. Rendering the same widths into both
        // gave 3.77x and 3.60x in Dark Mode — about half the light the reference catches inward, and
        // an inner arc barely brighter than the outer, so the wedges read as evenly lit tiles rather
        // than as slabs with a bright hub-facing face.
        let arcScale: CGFloat = colorScheme == .dark ? 1.6 : 1.0
        let innerWidth: CGFloat = {
            if isSelected { return HubChrome.selectedInnerArcWidth * arcScale }
            if isHovered { return (HubChrome.innerArcWidth + 0.4) * arcScale }
            return HubChrome.innerArcWidth * arcScale
        }()

        // Glass catch, not a border. The mock's inner edge is a blurred hue
        // (Chrome green, Slack pink); a 1px white stroke is what made live
        // tiles read as outlined cards.
        //
        // Softened against a measurement: the reference's inner arc peaks at 2.56x its own card
        // body, ours at 5.22x, which is the difference between light caught on a glass edge and a
        // line drawn round a dark plate. Most of that closes once the body is lit properly; the
        // rest is here, in a wider blur over a narrower, quieter stroke.
        // Scheme-aware, because the body it is caught on differs: over a dark tile the arc has to
        // carry the reference's 2.56x catch, while a light tile is already bright enough that the
        // same strength would overshoot the 1.04x measured there.
        //
        // Dark Mode raised against that same measurement. `glassRim` resolves to about luminance 200
        // in Dark Mode, so an arc drawn at 0.50 over a 23-luminance body can only reach 111 — the
        // reference's 173 is not available at that opacity whatever the blur does. 0.86 puts it
        // there arithmetically, and the blur below is what decides how much of it survives.
        let rimOpacity: Double = {
            if colorScheme == .dark {
                return isSelected ? 0.96 : (isHovered ? 0.90 : 0.86)
            }
            // Light Mode moves much less: its arcs measured 239 against the reference's 249 on a body
            // that already matched, so this is a few levels of separation rather than a rebuild.
            return isSelected ? 0.86 : (isHovered ? 0.80 : 0.72)
        }()

        // Blurred wide, because the width is what decides whether this reads as a catch or as an
        // outline. In the references the hue on the inner edge falls from luminance 128 to 50 over
        // about 14pt — a broad gradient the eye takes as light pooling against a curved face. At a
        // 3pt blur over a 3.2pt stroke the same colour occupies about 6pt, which is a drawn line,
        // and no amount of lowering its opacity changes that: a dim line is still a line.
        //
        // Blurred wide, but no longer wider than the stroke it blurs. That is the same arithmetic
        // that was costing the hub ring its peak: a Gaussian keeps only the kernel mass that falls
        // inside the stroke's own half-width, so a 3.2pt stroke under a 6.5pt blur throws most of its
        // brightness into a haze either side and the "catch" it draws is a smear. Kept broad enough
        // to still be light pooling rather than a line — the reference's hue falls off over about
        // 14pt — but now proportioned to a stroke wide enough to feed it.
        inner
            .stroke(rim.opacity(rimOpacity), lineWidth: innerWidth)
            .blur(radius: colorScheme == .dark ? (isSelected ? 5.0 : 4.2) : (isSelected ? 7.5 : 6.5))

        // A whiter core inside the hued catch, which is also what makes the inner arc the brighter of
        // the two.
        //
        // The reference's arcs are not the same light: its inner one peaks at luminance 173 carrying
        // 0.12–0.21 saturation while the outer peaks at 149 — brighter *and* paler, which is what
        // light does when it pools hard enough to start washing out. Opacity on the hued stroke alone
        // cannot produce that, because `glassRim` has a fixed saturation and adding more of it only
        // makes the arc more coloured. At 0.07 this stroke was contributing nothing and the two arcs
        // measured within 1 luminance of each other.
        inner
            .stroke(Color.white.opacity(colorScheme == .light ? 0.16 : 0.20), lineWidth: 2.4)
            .blur(radius: 2.1)

        // The outer arc is a rim, not an afterthought.
        //
        // In the references the outer edge is nearly as bright as the inner one — 4.4x the card's
        // body against the inner arc's 5.1x — and that symmetry is what makes a wedge read as a
        // slab of glass with light caught on both curved faces. This stroke was carrying 0.06 in
        // Dark Mode, which measured 1.5x: effectively nothing, so the cards were lit from the hub
        // side and simply stopped at their far edge.
        //
        // Dark Mode raised and widened for the same reason as the inner arc: the reference catches
        // 4.02x its body out here and this stroke was managing 3.60x on a body that had itself just
        // been halved, so in absolute terms it was drawing 88 luminance against the reference's 149.
        outer
            .stroke(
                Color.white.opacity(colorScheme == .light ? 0.30 : 0.50),
                lineWidth: colorScheme == .dark ? 4.2 : 2.6
            )
            .blur(radius: colorScheme == .dark ? 3.0 : 2.4)

        if isSelected {
            inner
                .stroke(palette.hubRing.opacity(colorScheme == .dark ? 0.55 : 0.38), lineWidth: 7)
                .blur(radius: 5)
        }
    }

    private var glassTint: Color {
        palette.glassTint(for: tint, selected: isSelected, scheme: colorScheme)
    }

    // MARK: - Contents

    /// Height the name needs for its two lines.
    ///
    /// A radial label never degrades to one truncated line: it either gets enough room to wrap
    /// or, once the arrangement is too small, disappears and leaves identification to the icon
    /// and hub caption.
    /// Two lines of name plus the leading between them, and no more.
    ///
    /// Every point reserved here is a point the icon does not get, and the icon is what identifies
    /// a window from across the ring. Two lines at 11pt need 26pt; the label was given 28.
    private var nameBandHeight: CGFloat {
        metrics.titleFontSize * 2 + 4
    }

    private var badgeRowHeight: CGFloat { badgeSize + 1 }

    /// Everything below the icon: the name, and the badge row when one is drawn.
    private var labelBandHeight: CGFloat {
        nameBandHeight + (showsBadges ? badgeRowHeight : 0)
    }

    private var contentSpacing: CGFloat { 1 }

    /// The icon is the faster identifier and must stay usable, so the label only appears while
    /// this much of the box is still left for it.
    private var minimumLabeledIconHeight: CGFloat { 24 }

    /// The icon a badge row is allowed to leave behind, which is deliberately more generous than
    /// the floor for the name.
    ///
    /// Without the wider margin, enlarging the box made things worse rather than better on a busy
    /// ring: at 80% scale the badge row began to fit where it previously had not, and paying for it
    /// left a *smaller* icon than before. A marker is worth less than the icon it shrinks.
    private var minimumBadgedIconHeight: CGFloat { 34 }

    private var showsLabel: Bool {
        metrics.size.height >= nameBandHeight + contentSpacing + minimumLabeledIconHeight
    }

    /// Badges are the first thing to go: they occupy a row of their own, and that row is worth less
    /// than the icon it would otherwise shrink.
    private var showsBadges: Bool {
        guard hasBadges, showsLabel else { return false }
        return metrics.size.height
            >= nameBandHeight + badgeRowHeight + contentSpacing + minimumBadgedIconHeight
    }

    @ViewBuilder
    private var content: some View {
        if showsLabel {
            VStack(spacing: contentSpacing) {
                icon
                label
            }
        } else {
            icon
        }
    }

    /// Reserve the label's full two-line band first, then give the remaining height to the icon.
    /// Without a label the icon may use the whole box, keeping a shrunken arrangement legible.
    private var iconBandHeight: CGFloat {
        showsLabel
            ? max(0, metrics.size.height - labelBandHeight - contentSpacing)
            : metrics.size.height
    }

    private var iconSide: CGFloat {
        min(metrics.artworkIconSize, iconBandHeight)
    }

    private var icon: some View {
        ZStack {
            if let applicationIcon = displayIcon {
                // `.interpolation(.high)`: a macOS icon arrives at 512pt and draws here at
                // roughly 44pt, and the default filter makes that downscale visibly mushy.
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSide, height: iconSide)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: iconSide * 0.6, weight: .light))
                    .foregroundStyle(secondaryColor)
                    .frame(width: iconSide, height: iconSide)
            }

            if entry.isMinimized {
                minimizedBadge
            }
        }
        .frame(height: iconBandHeight)
        .scaleEffect(iconScale)
    }

    /// The application name, plus whichever markers apply.
    ///
    /// ## Why the badges are on their own row
    ///
    /// They used to sit beside the name, and they quietly broke it. A wedge's content box is
    /// around 80pt wide before the arrangement scales it down, so two 8pt glyphs and their spacing
    /// take a quarter of the line — and an incognito browser window on a second display carries
    /// exactly that. "Google Chrome" was left with too little room to wrap at its space and came
    /// out as "Goog / le C…": a mid-word break *and* an ellipsis, which is the thing two-line
    /// wrapping was introduced to prevent.
    ///
    /// Giving the name the full width fixes it at the cause. The badges are markers rather than
    /// reading matter, so they lose nothing by dropping below it, and they are only drawn when
    /// there is a row's worth of height spare for them.
    private var label: some View {
        VStack(spacing: 1) {
            Text(entry.sourceLabel)
                .font(.system(size: metrics.titleFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                // A last resort before an ellipsis, and only a little: at 88% "Google Chrome"
                // still wraps to two legible lines in a wedge that has been scaled down, where
                // at full size it would have to cut a word.
                .minimumScaleFactor(0.88)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .foregroundStyle(textColor)

            if showsBadges {
                badges
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
    }

    /// Markers for this window, none of which are load-bearing enough to cost the name any width.
    ///
    /// Deliberately no screen marker. The switch animation already flies toward the display the
    /// window is on, which answers "where is it" by showing rather than labelling — and a glyph
    /// that appeared on every wedge said nothing that distinguished one from another.
    ///
    /// Deliberately no window-count badge either, unlike the other arrangements. It says how many
    /// windows an application has, which is worth knowing on a strip card that stands for several
    /// — but here every window already has its own wedge, so three Chrome windows are three
    /// visible wedges.
    private var badges: some View {
        HStack(spacing: 3) {
            if entry.isTab {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: badgeSize, weight: .semibold))
                    .foregroundStyle(secondaryColor)
            }

            if entry.isApplication {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: badgeSize, weight: .semibold))
                    .foregroundStyle(secondaryColor)
                    .help("Open installed application")
            }

            // Private browsing is marked on the icon by `PrivateWindowIcon`. A wedge has the least
            // label room of any arrangement, and this row was the worst place for the one marker
            // that changes what selecting the window means.
        }
    }

    private var badgeSize: CGFloat { 8 }

    private var hasBadges: Bool {
        entry.isTab || entry.isApplication
    }

    private var minimizedBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 8, weight: .semibold))
                    .padding(3)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [entry.applicationName, entry.displayTitle]
        if let tab = entry.tab { parts.append("tab, \(tab.host)") }
        if entry.isApplication { parts.append("installed application") }
        // The one result that leaves the switcher entirely, so it says so: every other result
        // raises something already open, and a screen reader user has no other way to tell.
        if entry.isWebSearch { parts.append("opens in your browser") }
        if isIncognito { parts.append("incognito") }
        if let display { parts.append(display.label) }
        if entry.isMinimized { parts.append("minimized") }
        if let badgeCount { parts.append("\(badgeCount) windows") }
        return parts.joined(separator: ", ")
    }
}

/// macOS 26 Liquid Glass, clipped to the wedge. The fallback in `WindowWedgeView.glass`
/// is the frosted + tinted construction used on macOS 15.
@available(macOS 26.0, *)
private struct NativeWedgeGlass: View {
    let shape: WedgeShape
    let tint: Color
    let panelSize: CGSize

    var body: some View {
        Color.clear
            .frame(width: panelSize.width, height: panelSize.height)
            .glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
    }
}
