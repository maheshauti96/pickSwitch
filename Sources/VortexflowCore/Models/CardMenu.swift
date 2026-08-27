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
///   already show no close button — so closing and minimising them is not merely unreliable, it is
///   impossible, and offering it would be a lie.
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

    case pinApplication(name: String)
    case unpinApplication(name: String)
    case quitApplication(name: String)

    case separator
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
    }

    /// The menu for one card, in order. Empty means no menu should open at all.
    static func items(for entry: WindowEntry, context: Context) -> [CardMenuItem] {
        guard entry.isWindow else { return [] }

        var groups: [[CardMenuItem]] = []

        // The browser group leads, because it is the one thing here that is about what the window
        // *contains* rather than about the window. For a browser that is what the user is actually
        // looking for — a tab — and Vortexflow's own search is already the fastest way to that.
        var browser: [CardMenuItem] = []
        if context.isBrowserWindow {
            browser.append(.searchWindowTabs(count: context.knownTabCount))
        }
        if context.isAudible {
            browser.append(.muteAudible)
        }
        groups.append(browser)

        var window: [CardMenuItem] = []
        if context.hasAccessibilityElement {
            window.append(.minimizeWindow)
            window.append(.closeWindow)
        }
        groups.append(window)

        let name = entry.applicationName
        groups.append([
            context.isPinned ? .unpinApplication(name: name) : .pinApplication(name: name),
            .quitApplication(name: name),
        ])

        // Separators between non-empty groups only, so a withheld group leaves no gap behind it.
        return groups.filter { !$0.isEmpty }
            .enumerated()
            .flatMap { index, group in index == 0 ? group : [.separator] + group }
    }
}

extension CardMenu {

    /// Split the menu into the actions that become a row of glyphs and the ones that stay written
    /// out as lines.
    ///
    /// The separators are dropped rather than translated. They marked groups in a vertical list —
    /// "about the contents", "about the window", "about the application" — and once those actions sit
    /// side by side in one row the grouping is carried by the row itself. A divider between glyphs
    /// would be furniture standing in for a distinction the layout already makes.
    static func partition(_ items: [CardMenuItem]) -> (icons: [CardMenuItem], written: [CardMenuItem]) {
        var icons: [CardMenuItem] = []
        var written: [CardMenuItem] = []
        for item in items where item != .separator {
            if item.icon == nil {
                written.append(item)
            } else {
                icons.append(item)
            }
        }
        return (icons, written)
    }
}

extension CardMenuItem {

    /// The glyph and the word under it, for an action compact enough to be a button.
    struct Icon: Equatable {
        let symbolName: String
        /// Kept alongside the glyph rather than left to a tooltip. A row of bare glyphs makes the
        /// user guess, and menu tooltips only appear after a delay the user has no reason to wait
        /// through — so the caption is the difference between recognising an action and risking one.
        let label: String
    }

    /// The button form of this action, or `nil` for one that has to stay a written line.
    var icon: Icon? {
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
        case .pinApplication:
            return Icon(symbolName: "pin", label: "Pin")
        case .unpinApplication:
            return Icon(symbolName: "pin.slash", label: "Unpin")
        case .quitApplication:
            // Deliberately not a glyph. Quitting closes every window the application has and can
            // lose unsaved work in all of them, which makes it the one action here that must not sit
            // a mis-click away from Minimize. Naming the application out loud is the confirmation.
            return nil
        case .separator:
            return nil
        }
    }

    /// The menu title. Written out here rather than at the call site so the wording is testable
    /// alongside the rules that decide whether the item appears.
    var title: String {
        switch self {
        case .searchWindowTabs(let count):
            // The count is worth showing when known: "Search 23 tabs" tells the user how much is
            // behind the window, which is the thing a single card cannot say.
            guard let count else { return "Search this window's tabs" }
            return "Search this window's \(count) tabs"
        case .muteAudible:
            return "Mute what's playing"
        case .closeWindow:
            return "Close window"
        case .minimizeWindow:
            return "Minimize window"
        case .pinApplication(let name):
            return "Pin \(name)"
        case .unpinApplication(let name):
            return "Unpin \(name)"
        case .quitApplication(let name):
            return "Quit \(name)"
        case .separator:
            return ""
        }
    }
}
