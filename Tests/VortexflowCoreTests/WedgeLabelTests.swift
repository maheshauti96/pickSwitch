import CoreGraphics
import Testing
@testable import VortexflowCore

/// What a wedge calls a window, which is a question the ring got wrong in a way that read as a bug.
///
/// Reported as "why do I see 3 zoom windows even though only one Zoom app is running". Zoom had three
/// windows, and the ring drew each of them as "zoom.us" with the same icon — so nothing on screen
/// distinguished three windows from one window drawn three times. Naming the application is right
/// when it identifies the result and wrong the moment two wedges share it.
struct WedgeLabelTests {

    private func window(app: String, title: String, id: CGWindowID) -> WindowEntry {
        Fixture.entry(id: id, app: app, title: title)
    }

    /// The single-window case, which is what the wedge was designed around: at ring distance the
    /// application is the recognisable part, and its window's title usually repeats it.
    @Test func aLoneWindowIsNamedByItsApplication() {
        let entry = window(app: "Warp", title: "..ments/Quattr-2/be+fe-2", id: 1)
        #expect(WindowWedgeView.primaryText(for: entry, badgeCount: nil) == "Warp")
    }

    /// The reported case. Real titles, from the enumeration that diagnosed it.
    @Test func siblingWindowsAreNamedByTheirTitles() {
        let healthcheck = window(app: "zoom.us", title: "Zoom Client Healthcheck", id: 1185)
        let workplace = window(app: "zoom.us", title: "Zoom Workplace", id: 1191)
        let meeting = window(app: "zoom.us", title: "Zoom", id: 1865)

        let labels = [healthcheck, workplace, meeting].map {
            WindowWedgeView.primaryText(for: $0, badgeCount: 3)
        }

        #expect(labels == ["Zoom Client Healthcheck", "Zoom Workplace", "Zoom"])
        // The property that was missing: three wedges, three different things to read.
        #expect(Set(labels).count == 3)
    }

    /// A window with no title of its own still has to say something, and `displayTitle` already
    /// falls back to the application name. Without that this change would trade three identical
    /// labels for three blank ones.
    @Test func anUntitledSiblingFallsBackToItsApplication() {
        let entry = Fixture.entry(id: 7, app: "zoom.us", title: "   ")
        #expect(WindowWedgeView.primaryText(for: entry, badgeCount: 2) == "zoom.us")
    }

    /// Tabs are left alone. `badgeCount` is nil for them by construction — it requires `isWindow` —
    /// and their `sourceLabel` is the site host, which already tells fifteen Chrome tabs apart where
    /// the browser's name could not.
    @Test func tabsKeepTheirSiteHost() {
        let tab = WindowEntry.tabEntry(
            BrowserTab(
                browser: .chrome,
                windowIdentifier: 1,
                tabIndex: 2,
                title: "Pull Request #6801 · Quattr/qwa",
                url: "https://github.com/Quattr/qwa/pull/6801"
            ),
            application: nil
        )
        #expect(WindowWedgeView.primaryText(for: tab, badgeCount: nil) == "github.com")
    }

    /// Accessibility lists tabs before scripting fills in the URL. The wedge must not
    /// fall back to "Google Chrome" for every seat while that address is missing.
    @Test func aTabWithoutAURLIsNamedByItsTitle() {
        let tab = WindowEntry.tabEntry(
            BrowserTab(
                browser: .chrome,
                windowIdentifier: 1,
                tabIndex: 1,
                title: "taxonomy engine - Grok",
                url: ""
            ),
            application: nil
        )
        #expect(WindowWedgeView.primaryText(for: tab, badgeCount: nil) == "taxonomy engine - Grok")
    }
}
