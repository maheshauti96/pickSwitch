import Foundation

/// What the spiral's hollow middle says about the window under the pointer.
///
/// ## Why this is a model rather than a few lines in the view
///
/// The hub is about 192 points across, and a circle's usable area is its inscribed square — so
/// roughly 136 points to work with, shrinking further on a small screen. Every fact added costs
/// characters of the window title, which is the one thing a wedge cannot show and the reason the hub
/// exists at all. That makes *what to leave out* the substance of this, and the omission rules are
/// worth stating and testing somewhere they can be read: a rule that quietly stops applying leaves a
/// hub that still renders, still passes every layout assertion, and says less than it did.
///
/// ## What earns a line
///
/// Only facts that change the decision:
///
/// - The source. For a browser window that is the site, not the browser: a Chrome window whose title
///   never mentions GitHub is identified by `github.com` and not at all by "Google Chrome", which is
///   also already on the wedge, in its icon and usually in the title.
/// - Which of its application's windows this is. The ring's order cannot say this, and it is exactly
///   what three near-identical Chrome wedges need.
/// - Whether activating it changes desktop. Nothing else on screen warns that the whole screen is
///   about to be replaced.
/// - When it was last on this desktop, but only for windows that are not — see `lastSeen`.
///
/// Deliberately absent: the monitor, which was removed on purpose once the transition began showing
/// direction; the window's pixel geometry, which decides nothing; and a tab count, which is not
/// fetched until the user starts typing and so would be missing at the moment the hub is read.
struct HubSummary: Equatable {

    /// A label that identifies this result rather than repeating what the wedge already shows.
    ///
    /// Two things qualify. The active site of a browser window or tab, because a Chrome window whose
    /// title never mentions GitHub is identified by `github.com` and by nothing else on screen. And
    /// the action of a web-search result, because that is the one result which leaves the machine and
    /// the title alone — the query — does not say so.
    let identifyingSource: String?

    /// The owning application, used only when there is no identifying source and something else
    /// earns the line.
    let applicationName: String

    /// Which of its application's windows this is, as "2 of 3". `nil` when the application has only
    /// one window, where the phrase would be noise.
    let position: String?

    /// Whether selecting this window means changing desktop.
    let isOnAnotherDesktop: Bool

    /// How long ago this window was last on the desktop the user is looking at, as "20m ago".
    ///
    /// Only ever set for a window that is *not* on this desktop, and that is not a presentation
    /// choice. Every window on the active Space is stamped with a single `seenAt` at enumeration, so
    /// for all of them this reads "just now" — true, and worth nothing, on every card at once. Off
    /// the active Space the stamp is the remembered one from when that desktop was last in front,
    /// which is real information and pairs with `isOnAnotherDesktop`: it says how stale the thing
    /// you are about to switch desktops for actually is.
    let lastSeen: String?

    /// The line above the title, or `nil` when it would say nothing the wedge does not.
    ///
    /// The application's name on its own does not earn this line, and that is the whole reason the
    /// hub never carried it before: the wedge under the pointer is already tinted, outlined, labelled
    /// with that name and showing its icon, and most titles end in it too. It appears here only when
    /// it is qualifying something — "Warp · 2 of 3" answers a question that four copies of "Warp"
    /// cannot. A site host always earns the line, because nothing else on screen spells it out.
    var sourceLine: String? {
        switch (identifyingSource, position) {
        case let (source?, position?): return "\(source) · \(position)"
        case let (source?, nil): return source
        case let (nil, position?): return "\(applicationName) · \(position)"
        case (nil, nil): return nil
        }
    }

    /// The line below the title, or `nil` when there is nothing to say. A window on the desktop you
    /// are already looking at needs no line: that is the unremarkable case.
    ///
    /// - Parameter includingAge: `false` on a scaled-down arrangement. At the smallest size the hub
    ///   is about 124 points across, and the full phrase truncates mid-token to something like
    ///   "Another desktop · 2…", which reads worse than not saying it. The warning is the part worth
    ///   keeping, so the age is what goes — the same trade the title makes when it gives up a line.
    func statusLine(includingAge: Bool = true) -> String? {
        guard isOnAnotherDesktop else { return nil }
        guard includingAge, let lastSeen else { return "Another desktop" }
        return "Another desktop · \(lastSeen)"
    }

    /// Build the summary for one entry.
    ///
    /// - Parameters:
    ///   - siteHost: the active site, already checked against private browsing by the caller.
    ///   - windowIndex: 1-based position among the windows of this entry's application.
    ///   - windowCount: how many windows that application has.
    ///   - now: `Date().timeIntervalSinceReferenceDate`, which is the clock
    ///     `WindowEntry.lastSeenOnActiveSpace` is stamped from. Passed in so the wording can be
    ///     tested without waiting for time to pass.
    static func make(
        entry: WindowEntry,
        siteHost: String?,
        windowIndex: Int?,
        windowCount: Int?,
        now: TimeInterval
    ) -> HubSummary {
        let source: String? = {
            // A web-search result names its action here. Its title is the query, which says what
            // was typed but not that confirming it opens a browser.
            if entry.isWebSearch { return entry.sourceLabel }
            guard let siteHost, !siteHost.isEmpty else { return nil }
            return siteHost
        }()

        let position: String? = {
            guard entry.isWindow,
                  let windowIndex,
                  let windowCount,
                  windowCount > 1,
                  windowIndex >= 1,
                  windowIndex <= windowCount
            else { return nil }
            return "\(windowIndex) of \(windowCount)"
        }()

        // Only a real window belongs to a desktop. A tab is reached through its browser and an
        // installed application has no window yet, so neither can be somewhere else.
        let isOnAnotherDesktop = entry.isWindow && !entry.isOnActiveSpace

        let lastSeen: String? = {
            guard isOnAnotherDesktop, let seen = entry.lastSeenOnActiveSpace else { return nil }
            let age = now - seen
            guard age >= 0 else { return nil }
            return relativeAge(age)
        }()

        return HubSummary(
            identifyingSource: source,
            applicationName: entry.applicationName,
            position: position,
            isOnAnotherDesktop: isOnAnotherDesktop,
            lastSeen: lastSeen
        )
    }

    /// A compact age, in the widest unit that still says something.
    ///
    /// Short by necessity: this shares one line of roughly thirty characters with "Another desktop".
    /// Precision beyond a single unit would cost the phrase it sits next to.
    static func relativeAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }
}
