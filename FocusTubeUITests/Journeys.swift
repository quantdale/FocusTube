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
            app.buttons["Sign in with Google"].waitForExistence(timeout: 5),
            "fresh signed-out install must surface the sign-in CTA"
        )
    }

    // MARK: - Journey C: signed-in Home

    func testHomeFeedLoadsAndExplicitLoadMoreAppends() {
        let app = launch("home-loaded")
        let firstRow = app.buttons["feed-video-row"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))

        let loadMore = app.buttons["load-more-button"]
        XCTAssertTrue(loadMore.waitForExistence(timeout: 5), "page one advertises continuation")
        loadMore.tap()

        let appended = app.buttons.matching(identifier: "feed-video-row").element(boundBy: 3)
        XCTAssertTrue(appended.waitForExistence(timeout: 5), "explicit Load more must append page two")
    }

    // MARK: - Journey D: search

    func testSearchButtonSubmitsAndShortsNeverAppear() {
        let app = launch("search-ready")
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

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
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["feed-video-row"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["feed-video-row"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["video-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["video-title"].label, "Fixture Documentary One")
        XCTAssertTrue(app.staticTexts["video-channel"].exists)
        XCTAssertTrue(app.staticTexts["Fixture comment alpha"].waitForExistence(timeout: 5))

        let save = app.buttons["save-toggle"]
        XCTAssertTrue(save.exists)
        XCTAssertEqual(save.label, "Save video", "accessibility label reflects the action, not the state")
        save.tap()
        XCTAssertEqual(
            app.buttons["save-toggle"].label, "Remove from saved",
            "save toggle must reflect saved state"
        )

        let download = app.buttons["download-button"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        XCTAssertTrue(download.isEnabled, "picker must offer qualities resolved by the extractor")

        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["feed-video-row"].firstMatch.waitForExistence(timeout: 5), "dismissal returns to the feed")
    }

    // MARK: - Journey F/H: library persistence + relaunch + actionability

    func testLibraryRowsAreActionableAndSurviveRelaunch() {
        let app = launch("library-seeded")
        app.tabBars.buttons["Library"].tap()

        let historyRow = app.buttons["library-history-row"]
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5))
        let savedRow = app.buttons["library-saved-row"]
        XCTAssertTrue(savedRow.exists)

        // Relaunch against the same persistent fixture store: entries survive.
        app.terminate()
        let relaunched = launch("library-seeded")
        relaunched.tabBars.buttons["Library"].tap()
        XCTAssertTrue(relaunched.buttons["library-history-row"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.buttons["library-saved-row"].exists)

        // Continue Watching is actionable: opens the video page for that entry.
        relaunched.buttons["library-history-row"].firstMatch.tap()
        XCTAssertTrue(
            relaunched.staticTexts["Seeded In-Progress Video"].waitForExistence(timeout: 5),
            "tapping Continue Watching must open the stored video"
        )
    }

    // MARK: - Journey G: downloads

    func testDownloadCompletesRegistersAndDeletes() {
        let app = launch("download-flow")
        XCTAssertTrue(app.buttons["feed-video-row"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["feed-video-row"].firstMatch.tap()

        let download = app.buttons["download-button"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["feed-video-row"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["feed-video-row"].firstMatch.tap()

        let download = app.buttons["download-button"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()

        XCTAssertTrue(
            app.alerts["Download failed"].waitForExistence(timeout: 10),
            "transport failure must surface the typed failure alert"
        )
        XCTAssertTrue(
            app.alerts["Download failed"].staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "network problem")
            ).firstMatch.exists,
            "failure copy should explain the cause and whether retry can help"
        )
    }
}
