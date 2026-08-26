import AppKit
import CoreGraphics
import Testing
@testable import PeekSwitchCore

/// What confirming the overlay does, and specifically that the selection decides it.
///
/// The bug this covers: a Return-only web fallback sat in front of the selected entry, so with a
/// query that had matched nothing locally, Return opened the *first* offer whatever the user had
/// selected. Picking "Prompt on ChatGPT" opened a Google search. It survived because the decision
/// was a chain of conditions inside the controller, and there is no controller test harness.
@Suite("Confirmation target")
struct ConfirmationTargetTests {

    private static let query = "how do I revert a merge commit"

    /// The offers a real query produces, in the order the overlay shows them.
    private static var offers: [WindowEntry] {
        WebSearch.destinations(for: query).map { destination in
            .webSearchEntry(WebSearchTarget(query: query, destination: destination))
        }
    }

    private static func window(_ name: String) -> WindowEntry {
        WindowEntry(
            windowID: 42,
            processID: 1,
            applicationName: name,
            applicationIcon: nil,
            title: "a window",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false,
            zOrder: 0,
            axElement: nil
        )
    }

    /// The regression, over every offer a query produces and both ways of confirming.
    ///
    /// Swept rather than spot-checked: the failure was per-destination — the first offer worked by
    /// coincidence and every later one silently opened the first instead — so checking one would
    /// have reproduced exactly the blind spot that let it ship.
    @Test("every offer opens its own destination, however it was confirmed")
    func selectedOfferOpensItself() {
        let offers = Self.offers
        #expect(offers.count >= 4, "expected a search plus one prompt per assistant")

        for offer in offers {
            let expected = try? #require(offer.webSearch?.destination)

            for isReturn in [true, false] {
                let target = ConfirmationTarget.resolve(
                    isReturn: isReturn,
                    selectedEntry: offer,
                    // The state the bug needed: nothing matched locally, so the old fallback fired.
                    canOfferWebSearch: true,
                    query: Self.query
                )
                #expect(
                    target == .open(expected!),
                    """
                    \(offer.sourceLabel) confirmed with \(isReturn ? "Return" : "a click") \
                    resolved to \(target) instead of its own destination
                    """
                )
            }
        }
    }

    /// The specific symptom, named: an assistant must not open a search engine.
    @Test("a selected assistant never opens the search engine")
    func assistantNeverOpensSearch() {
        for provider in WebSearch.PromptProvider.allCases {
            let offer = Self.offers.first {
                if case .prompt(let selected, _) = $0.webSearch?.destination { return selected == provider }
                return false
            }
            #expect(offer != nil, "\(provider.displayName) was not offered")
            guard let offer else { continue }

            let target = ConfirmationTarget.resolve(
                isReturn: true,
                selectedEntry: offer,
                canOfferWebSearch: true,
                query: Self.query
            )
            guard case .open(let destination) = target else {
                Issue.record("\(provider.displayName) did not open anything: \(target)")
                continue
            }
            guard case .prompt(let opened, let url) = destination else {
                Issue.record("\(provider.displayName) opened \(destination) instead of a prompt")
                continue
            }
            #expect(opened == provider)
            #expect(url.absoluteString.hasPrefix(provider.template))
            #expect(!url.absoluteString.hasPrefix(WebSearch.searchTemplate))
            // And it really is that provider's own host, not merely the right label.
            #expect(url.host == URL(string: provider.siteURL)?.host)
        }
    }

    /// A local match still wins, which is the whole point of the switcher.
    @Test("a selected window is activated rather than opened")
    func selectedWindowIsActivated() {
        for isReturn in [true, false] {
            // Even with the fallback's own precondition true, which is the precedence that broke.
            #expect(
                ConfirmationTarget.resolve(
                    isReturn: isReturn,
                    selectedEntry: Self.window("Slack"),
                    canOfferWebSearch: true,
                    query: Self.query
                ) == .activate(Self.window("Slack"))
            )
        }
    }

    /// The fallback the old chain was written for, kept: with nothing selectable at all, Return
    /// still takes the query to the web.
    @Test("Return still offers the web when there is nothing to select")
    func fallbackSurvivesForTheEmptyState() {
        let target = ConfirmationTarget.resolve(
            isReturn: true,
            selectedEntry: nil,
            canOfferWebSearch: true,
            query: Self.query
        )
        #expect(target == .open(WebSearch.destination(for: Self.query)!))
    }

    /// Mouse and trigger confirmation have never opened a browser with nothing selected, and still
    /// do not — that would turn a stray click into a page load.
    @Test("a click with nothing selected only dismisses")
    func clickWithNothingSelectedDismisses() {
        #expect(
            ConfirmationTarget.resolve(
                isReturn: false,
                selectedEntry: nil,
                canOfferWebSearch: true,
                query: Self.query
            ) == .dismiss
        )
    }

    /// And with no query to fall back on there is nothing to open either.
    @Test("nothing selected and nothing to offer dismisses")
    func nothingToDoDismisses() {
        for query in ["", "   "] {
            #expect(
                ConfirmationTarget.resolve(
                    isReturn: true,
                    selectedEntry: nil,
                    canOfferWebSearch: false,
                    query: query
                ) == .dismiss
            )
        }
    }
}
