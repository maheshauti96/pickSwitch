import Foundation

/// What a card's context menu offers, decided as a pure function of the card and what is known
/// about it.
///
/// A model rather than a pile of `if`s where the menu is built, for the reason `ConfirmationTarget`
/// and `KeyResponse` were extracted: the menu is assembled inside a right-click handler that needs a
/// live overlay, a real panel and a running application to reach, so the rules it encodes could only
/// ever be checked by hand. The rules are also the substance here — *what to leave out* is most of
/// the design, because an item that cannot work is worse than an item that is absent.
///
/// ## The omission rules
///
/// - Only windows get a menu. A tab result has no window of its own to act on and an installed
///   application has no window yet, so both would produce a menu of things that cannot be done.
/// - Anything routed through Accessibility is withheld without a live element. Windows discovered on
///   another desktop through the window server alone carry none — they are the same windows that
///   already show no close button — so closing, minimising and tiling them is not merely unreliable,
///   it is impossible, and offering it would be a lie.
/// - Tiling is withheld for a minimized window. Its frame is not where it is or how big it looks, so
///   moving it to half a screen you cannot see it on changes nothing you can observe.
/// - Muting appears only for a window actually making noise. It is not a toggle and not a preference;
///   it acts on what is playing right now, and there is nothing to act on otherwise.
enum CardMenuItem: Equatable {

    /// Scope the overlay's own search to this browser window's tabs. `count` is `nil` until the tab
    /// list has been fetched, which does not happen until the user types — so the item is offered
    /// before the number is known, and choosing it is what fetches them.
    case searchWindowTabs(count: Int?)

    /// Mute whatever is currently audible in this window.
    case muteAudible

    case closeWindow
    case minimizeWindow
    /// Send the window to half its screen.
    case tileWindow(WindowTile)

    case pinApplication(name: String)
    case unpinApplication(name: String)
}

enum CardMenu {

    /// Everything the menu needs to know that is not on the entry itself.
    struct Context: Equatable {
        /// Whether this window belongs to a browser whose tabs can be listed.
        var isBrowserWindow: Bool = false
        /// Tabs known to belong to this window, or `nil` if they have not been fetched.
        var knownTabCount: Int?
        /// Whether this window is making noise right now.
        var isAudible: Bool = false
        /// Whether a live Accessibility element exists for this window.
        var hasAccessibilityElement: Bool = false
        /// Whether the owning application is pinned to the front of the list.
        var isPinned: Bool = false
        /// Whether the window is currently in the Dock.
        var isMinimized: Bool = false
    }

    /// The menu in the two rows it is drawn as.
    ///
    /// Two ordered lists rather than one flat list with separators in it. The separators used to mark
    /// these same groups in a vertical list of words, and now that the groups are laid out as
    /// separate rows the boundary is carried by the layout — so a model that still emitted separators
    /// would be describing a shape the menu no longer has.
    struct Rows: Equatable {

        /// Above the preview, top-left: everything that acts on the window *as a window*. Grouped
        /// there because the preview is the window, so the controls sit on the thing they affect —
        /// the same reason a title bar puts them on the window rather than in a menu.
        var windowControls: [CardMenuItem] = []

        /// Below the facts: what is about the window's *contents* or about its application, neither
        /// of which the preview shows.
        var actions: [CardMenuItem] = []

        var isEmpty: Bool { windowControls.isEmpty && actions.isEmpty }
    }

    static func rows(for entry: WindowEntry, context: Context) -> Rows {
        guard entry.isWindow else { return Rows() }

        var rows = Rows()

        if context.hasAccessibilityElement {
            rows.windowControls.append(.minimizeWindow)
            rows.windowControls.append(.closeWindow)
            if !context.isMinimized {
                rows.windowControls.append(contentsOf: WindowTile.allCases.map(CardMenuItem.tileWindow))
            }
        }

        // The browser action leads the second row, because it is the one thing here about what the
        // window *contains* rather than about the window. For a browser that is what the user is
        // actually looking for — a tab — and Vortexflow's own search is already the fastest way there.
        if context.isBrowserWindow {
            rows.actions.append(.searchWindowTabs(count: context.knownTabCount))
        }
        if context.isAudible {
            rows.actions.append(.muteAudible)
        }
        let name = entry.applicationName
        rows.actions.append(context.isPinned ? .unpinApplication(name: name) : .pinApplication(name: name))

        return rows
    }
}

extension CardMenuItem {

    /// The glyph and the word that names it.
    struct Icon: Equatable {
        let symbolName: String
        /// Kept with the glyph rather than left to a tooltip. A row of bare glyphs makes the user
        /// guess, and menu tooltips only appear after a delay the user has no reason to wait through
        /// — so this is the difference between recognising an action and risking one.
        let label: String
    }

    var icon: Icon {
        switch self {
        case .searchWindowTabs(let count):
            // The count rides in the caption when it is known. It is the one thing a single card
            // cannot tell you, and it is what decides whether searching inside is worth doing.
            return Icon(
                symbolName: "magnifyingglass",
                label: count.map { $0 == 1 ? "1 tab" : "\($0) tabs" } ?? "Tabs"
            )
        case .muteAudible:
            return Icon(symbolName: "speaker.slash", label: "Mute")
        case .minimizeWindow:
            // The traffic-light glyph rather than a more descriptive arrow: beside the close cross it
            // reads as the pair the user already knows from every title bar.
            return Icon(symbolName: "minus", label: "Minimize")
        case .closeWindow:
            return Icon(symbolName: "xmark", label: "Close")
        case .tileWindow(let tile):
            return Icon(symbolName: tile.symbolName, label: tile.title)
        case .pinApplication:
            return Icon(symbolName: "pin", label: "Pin")
        case .unpinApplication:
            return Icon(symbolName: "pin.slash", label: "Unpin")
        }
    }

    /// The full sentence, for VoiceOver and for the hovered-action caption. Written out here rather
    /// than at the call site so the wording is testable alongside the rules that decide whether the
    /// item appears.
    var title: String {
        switch self {
        case .searchWindowTabs(let count):
            guard let count else { return "Search this window's tabs" }
            return "Search this window's \(count) tabs"
        case .muteAudible:
            return "Mute what's playing"
        case .closeWindow:
            return "Close window"
        case .minimizeWindow:
            return "Minimize window"
        case .tileWindow(let tile):
            return tile.title
        case .pinApplication(let name):
            return "Pin \(name)"
        case .unpinApplication(let name):
            return "Unpin \(name)"
        }
    }
}
