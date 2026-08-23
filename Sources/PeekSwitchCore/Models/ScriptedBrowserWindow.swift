import CoreGraphics
import Foundation

/// A browser window as its own scripting interface describes it.
///
/// Exists for one thing the window server cannot answer: whether a window is a private one.
/// Neither Accessibility nor `CGWindowList` exposes anything about private browsing — an
/// incognito Chrome window is an ordinary window with an ordinary title — so the only source is
/// the browser itself, which reports `mode` per window over Apple Events.
struct ScriptedBrowserWindow: Equatable, Sendable {

    let browser: BrowserTab.Browser
    /// The browser's own window id, not a `CGWindowID`.
    let identifier: Int
    let isIncognito: Bool
    /// The window's title, which is also what Accessibility reports for it. The primary key
    /// for matching this back to a `WindowEntry`.
    let title: String
    /// Screen rectangle, in the same top-left-origin space `CGWindowList` uses.
    let frame: CGRect
}

/// Works out which on-screen windows are private browsing windows.
///
/// ## Why this is a matching problem at all
///
/// There is no shared identifier. A browser's scripting interface numbers its windows in its own
/// namespace, and nothing maps that to a `CGWindowID`; the window server, for its part, knows
/// nothing about browsing modes. So the two descriptions of the same window have to be paired up
/// on what they both report: the title, and the rectangle.
///
/// Neither is reliable alone. Two windows of one browser can share a title — two blank tabs are
/// both "New Tab" — and on a laptop where everything is maximised, windows routinely share a
/// rectangle to the pixel. Matching therefore runs in passes, strongest evidence first, so the
/// unambiguous pairs are settled before the ambiguous ones are guessed at.
enum IncognitoMatcher {

    /// How close two rectangles must be to count as the same window. Rounding between the two
    /// APIs is the only difference worth absorbing.
    static let frameTolerance: CGFloat = 2

    /// The `CGWindowID`s of the entries that are private browsing windows.
    ///
    /// Entries that cannot be paired with a scripted window are simply left out — a window whose
    /// mode is unknown is treated as normal, never as private. Getting that the wrong way round
    /// would label ordinary windows as incognito, which is a worse error than missing a badge.
    static func incognitoWindowIDs(
        entries: [WindowEntry],
        scripted: [ScriptedBrowserWindow]
    ) -> Set<CGWindowID> {
        guard !scripted.isEmpty else { return [] }

        // Only real windows of the browsers that answered. Tabs have no window of their own, and
        // an entry from another application cannot be one of these.
        let answered = Set(scripted.map(\.browser.bundleIdentifier))
        var candidates = entries.filter { entry in
            !entry.isTab && entry.bundleIdentifier.map(answered.contains) == true
        }
        guard !candidates.isEmpty else { return [] }

        var remaining = scripted
        var incognito: Set<CGWindowID> = []

        // Strongest evidence first. Each pass consumes the entries and scripted windows it
        // settles, so a title shared by two windows is resolved by whichever of them also
        // matches on geometry before the other is considered.
        for requirement in MatchRequirement.allCases {
            var stillUnmatched: [WindowEntry] = []

            for entry in candidates {
                guard
                    let index = remaining.firstIndex(where: {
                        requirement.matches(entry: entry, scripted: $0)
                    })
                else {
                    stillUnmatched.append(entry)
                    continue
                }

                if remaining[index].isIncognito {
                    incognito.insert(entry.windowID)
                }
                remaining.remove(at: index)
            }

            candidates = stillUnmatched
            if candidates.isEmpty || remaining.isEmpty { break }
        }

        return incognito
    }

    /// The passes, in the order they run.
    private enum MatchRequirement: CaseIterable {
        /// Same browser, same title, same rectangle. Unambiguous in practice.
        case titleAndFrame
        /// Same browser and title. Distinct titles are the common case, and a title is the more
        /// meaningful of the two signals — it is what the user is reading.
        case title
        /// Same browser and rectangle, for a window whose title the two APIs disagree about
        /// (a page that retitled itself between the two reads).
        case frame

        func matches(entry: WindowEntry, scripted: ScriptedBrowserWindow) -> Bool {
            guard entry.bundleIdentifier == scripted.browser.bundleIdentifier else { return false }
            switch self {
            case .titleAndFrame:
                return sameTitle(entry, scripted) && sameFrame(entry, scripted)
            case .title:
                return sameTitle(entry, scripted)
            case .frame:
                return sameFrame(entry, scripted)
            }
        }

        private func sameTitle(_ entry: WindowEntry, _ scripted: ScriptedBrowserWindow) -> Bool {
            let left = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let right = scripted.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty title matches any other empty one, which is no evidence at all, so it is
            // not allowed to settle a pair on its own.
            return !left.isEmpty && left == right
        }

        private func sameFrame(_ entry: WindowEntry, _ scripted: ScriptedBrowserWindow) -> Bool {
            let tolerance = IncognitoMatcher.frameTolerance
            return abs(entry.frame.minX - scripted.frame.minX) <= tolerance
                && abs(entry.frame.minY - scripted.frame.minY) <= tolerance
                && abs(entry.frame.width - scripted.frame.width) <= tolerance
                && abs(entry.frame.height - scripted.frame.height) <= tolerance
        }
    }
}
