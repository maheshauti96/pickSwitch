import AppKit
import Combine
import SwiftUI

/// Which glyph the pointer is over, held outside the view.
///
/// An `ObservableObject` rather than a view-local `@State` for the reason `OverlayState` and
/// `SettingsViewModel` already give: `@State` is a macro in the current SwiftUI and this toolchain
/// does not load its plugin, so a view that uses it will not build with Command Line Tools.
///
/// One index for the whole row rather than a flag per button, which also makes the invariant
/// structural: two glyphs cannot both believe they are hovered.
final class CardMenuHoverModel: ObservableObject {
    @Published var hoveredIndex: Int?
}

/// A row of glyph buttons in a card's context menu.
///
/// Separate from `CardMenuHeaderView`, and separate for a reason that is not tidiness: the header is a
/// label and this is a set of controls. A menu item's custom view is responsible for its own event
/// handling, so the header's item is disabled with hit testing switched off — anything else lets it
/// swallow the click on its way to the tracking loop — while these rows have to be enabled and live.
/// Merging them would mean one item that is both inert and interactive.
struct CardMenuGlyphRow: View {

    /// How the glyphs are named.
    enum Caption: Equatable {
        /// A word under every glyph. Fine for two or three wide actions.
        case perGlyph
        /// One line above the row, carrying this title until the pointer is over a glyph and that
        /// glyph's name after.
        ///
        /// Six window controls cannot each carry a legible word inside a fixed-width menu — the
        /// captions would be four points tall or truncated to "Botto…". Naming only the one being
        /// pointed at keeps the row compact without going back to bare glyphs the user has to guess
        /// at, and the line is always present so nothing moves when the pointer arrives.
        case shared(String)
    }

    let actions: [CardMenuItem]
    let caption: Caption
    @ObservedObject var hover: CardMenuHoverModel
    /// Invoked with the chosen action. The caller ends menu tracking; this view does not know it is
    /// in a menu.
    let onAction: (CardMenuItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if case .shared(let title) = caption {
                Text(hoveredTitle ?? title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            row
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        // Leading, so the controls sit at the top-left corner of the block above the preview rather
        // than spread across it.
        .frame(width: CardMenuHeaderView.width, alignment: .leading)
    }

    private var hoveredTitle: String? {
        hover.hoveredIndex.flatMap { index in
            actions.indices.contains(index) ? actions[index].title : nil
        }
    }

    private var row: some View {
        HStack(spacing: perGlyph ? 2 : 4) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button {
                    onAction(action)
                } label: {
                    label(for: action, isHovered: hover.hoveredIndex == index)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        hover.hoveredIndex = index
                    } else if hover.hoveredIndex == index {
                        hover.hoveredIndex = nil
                    }
                }
                .accessibilityLabel(action.title)
            }
            // Only the captioned row divides the full width between its glyphs; a shared-caption row
            // packs them at the leading edge.
            if !perGlyph { Spacer(minLength: 0) }
        }
    }

    private var perGlyph: Bool { caption == .perGlyph }

    /// Closing is red before it is hovered, not only once the pointer is on it.
    ///
    /// The point is to be seen on the way past. The cross sits immediately beside the minus, which is
    /// the pair most easily confused in a row of identical glyphs, and a warning that only appears
    /// after you have already aimed at the thing is not a warning.
    private func foreground(for action: CardMenuItem, isHovered: Bool) -> AnyShapeStyle {
        if isHovered { return AnyShapeStyle(.white) }
        return action.isDestructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary)
    }

    private func highlight(for action: CardMenuItem, isHovered: Bool) -> Color {
        guard isHovered else { return .clear }
        return action.isDestructive ? .red : .accentColor
    }

    private func label(for action: CardMenuItem, isHovered: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: action.icon.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(height: 15)
            if perGlyph {
                Text(action.icon.label)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    // The row divides a fixed width by however many actions survived the omission
                    // rules, so a three-action window gives each caption less room than a two-action
                    // one. Shrinking beats truncating "Minimize" to "Minim…".
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(foreground(for: action, isHovered: isHovered))
        .frame(maxWidth: perGlyph ? .infinity : nil)
        .frame(width: perGlyph ? nil : 28)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(highlight(for: action, isHovered: isHovered))
        )
        // The gap between a glyph and its caption is still part of the button.
        .contentShape(Rectangle())
    }
}
