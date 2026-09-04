import SwiftUI

/// One tile of the inner turn: a pinned shortcut's seat in the seam between hub and ring.
///
/// The same rounded sector as a window wedge, on the same angular grid, so the inner turn
/// reads as the spiral continuing inward rather than as ornaments placed in a gap. What
/// makes it secondary is the material: a muted, untinted plate rather than a pastel card,
/// a hairline border, a lighter shadow — so a pin and a window cannot be mistaken for
/// each other even before the badge. Solid, not translucent: a veil disappears on a dark
/// desktop, which is most of the time this overlay is used.
/// Deep tiles carry an icon and a name like a card; slivers carry the icon alone. The one
/// empty tile is a ghost: no fill, a dashed hairline and a light plus in the hub ring's
/// tint, which is bright in both palettes and so survives whatever wallpaper is behind it.
struct ShortcutTileView: View {
    let shortcut: PinnedShortcut?
    let favicon: NSImage?
    let seat: RadialLayout.Seat
    let centre: CGPoint
    let panelSize: CGSize
    let scale: CGFloat
    let isHovered: Bool
    let isDragging: Bool
    /// Another pin is being dragged and would land here on release.
    let isDropTarget: Bool

    @Environment(\.overlayPalette) private var palette

    private var isEmpty: Bool { shortcut == nil }
    private var isLifted: Bool { isHovered || isDropTarget }

    private var shape: WedgeShape {
        WedgeShape(seat: seat, centre: centre, cornerRadius: max(4, 9 * scale))
    }

    private var box: CGRect { seat.contentFrame }
    /// A name fits under the icon only where the tile is deep enough for both. A keyboard
    /// shortcut's "icon" already is its name, so it never repeats itself underneath.
    private var showsLabel: Bool {
        guard let shortcut, box.height >= 48 * scale else { return false }
        if case .keys = shortcut { return false }
        return true
    }

    /// The pin badge's centre: tucked into the tile's outer, clockwise corner — the radial
    /// "top-right" — inset far enough from both the arc and the ray to clear the rounding.
    private var badgeCentre: CGPoint {
        let inset = min(10 * scale, max(6, (seat.outerRadius - seat.innerRadius) * 0.28))
        let radius = seat.outerRadius - inset
        let angle = seat.endAngle - asin(Double(min(1, inset / radius)))
        return CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
    }
    private var iconSide: CGFloat {
        let room = showsLabel ? box.height - 16 * scale : min(box.width, box.height)
        return min(40 * scale, max(14, room * 0.68))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isEmpty {
                shape.fill(palette.hubRing.opacity(isLifted ? 0.10 : 0))
                shape.stroke(
                    palette.hubRing.opacity(isLifted ? 0.85 : 0.38),
                    style: StrokeStyle(lineWidth: 1, dash: isLifted ? [] : [3, 3])
                )
                .shadow(color: .black.opacity(0.35), radius: 1)
            } else {
                // Opaque, but quieter than a window card: the thumbnail grey, stepping up
                // to the card fill only under the pointer. No tint, so they never pick up
                // the pastels the ring uses to tell windows apart. The well is too dark
                // for this — in Dark Mode it is nearly black, and a pin would vanish.
                shape.fill(isHovered ? palette.cardFill : palette.thumbnailFill)
                    .shadow(color: .black.opacity(isLifted ? 0.28 : 0.18), radius: isLifted ? 7 : 4, y: 2)
                shape.stroke(
                    isDropTarget ? palette.hubRing.opacity(0.9) : (isHovered ? palette.strongBorder : palette.border),
                    lineWidth: isDropTarget ? 1.5 : 1
                )
            }

            content
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)

            // What tells a pin from a window at a glance: the tile shape is deliberately the
            // ring's, so this small mark carries the difference. Muted like everything else here.
            if !isEmpty {
                pinBadge.position(badgeCentre)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .opacity(isDragging ? 0.55 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isLifted)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isDragging)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 3 * scale) {
            icon
                .frame(width: iconSide, height: iconSide)
                // The hovered tile pops its icon the way a selected wedge does, not its shape:
                // a sector grown about its bounding box slides off the grid.
                .scaleEffect(isLifted && !isEmpty ? 1.1 : 1)
            if showsLabel, let shortcut {
                Text(shortcut.title)
                    .font(.system(size: max(9, 10 * scale), weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var pinBadge: some View {
        let side = max(12, 15 * scale)
        return ZStack {
            Circle().fill(palette.cardFill)
            Circle().strokeBorder(palette.border, lineWidth: 1)
            Image(systemName: "pin.fill")
                .font(.system(size: side * 0.5, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                // Pushed into a corkboard, not standing to attention.
                .rotationEffect(.degrees(-35))
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private var icon: some View {
        switch shortcut {
        case nil:
            Image(systemName: "plus")
                .font(.system(size: iconSide * 0.8, weight: .light))
                .foregroundStyle(palette.hubRing.opacity(isLifted ? 1 : 0.6))
        case .keys(let keys):
            Text(keys.displayName)
                .font(.system(size: iconSide * 0.5, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(palette.text.opacity(0.9))
        case .app(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        case .link:
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: iconSide * 0.2, style: .continuous))
                    .padding(iconSide * 0.1)
            } else {
                Image(systemName: "link")
                    .font(.system(size: iconSide * 0.7, weight: .regular))
                    .foregroundStyle(palette.hubSecondaryText)
            }
        }
    }
}

/// The plus that sits in the leftover gap after the last first-turn pin — a mark, not a card.
struct ShortcutPlusView: View {
    let frame: CGRect
    let isHovered: Bool

    @Environment(\.overlayPalette) private var palette

    var body: some View {
        ZStack {
            Circle().fill(palette.hubRing.opacity(isHovered ? 0.10 : 0))
            Circle()
                .strokeBorder(
                    palette.hubRing.opacity(isHovered ? 0.85 : 0.38),
                    style: StrokeStyle(lineWidth: 1, dash: isHovered ? [] : [2.5, 3])
                )
            Image(systemName: "plus")
                .font(.system(size: frame.width * 0.42, weight: .light))
                .foregroundStyle(palette.hubRing.opacity(isHovered ? 1 : 0.6))
        }
        .frame(width: frame.width, height: frame.height)
        .shadow(color: .black.opacity(0.35), radius: 1)
        .scaleEffect(isHovered ? 1.08 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        .position(x: frame.midX, y: frame.midY)
    }
}
