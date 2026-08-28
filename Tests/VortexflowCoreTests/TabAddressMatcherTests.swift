import Testing
@testable import VortexflowCore

/// Copying scripting URLs onto Accessibility-listed tabs.
///
/// Chrome's tab strip has titles and no addresses. Wedges need the host, favicons
/// need the URL, and a window on another Space is often only listable through that
/// strip. Matching must keep the native window id so the scope does not go empty.
struct TabAddressMatcherTests {

    private func listed(_ title: String, index: Int, window: Int = 5_575) -> BrowserTab {
        BrowserTab(
            browser: .chrome,
            windowIdentifier: window,
            tabIndex: index,
            title: title,
            url: "",
            usesNativeWindowIdentifier: true
        )
    }

    private func scripted(_ title: String, index: Int, url: String, window: Int = 99) -> BrowserTab {
        BrowserTab(
            browser: .chrome,
            windowIdentifier: window,
            tabIndex: index,
            title: title,
            url: url,
            allowsFaviconRequest: true
        )
    }

    @Test func aUniqueTitleReceivesItsURL() {
        let result = TabAddressMatcher.enrich(
            [listed("Grok", index: 1), listed("GitHub", index: 2)],
            with: [
                scripted("Grok", index: 1, url: "https://grok.com/"),
                scripted("GitHub", index: 2, url: "https://github.com/"),
            ]
        )
        #expect(result.map(\.url) == ["https://grok.com/", "https://github.com/"])
        #expect(result.allSatisfy { $0.allowsFaviconRequest })
        #expect(result.allSatisfy { $0.usesNativeWindowIdentifier })
        #expect(result.map(\.windowIdentifier) == [5_575, 5_575])
        #expect(result.map(\.scriptedWindowIdentifier) == [99, 99])
        #expect(result.map(\.scriptedTabIndex) == [1, 2])
        #expect(result[0].scriptedActivation?.windowIdentifier == 99)
    }

    @Test func aTruncatedAccessibilityTitleStillMatches() {
        let result = TabAddressMatcher.enrich(
            [listed("feat(snowflake): key-pair auth, no password fallback by pratikb-quattr · Pull Re", index: 1)],
            with: [
                scripted(
                    "feat(snowflake): key-pair auth, no password fallback by pratikb-quattr · Pull Request #184 · Quattr/QBatch",
                    index: 1,
                    url: "https://github.com/Quattr/QBatch/pull/184"
                ),
            ]
        )
        #expect(result[0].host == "github.com")
    }

    @Test func duplicateTitlesInOneWindowMatchByIndex() {
        let result = TabAddressMatcher.enrich(
            [listed("Grok", index: 1), listed("Grok", index: 2)],
            with: [
                scripted("Grok", index: 1, url: "https://grok.com/c/1"),
                scripted("Grok", index: 2, url: "https://grok.com/c/2"),
            ]
        )
        #expect(result.map(\.url) == ["https://grok.com/c/1", "https://grok.com/c/2"])
    }

    @Test func aWindowTitleKeepsTheOtherWindowsTabsOut() {
        var window = Fixture.entry(id: 1, app: "Google Chrome", title: "taxonomy engine - Grok")
        window.bundleIdentifier = "com.google.Chrome"
        let result = TabAddressMatcher.enrich(
            [listed("taxonomy engine - Grok", index: 1)],
            with: [
                scripted("YouTube Music", index: 1, url: "https://music.youtube.com/", window: 10),
                scripted("taxonomy engine - Grok", index: 1, url: "https://grok.com/c/1", window: 20),
            ],
            window: window
        )
        #expect(result[0].url == "https://grok.com/c/1")
    }

    @Test func anExistingAddressIsLeftAlone() {
        let already = BrowserTab(
            browser: .chrome,
            windowIdentifier: 5_575,
            tabIndex: 1,
            title: "Grok",
            url: "https://grok.com/already",
            usesNativeWindowIdentifier: true
        )
        let result = TabAddressMatcher.enrich(
            [already],
            with: [scripted("Grok", index: 1, url: "https://grok.com/other")]
        )
        #expect(result[0].url == "https://grok.com/already")
    }
}
