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
/// - Tiling and Move to Display are withheld in Full Screen. The window occupies a Space, not a
///   resizable frame on a desktop — the same reason macOS greys those items out. Exit Full Screen
///   is offered instead.
/// - Muting appears only for a window actually making noise. It is not a toggle and not a preference;
///   it acts on what is playing right now, and there is nothing to act on otherwise.
enum CardMenuItem: Equatable {

    /// Scope the overlay's own search to this browser window's tabs. `count` is `nil` until the tab
    /// list has been fetched, which does not happen until the user types — so the item is offered
    /// before the number is known, and choosing it is what fetches them.
    case searchWindowTabs(count: Int?)

    /// Mute whatever is currently audible in this window.
    case muteAudible
    /// Toggle play / pause for whatever this window is playing. Offered when the window
    /// is making noise. The hardware play key is a toggle, so this is too.
    case pausePlayback
    case nextTrack
    case previousTrack

    case closeWindow
    case minimizeWindow
    /// Send the window to a region of its screen.
    case tileWindow(WindowTile)
    /// Enter macOS Full Screen, which is a Space rather than a tiled frame.
    case enterFullScreen
    /// Leave Full Screen, returning the window to the desktop it came from.
    case exitFullScreen
    /// Move the window onto another display, centred in that display's usable area.
    case moveToDisplay(DisplayInfo)

}

enum CardMenu {

    /// Everything the menu needs to know that is not on the entry itself.
    struct Context: Equatable {
        /// Whether this window's tabs can be listed through its application's scripting
        /// interface. Pairing to a scripting id is *not* required to offer the item —
        /// choosing it is what fetches the tabs, and the pairing can finish after that.
        var hasSearchableTabs: Bool = false
        /// Tabs known to belong to this window, or `nil` if they have not been fetched.
        var knownTabCount: Int?
        /// Whether this window is making noise right now. Mute is offered on this, because
        /// mute acts on whatever is coming out of the speakers.
        var isAudible: Bool = false
        /// Whether this window is currently playing, as opposed to only using the microphone.
        /// Previous / pause / next are a media session, and a call on the mic is not one.
        var isPlayingAudio: Bool = false
        /// Whether a live Accessibility element exists for this window.
        var hasAccessibilityElement: Bool = false
        /// Whether the window is currently in the Dock.
        var isMinimized: Bool = false
        /// Whether the window already occupies a Full Screen Space. The item would only
        /// set a flag that is already true.
        var isFullScreen: Bool = false
        /// Displays the window is *not* on, for "Move to …". Empty on a single-display desk.
        var otherDisplays: [DisplayInfo] = []
    }

    /// The menu in the groups it is drawn as.
    ///
    /// Separate lists rather than one flat list with separators in it. The separators used to mark
    /// these same groups in a vertical list of words, and now that the groups are laid out as
    /// distinct rows the boundary is carried by the layout — so a model that still emitted separators
    /// would be describing a shape the menu no longer has.
    struct Rows: Equatable {

        /// What a title bar carries: minimize and close, in that order.
        ///
        /// Drawn in the corner above the preview, because the preview *is* the window and these are
        /// the controls that belong on a window rather than in a list. Keeping them as their own group
        /// is what lets the view place them without pattern-matching cases back out of a mixed list.
        var windowControls: [CardMenuItem] = []

        /// The four halves, matching macOS Move & Resize.
        var moveResize: [CardMenuItem] = []
        /// Fill and the remaining arrangements, matching macOS Fill & Arrange.
        var fillArrange: [CardMenuItem] = []
        /// Full Screen and Move to another display.
        var placement: [CardMenuItem] = []

        /// What the window *contains* — tab search — drawn as a labelled row under the
        /// preview, after the title and facts the picture is of.
        var contents: [CardMenuItem] = []

        /// Remaining content actions that still need a captioned glyph, currently mute.
        var actions: [CardMenuItem] = []

        /// Previous / pause / next, drawn under the facts the way Chrome's own media
        /// controls sit under the playing tab. Offered only while this window is playing.
        var media: [CardMenuItem] = []

        var isEmpty: Bool {
            windowControls.isEmpty
                && moveResize.isEmpty
                && fillArrange.isEmpty
                && placement.isEmpty
                && contents.isEmpty
                && actions.isEmpty
                && media.isEmpty
        }
    }

    static func rows(for entry: WindowEntry, context: Context) -> Rows {
        guard entry.isWindow else { return Rows() }

        var rows = Rows()

        if context.hasAccessibilityElement {
            // Minimize first, close last: close ends up furthest into the corner, which is where the
            // pointer travels least accurately, and putting the reversible action on the inside is
            // what keeps a slightly long throw from closing the window.
            rows.windowControls.append(.minimizeWindow)
            rows.windowControls.append(.closeWindow)
            if !context.isMinimized, !context.isFullScreen {
                rows.moveResize = WindowTile.moveResize.map(CardMenuItem.tileWindow)
                rows.fillArrange = WindowTile.fillArrange.map(CardMenuItem.tileWindow)
                rows.placement.append(.enterFullScreen)
                rows.placement.append(contentsOf: context.otherDisplays.map(CardMenuItem.moveToDisplay))
            } else if !context.isMinimized, context.isFullScreen {
                rows.placement.append(.exitFullScreen)
            }
        }

        // Under the preview, because it is about what the picture contains. For a tabbed
        // window that is a tab, and Vortexflow's own search is already the fastest way there.
        if context.hasSearchableTabs {
            rows.contents.append(.searchWindowTabs(count: context.knownTabCount))
        }
        // Pause / next only while something is actually playing. A microphone session is
        // audible in the mute sense but has no track to skip.
        if context.isPlayingAudio {
            rows.media = [.previousTrack, .pausePlayback, .nextTrack]
        }
        if context.isAudible {
            rows.actions.append(.muteAudible)
        }

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
        case .pausePlayback:
            return Icon(symbolName: "pause.fill", label: "Pause")
        case .nextTrack:
            return Icon(symbolName: "forward.end.fill", label: "Next")
        case .previousTrack:
            return Icon(symbolName: "backward.end.fill", label: "Previous")
        case .minimizeWindow:
            // The traffic-light glyph rather than a more descriptive arrow: beside the close cross it
            // reads as the pair the user already knows from every title bar.
            return Icon(symbolName: "minus", label: "Minimize")
        case .closeWindow:
            return Icon(symbolName: "xmark", label: "Close")
        case .tileWindow(let tile):
            return Icon(symbolName: tile.symbolName, label: tile.title)
        case .enterFullScreen:
            return Icon(symbolName: "arrow.up.left.and.arrow.down.right", label: "Full Screen")
        case .exitFullScreen:
            return Icon(symbolName: "arrow.down.right.and.arrow.up.left", label: "Exit Full Screen")
        case .moveToDisplay:
            return Icon(symbolName: "display", label: "Move")
        }
    }

    /// Whether this action destroys something, and should be coloured to say so before it is clicked.
    ///
    /// Only closing. Minimizing is reversible from the Dock and tiling is reversible by dragging, but
    /// a closed window with unsaved work in it is not reversible at all — and in a row of same-coloured
    /// glyphs the cross sits immediately beside the minus, which is the pair most easily confused.
    var isDestructive: Bool {
        switch self {
        case .closeWindow: return true
        case .searchWindowTabs, .muteAudible, .pausePlayback, .nextTrack, .previousTrack,
             .minimizeWindow, .tileWindow, .enterFullScreen, .exitFullScreen, .moveToDisplay:
            return false
        }
    }

    /// The full sentence, for VoiceOver and for the hovered-action caption. Written out here rather
    /// than at the call site so the wording is testable alongside the rules that decide whether the
    /// item appears.
    var title: String {
        switch self {
        case .searchWindowTabs(let count):
            guard let count else { return "Search through Tabs" }
            return count == 1 ? "Search through 1 Tab" : "Search through \(count) Tabs"
        case .muteAudible:
            return "Mute what's playing"
        case .pausePlayback:
            return "Play/Pause"
        case .nextTrack:
            return "Next track"
        case .previousTrack:
            return "Previous track"
        case .closeWindow:
            return "Close window"
        case .minimizeWindow:
            return "Minimize window"
        case .tileWindow(let tile):
            return tile.title
        case .enterFullScreen:
            return "Full Screen"
        case .exitFullScreen:
            return "Exit Full Screen"
        case .moveToDisplay(let display):
            return display.name.isEmpty ? "Move to \(display.label)" : "Move to \(display.name)"
        }
    }

    /// Media transport is used as a player, so the menu stays open through pause / next.
    /// Everything else is a one-shot and closes.
    var keepsMenuOpen: Bool {
        switch self {
        case .pausePlayback, .nextTrack, .previousTrack: return true
        case .searchWindowTabs, .muteAudible, .closeWindow, .minimizeWindow,
             .tileWindow, .enterFullScreen, .exitFullScreen, .moveToDisplay:
            return false
        }
    }
}
