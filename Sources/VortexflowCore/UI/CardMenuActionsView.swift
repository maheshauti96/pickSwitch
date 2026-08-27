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

/// The row of glyph buttons under a card's context menu header.
///
/// Separate from `CardMenuHeaderView`, and separate for a reason that is not tidiness: the header is a
/// label and this is a set of controls. A menu item's custom view is responsible for its own event
/// handling, so the header's item is disabled with hit testing switched off — anything else lets it
/// swallow the click on its way to the tracking loop — while this one has to be enabled and live.
/// Merging them would mean one item that is both inert and interactive.
struct CardMenuActionsView: View {

    let actions: [CardMenuItem]
    @ObservedObject var hover: CardMenuHoverModel
    /// Invoked with the chosen action. The caller ends menu tracking; this view does not know it is
    /// in a menu.
    let onAction: (CardMenuItem) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                if let icon = action.icon {
                    Button {
                        onAction(action)
                    } label: {
                        label(icon: icon, isHovered: hover.hoveredIndex == index)
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
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(width: CardMenuHeaderView.width)
    }

    private func label(icon: CardMenuItem.Icon, isHovered: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(height: 15)
            Text(icon.label)
                .font(.system(size: 9.5))
                .lineLimit(1)
                // The row divides a fixed width by however many actions survived the omission rules,
                // so a five-action window gives each caption less room than a three-action one.
                // Shrinking beats truncating "Minimize" to "Minim…".
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.accentColor : .clear)
        )
        // The gap between the glyph and its caption is still part of the button.
        .contentShape(Rectangle())
    }
}
