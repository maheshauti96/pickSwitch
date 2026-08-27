import AppKit
import Combine
import SwiftUI

/// Which glyph the pointer is over, held outside the view.
///
/// An `ObservableObject` rather than a view-local `@State` for the reason `OverlayState` and
/// `SettingsViewModel` already give: `@State` is a macro in the current SwiftUI and this toolchain
/// does not load its plugin, so a view that uses it will not build with Command Line Tools.
///
/// Keyed on the action rather than on a position, so one model serves every group in the menu — the
/// two title-bar controls in one corner, the tiling pair in another, the content actions in a row.
/// Keying on an index would have needed a model per group and would have let two groups both believe
/// their first glyph was hovered.
final class CardMenuHoverModel: ObservableObject {

    @Published private var hoveredKey: String?

    func isHovered(_ action: CardMenuItem) -> Bool {
        hoveredKey == Self.key(action)
    }

    func setHovered(_ action: CardMenuItem, _ inside: Bool) {
        let key = Self.key(action)
        if inside {
            hoveredKey = key
        } else if hoveredKey == key {
            hoveredKey = nil
        }
    }

    /// The action's own sentence. Unique across everything one menu can show, and already written for
    /// VoiceOver, so it needs no second identifier kept in step with it.
    private static func key(_ action: CardMenuItem) -> String { action.title }
}

/// One glyph button.
///
/// Shared by the corner groups inside `CardMenuHeaderView` and by the captioned row below it, so a
/// button's size, hover behaviour and destructive colouring are decided once. The two placements
/// differ only in whether the caption is drawn.
struct CardMenuGlyphButton: View {

    let action: CardMenuItem
    /// Draw the word under the glyph. False in the corners, where there is no room for it and the
    /// position carries the meaning instead.
    var showsCaption: Bool = false
    /// Fill the width available, for a row that divides itself between its glyphs.
    var fillsWidth: Bool = false
    @ObservedObject var hover: CardMenuHoverModel
    let onAction: (CardMenuItem) -> Void

    var body: some View {
        Button {
            onAction(action)
        } label: {
            content
        }
        .buttonStyle(.plain)
        .onHover { hover.setHovered(action, $0) }
        .accessibilityLabel(action.title)
        // Harmless if a menu never shows it, and the only naming the corner glyphs get.
        .help(action.title)
    }

    private var content: some View {
        let isHovered = hover.isHovered(action)
        return VStack(spacing: 3) {
            Image(systemName: action.icon.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(height: 15)
            if showsCaption {
                Text(action.icon.label)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    // The row divides a fixed width by however many actions survived the omission
                    // rules, so shrinking beats truncating a caption to "Minim…".
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(foreground(isHovered: isHovered))
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .frame(width: fillsWidth ? nil : 26)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(highlight(isHovered: isHovered))
        )
        // The gap between a glyph and its caption is still part of the button.
        .contentShape(Rectangle())
    }

    /// Closing is red before it is hovered, not only once the pointer is on it.
    ///
    /// The point is to be seen on the way past. Close sits immediately beside minimize, and a warning
    /// that only appears after you have already aimed at the thing is not a warning.
    private func foreground(isHovered: Bool) -> AnyShapeStyle {
        if isHovered { return AnyShapeStyle(.white) }
        return action.isDestructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary)
    }

    private func highlight(isHovered: Bool) -> Color {
        guard isHovered else { return .clear }
        return action.isDestructive ? .red : .accentColor
    }
}

/// The captioned row of content actions below the header.
///
/// Separate menu item from the header, and enabled where the header used to be disabled: a menu item's
/// custom view is responsible for its own event handling, and a disabled item does not track at all,
/// so its view would never see a click.
struct CardMenuGlyphRow: View {

    let actions: [CardMenuItem]
    @ObservedObject var hover: CardMenuHoverModel
    let onAction: (CardMenuItem) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                CardMenuGlyphButton(
                    action: action,
                    showsCaption: true,
                    fillsWidth: true,
                    hover: hover,
                    onAction: onAction
                )
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(width: CardMenuHeaderView.width)
    }
}
