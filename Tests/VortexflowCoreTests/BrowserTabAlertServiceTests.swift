import Testing
@testable import VortexflowCore

/// Listing tabs from Chrome's accessibility strip.
///
/// Chrome currently exposes empty `AXTabGroup`s above the real strip, and leaves
/// `AXTitle` blank on each tab button — the page name is only in the description.
/// Both of those used to make Search through Tabs report "No tabs in this window"
/// for windows that were full of tabs.
struct BrowserTabAlertListingTests {

    @Test func theStripWithTabsIsPreferredOverAnEmptyNeighbour() {
        #expect(BrowserTabAlertService.preferredTabStripIndex(tabCounts: [0, 19, 0]) == 1)
        #expect(BrowserTabAlertService.preferredTabStripIndex(tabCounts: [19, 19, 0]) == 0)
        #expect(BrowserTabAlertService.preferredTabStripIndex(tabCounts: []) == nil)
        #expect(BrowserTabAlertService.preferredTabStripIndex(tabCounts: [0, 0]) == 0)
    }

    @Test func anEmptyTitleUsesTheAccessibilityDescription() {
        #expect(
            BrowserTabAlertService.resolvedTabTitle(
                axTitle: "",
                accessibilityDescription: "Code search results"
            ) == "Code search results"
        )
        #expect(
            BrowserTabAlertService.resolvedTabTitle(
                axTitle: "   ",
                accessibilityDescription: "ChatGPT - Memory usage - 368 MB"
            ) == "ChatGPT"
        )
        #expect(
            BrowserTabAlertService.resolvedTabTitle(
                axTitle: nil,
                accessibilityDescription: "YouTube Music \u{2013} Audio playing"
            ) == "YouTube Music"
        )
    }

    @Test func aPopulatedTitleWinsOverTheDescription() {
        #expect(
            BrowserTabAlertService.resolvedTabTitle(
                axTitle: "Inbox",
                accessibilityDescription: "Inbox (27,383) - Gmail"
            ) == "Inbox"
        )
    }
}
