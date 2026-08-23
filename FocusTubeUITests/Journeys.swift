import XCTest

/// Deterministic product journeys over the DEBUG fixture harness
/// (`-focustube-ui-test <scenario>`). Every scenario serves local scripted
/// data only — no live YouTube/network dependency. Waits are explicit
/// `waitForExistence` expectations, never sleeps.
final class Journeys: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-focustube-ui-test", scenario]
        app.launch()
        return app
    }

    /// Cold simulator launches can take several seconds before freshly pushed
    /// content exists; every existence wait uses this generous bound instead of
    /// asserting against first-frame latency.
    @discardableResult
    private func waitExists(_ element: XCUIElement, _ timeout: TimeInterval = 15) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    // MARK: - Diagnostics

    /// Compact, bounded view of what XCUITest actually sees when an expected
    /// video-page element fails to appear. Emitted only inside failure messages
    /// (assertion autoclosures), so passing tests pay nothing. Remote agents can
    /// read these through check-run annotations without authenticated API access.
    private func treeDiagnostics(_ app: XCUIApplication) -> String {
        var facts = ["sheets=\(app.sheets.count)"]
        let probes: [(String, XCUIElement)] = [
            ("title", app.staticTexts["video-title"]),
            ("channel", app.staticTexts["video-channel"]),
            ("save", app.buttons["save-toggle"]),
            ("dl", app.buttons["download-button"]),
            ("close", app.buttons["Close"]),
            ("failed", app.staticTexts["Playback failed"]),
            ("loading", app.staticTexts["Loading…"]),
            ("row0", app.buttons.matching(identifier: "feed-video-row").element(boundBy: 0)),
            ("alert", app.alerts.element(boundBy: 0))
        ]
        for (name, el) in probes {
            guard el.exists else { facts.append("\(name)=no"); continue }
            facts.append(el.isHittable ? "\(name)=hit" : "\(name)=flat")
        }
        let interesting = app.debugDescription
            .split(separator: "\n")
            .filter { line in
                ["Sheet", "Alert", "video-title", "download-button", "save-toggle",
                 "'Close'", "Playback failed", "Loading…", "feed-video-row", "Window",
                 "Application"]
                    .contains { line.contains($0) }
            }
            .prefix(30)
        return "FACTS{\(facts.joined(separator: ","))} TREE{\(interesting.joined(separator: " ~ "))}"
    }

    /// Opens the fixture video page from the Home feed and returns a diagnostic
    /// trace (empty when the marker appeared after the first tap).
    ///
    /// iOS 26 cold-simulator launches have a documented tendency to swallow the
    /// first injected tap; the bounded single retry below re-taps ONLY while the
    /// feed row itself is still hittable, so a sheet that did present is never
    /// tapped through or dismissed by this helper.
    @discardableResult
    private func openVideoPageFromFeed(_ app: XCUIApplication, expecting marker: XCUIElement) -> String {
        app.buttons.matching(identifier: "feed-video-row").firstMatch.tap()
        if marker.waitForExistence(timeout: 15) { return "" }

        var trace = "tap1-no-marker"
        let row = app.buttons.matching(identifier: "feed-video-row").firstMatch
        if row.exists, row.isHittable {
            row.tap()
            if marker.waitForExistence(timeout: 10) { return "recovered-on-retry-tap" }
            trace += ";tap2-no-marker"
        } else {
            trace += ";row-gone-or-covered"
        }
        return trace + ";" + treeDiagnostics(app)
    }

    /// Brings an off-screen element into the lazy List hierarchy with bounded
    /// swipes. SwiftUI Lists on current iOS runtimes only materialize rows near
    /// the viewport, so below-the-fold controls (Save, download quality,
    /// comments) do not exist for XCUITest until the list scrolls to them.
    @discardableResult
    private func scrollToExist(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int = 5) -> Bool {
        var swipes = 0
        while !element.exists, swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }

    // MARK: - Journey A: shell

    func testShellTabsExistAndSwitchWithoutCorruption() {
        let app = launch("signed-out")

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Search"].exists)
        XCTAssertTrue(app.tabBars.buttons["Downloads"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)

        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
    }

    // MARK: - Journey B: signed-out Home

    func testSignedOutHomeShowsSignInCallToAction() {
        let app = launch("signed-out")
        XCTAssertTrue(
            app.buttons["Sign in with Google"].waitForExistence(timeout: 15),
            "fresh signed-out install must surface the sign-in CTA"
        )
    }

    // MARK: - Journey B2: signed-in Home error recovery

    func testHomeFeedErrorSurfacesAndRetryStaysInteractive() {
        let app = launch("home-network-error")
        XCTAssertTrue(
            app.staticTexts["Network error loading your subscriptions."].waitForExistence(timeout: 15),
            "feed failure must be visible, never a silent blank list"
        )
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(
            app.staticTexts["Network error loading your subscriptions."].waitForExistence(timeout: 5),
            "repeated failure stays in a coherent recoverable error state"
        )
    }

    // MARK: - Journey C: signed-in Home

    func testHomeFeedLoadsAndExplicitLoadMoreAppends() {
        let app = launch("home-loaded")
        let firstRow = app.buttons["feed-video-row"].firstMatch
        XCTAssertTrue(waitExists(firstRow), "fixture feed rows must render")

        let loadMore = app.buttons["load-more-button"]
        XCTAssertTrue(waitExists(loadMore), "page one advertises continuation")
        loadMore.tap()

        let appended = app.buttons.matching(identifier: "feed-video-row").element(boundBy: 3)
        XCTAssertTrue(appended.waitForExistence(timeout: 5), "explicit Load more must append page two")
    }

    // MARK: - Journey D: search

    func testSearchButtonSubmitsAndShortsNeverAppear() {
        let app = launch("search-ready")
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(waitExists(field), "search field must exist on the Search tab")
        field.tap()
        field.typeText("documentary")

        app.buttons["search-submit-button"].tap()

        XCTAssertTrue(
            app.staticTexts["Fixture Search Result Alpha"].waitForExistence(timeout: 5),
            "hydrated long-form result must render after explicit submit"
        )
        XCTAssertFalse(
            app.staticTexts["Fixture Sneaky Short"].exists,
            "short-form results are filtered before render, always"
        )

        let loadMore = app.buttons["load-more-button"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5))
        loadMore.tap()
        XCTAssertTrue(
            app.staticTexts["Fixture Search Result Gamma"].waitForExistence(timeout: 5),
            "Load more must append the second result page"
        )
    }

    func testKeyboardReturnSubmitsSearch() {
        let app = launch("search-ready")
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(waitExists(field), "search field must exist on the Search tab")
        field.tap()
        // Trailing newline presses the keyboard's Search key: proves the
        // onSubmit path without touching the Search button.
        field.typeText("keyboard query\n")

        XCTAssertTrue(
            app.staticTexts["Fixture Search Result Alpha"].waitForExistence(timeout: 5),
            "keyboard Return/Search must trigger the explicit-submit path"
        )
    }

    func testEmptyQuerySubmitIsRejectedWithoutNetworkOrStateChange() {
        let app = launch("search-ready")
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(waitExists(field), "search field must exist on the Search tab")

        XCTAssertFalse(
            app.buttons["search-submit-button"].isEnabled,
            "whitespace-only input must leave the Search button disabled"
        )
        field.tap()
        field.typeText("\n") // Return on an empty field: no API call, no state.
        XCTAssertFalse(app.staticTexts["No results for"].exists)
        XCTAssertFalse(app.buttons["load-more-button"].exists)
    }

    func testSearchErrorSurfacesAndRetryStaysInteractive() {
        let app = launch("search-error")
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(waitExists(field), "search field must exist on the Search tab")
        field.tap()
        field.typeText("anything\n")

        XCTAssertTrue(
            app.staticTexts["Network error."].waitForExistence(timeout: 5),
            "typed network failure must be visible, never a silent blank list"
        )
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        // Fixture keeps failing; the important behavior is that the UI stays
        // in a coherent recoverable error state instead of hanging or crashing.
        XCTAssertTrue(app.staticTexts["Network error."].waitForExistence(timeout: 5))
    }

    func testSearchWithNoHitsShowsEmptyState() {
        let app = launch("search-empty")
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(waitExists(field), "search field must exist on the Search tab")
        field.tap()
        field.typeText("nothing to find\n")

        XCTAssertTrue(
            app.staticTexts["No results for \"nothing to find\"."].waitForExistence(timeout: 5),
            "zero-hit search must show an explicit empty state"
        )
    }

    // MARK: - Journey E: video page

    func testVideoPageShowsMetadataSaveCommentsAndCloses() {
        let app = launch("video-page")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "fixture feed must load")
        let title = app.staticTexts["video-title"]
        let trace = openVideoPageFromFeed(app, expecting: title)

        XCTAssertTrue(title.exists, "video title must render [\(trace)]")
        XCTAssertEqual(app.staticTexts["video-title"].label, "Fixture Documentary One")
        XCTAssertTrue(app.staticTexts["video-channel"].exists)

        let save = app.buttons["save-toggle"]
        scrollToExist(app, save)
        XCTAssertTrue(save.exists, "save action must exist once scrolled into the lazy hierarchy")
        XCTAssertEqual(save.label, "Save video", "accessibility label reflects the action, not the state")
        save.tap()
        XCTAssertEqual(
            app.buttons["save-toggle"].label, "Remove from saved",
            "save toggle must reflect saved state"
        )

        let download = app.buttons["download-button"]
        scrollToExist(app, download)
        XCTAssertTrue(download.exists)
        XCTAssertTrue(download.isEnabled, "picker must offer qualities resolved by the extractor")

        let comment = app.staticTexts["Fixture comment alpha"]
        scrollToExist(app, comment)
        XCTAssertTrue(comment.waitForExistence(timeout: 5))

        app.buttons["Close"].tap()
        XCTAssertTrue(
            waitExists(app.buttons["feed-video-row"].firstMatch),
            "dismissal returns to the feed"
        )
    }

    // MARK: - Journey F/H: library persistence + relaunch + actionability

    func testLibraryRowsAreActionableAndSurviveRelaunch() {
        let app = launch("library-seeded")
        app.tabBars.buttons["Library"].tap()

        let historyRow = app.buttons["library-history-row"]
        XCTAssertTrue(waitExists(historyRow))
        let savedRow = app.buttons["library-saved-row"]
        XCTAssertTrue(savedRow.exists)

        // Relaunch against the same persistent fixture store: entries survive.
        app.terminate()
        let relaunched = launch("library-seeded")
        relaunched.tabBars.buttons["Library"].tap()
        XCTAssertTrue(waitExists(relaunched.buttons["library-history-row"]))
        XCTAssertTrue(relaunched.buttons["library-saved-row"].exists)

        // Continue Watching is actionable: opens the video page for that entry.
        // Asserted against the video page's own identifier, not the row label,
        // which would otherwise match the tapped row itself (vacuous pass).
        relaunched.buttons["library-history-row"].firstMatch.tap()
        let resumedTitle = relaunched.staticTexts["video-title"]
        XCTAssertTrue(
            resumedTitle.waitForExistence(timeout: 15),
            "tapping Continue Watching must open the stored video; \(treeDiagnostics(relaunched))"
        )
        XCTAssertEqual(resumedTitle.label, "Seeded In-Progress Video")
    }

    // MARK: - Journey G: downloads

    func testDownloadCompletesRegistersAndDeletes() {
        let app = launch("download-flow")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "fixture feed must load")
        let page = app.staticTexts["video-title"]
        let trace = openVideoPageFromFeed(app, expecting: page)
        XCTAssertTrue(page.exists, "video page must open from the fixture feed [\(trace)]")

        let download = app.buttons["download-button"]
        scrollToExist(app, download)
        XCTAssertTrue(download.exists, "download action must appear once qualities resolve")
        download.tap()

        app.tabBars.buttons["Downloads"].tap()
        let completedTitle = app.staticTexts["downloaded-row-title"].firstMatch
        XCTAssertTrue(
            completedTitle.waitForExistence(timeout: 10),
            "the scripted transfer must finalize, validate, and register offline media"
        )
        XCTAssertEqual(completedTitle.label, "Fixture Documentary One")

        app.buttons["Delete download"].firstMatch.tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "destructive delete requires explicit confirmation")
        confirm.tap()
        XCTAssertFalse(
            completedTitle.waitForExistence(timeout: 3),
            "confirmed deletion removes the downloaded-media row"
        )
        XCTAssertTrue(app.staticTexts["No downloaded videos yet."].exists)
    }

    func testDownloadFailureSurfacesTypedAlert() {
        let app = launch("download-failure")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "fixture feed must load")
        let page = app.staticTexts["video-title"]
        let trace = openVideoPageFromFeed(app, expecting: page)
        XCTAssertTrue(page.exists, "video page must open from the fixture feed [\(trace)]")

        let download = app.buttons["download-button"]
        scrollToExist(app, download)
        XCTAssertTrue(download.exists, "download action must appear once qualities resolve")
        download.tap()

        XCTAssertTrue(
            app.alerts["Download failed"].waitForExistence(timeout: 10),
            "transport failure must surface the typed failure alert"
        )
        // iOS 26 hosts alert message copy outside the alert's staticTexts
        // subtree; assert the typed cause app-wide instead.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "network problem")
            ).firstMatch.waitForExistence(timeout: 5),
            "failure copy should explain the cause and whether retry can help"
        )
    }
}
