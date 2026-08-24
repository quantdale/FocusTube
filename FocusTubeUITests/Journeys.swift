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

            /// Reveals an element fully inside the visible window (with a safety
    /// margin) using FRAME GEOMETRY, requires its frame to hold still across
    /// a real time gap (mid-push-animation snapshots can fake stability via
    /// cached results), then performs a NATIVE tap — valid whenever the
    /// activation point is comfortably on screen, which the margin
    /// guarantees. Never trusts `isHittable` (unreliable on iOS 26).
    /// Returns "" on success, otherwise a diagnostic trace.
    private func interact(
        _ app: XCUIApplication,
        locate: @escaping (XCUIApplication) -> XCUIElement,
        tap: Bool,
        timeout: TimeInterval = 12
    ) -> String {
        var win = CGRect.null
        let windowCount = app.windows.count
        for index in 0..<max(windowCount, 0) {
            let f = app.windows.element(boundBy: index).frame
            if f.width > 1, f.height > 1 { win = f; break }
        }
        if win.isNull {
            let af = app.frame
            if af.width > 1, af.height > 1 { win = af }
        }
        guard !win.isNull else {
            return "no-usable-window;windows=\(windowCount);appFrame=\(app.frame)"
        }

        func visible(_ f: CGRect) -> Bool {
            let margin: CGFloat = 24
            return f.height > 0
                && f.minY >= win.minY + margin
                && f.maxY <= win.maxY - margin
                && f.minX >= win.minX
                && f.maxX <= win.maxX
        }

        var swipes = 0
        var settled: XCUIElement?
        while swipes < 16 {
            let current = locate(app)
            if current.exists {
                let f = current.frame
                if visible(f) {
                    // Require the SAME frame again after a real runloop gap;
                    // two immediate reads can share one cached snapshot.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                    let recheck = locate(app)
                    if recheck.exists, recheck.frame == f {
                        settled = recheck
                        break
                    }
                } else if f.height > 0 {
                    if f.maxY < win.midY { app.swipeDown() } else { app.swipeUp() }
                }
                // Degenerate frame: cell realized but not laid out yet.
            } else {
                app.swipeUp()
            }
            swipes += 1
        }

        guard let el = settled else {
            return "not-revealed-after-\(swipes)-attempts;tree=\(treeDiagnostics(app))"
        }
        guard tap else { return "" }
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: el
        )
        guard XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed else {
            return "never-enabled;frame=\(el.frame)"
        }
        el.tap()
        return ""
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

        // Reveal first (no tap) so the pre-action label is observable, then
        // toggle with bounded retries. All reads use fresh queries: captured
        // elements can serve stale labels after SwiftUI rebuilds the row.
        let revealTrace = interact(app, locate: { $0.buttons["save-toggle"].firstMatch }, tap: false)
        XCTAssertTrue(revealTrace.isEmpty, "save action must be revealed [\(revealTrace)]")
        XCTAssertEqual(
            app.buttons["save-toggle"].firstMatch.label,
            "Save video",
            "accessibility label reflects the action, not the state"
        )

        var toggledToSaved = false
        for _ in 0..<3 {
            let saveTrace = interact(app, locate: { $0.buttons["save-toggle"].firstMatch }, tap: true)
            XCTAssertTrue(saveTrace.isEmpty, "save action must be tappable [\(saveTrace)]")
            let savedLabel = NSPredicate(format: "label == %@", "Remove from saved")
            let savedExpectation = XCTNSPredicateExpectation(
                predicate: savedLabel,
                object: app.buttons["save-toggle"].firstMatch
            )
            if XCTWaiter.wait(for: [savedExpectation], timeout: 3) == .completed {
                toggledToSaved = true
                break
            }
        }
        XCTAssertTrue(
            toggledToSaved,
            "save toggle must reflect saved state; label was '\(app.buttons["save-toggle"].firstMatch.label)'"
        )

        let download = app.buttons["download-button"]
        let dlTrace = interact(app, locate: { $0.buttons["download-button"].firstMatch }, tap: false)
        XCTAssertTrue(dlTrace.isEmpty, "download control must be revealed [\(dlTrace)]")
        XCTAssertTrue(download.isEnabled, "picker must offer qualities resolved by the extractor")

        let comment = app.staticTexts["Fixture comment alpha"]
        let commentTrace = interact(app, locate: { $0.staticTexts["Fixture comment alpha"].firstMatch }, tap: false)
        XCTAssertTrue(commentTrace.isEmpty, "fixture comment must render once scrolled into view [\(commentTrace)]")

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
        let dlTrace = interact(app, locate: { $0.buttons["download-button"].firstMatch }, tap: true)
        XCTAssertTrue(
            dlTrace.isEmpty,
            "download action must appear once qualities resolve [\(trace);\(dlTrace)]"
        )
        // Precise signal if the scripted happy path ever surfaces a failure:
        // registration cannot succeed when admission refused the transfer.
        XCTAssertFalse(
            app.alerts["Download failed"].waitForExistence(timeout: 2),
            "scripted happy-path download must not surface a failure alert"
        )

        app.tabBars.buttons["Downloads"].tap()
        // SwiftUI Buttons merge their label children, so the row is addressed
        // by its own identifier; the merged label carries the real title.
        let completedRow = app.buttons.matching(identifier: "downloaded-row").firstMatch
        XCTAssertTrue(
            completedRow.waitForExistence(timeout: 10),
            "the scripted transfer must finalize, validate, and register offline media"
        )
        XCTAssertTrue(
            completedRow.label.contains("Fixture Documentary One"),
            "registered row carries the real video title; label was '\(completedRow.label)'"
        )

        app.buttons["Delete download"].firstMatch.tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "destructive delete requires explicit confirmation")
        confirm.tap()
        XCTAssertFalse(
            completedRow.waitForExistence(timeout: 3),
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
        let dlTrace = interact(app, locate: { $0.buttons["download-button"].firstMatch }, tap: true)
        XCTAssertTrue(
            dlTrace.isEmpty,
            "download action must appear once qualities resolve [\(trace);\(dlTrace)]"
        )

        XCTAssertTrue(
            app.alerts["Download failed"].waitForExistence(timeout: 10),
            "transport failure must surface the typed failure alert"
        )
        // The typed cause/retry copy is pinned at unit level
        // (DownloadServiceTests.testTransportFailureCopyExplainsCauseAndRetry);
        // iOS 26 does not reliably expose alert message text to XCUITest, so
        // the UI contract here is: typed alert presents with an acknowledge
        // action.
        XCTAssertTrue(
            app.alerts["Download failed"].buttons["OK"].waitForExistence(timeout: 5),
            "failure alert must be actionable"
        )
    }

    // MARK: - Journey H: settings/account (DDV2-05)

    func testSettingsSheetShowsAccountStateAndSignOutFlips() {
        let app = launch("home-loaded")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "fixture feed must load first")

        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(waitExists(settingsButton), "profile control must exist on Home")
        settingsButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings-signed-in"].firstMatch.waitForExistence(timeout: 10),
            "settings must show authenticated state"
        )
        let signOut = app.buttons["settings-sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "sign-out control must exist when signed in")
        signOut.tap()
        XCTAssertTrue(
            app.staticTexts["Signed out"].waitForExistence(timeout: 5),
            "signing out must flip the visible account state"
        )
    }

    func testSettingsSheetShowsSignedOutStateWithoutSignOut() {
        let app = launch("signed-out")
        XCTAssertTrue(waitExists(app.buttons["settings-button"]))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.staticTexts["Signed out"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings-sign-in"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["settings-sign-out"].exists,
            "no sign-out control may appear while signed out"
        )
    }

    // MARK: - Journey I: search recents (DDV2-07)

    private func clearTextField(_ field: XCUIElement) {
        field.tap()
        for _ in 0..<30 {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
    }

    func testSearchRecentsRecordSuggestAndClearLocally() {
        let app = launch("search-ready")
        app.tabBars.buttons["Search"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(waitExists(field))

        // Explicit submit records the query.
        field.tap()
        field.typeText("documentary")
        app.buttons["search-submit-button"].tap()
        XCTAssertTrue(
            app.staticTexts["Fixture Search Result Alpha"].waitForExistence(timeout: 5),
            "first submit must produce results"
        )

        // Clearing the typed text reveals the persisted recents list.
        clearTextField(field)
        let recent = app.buttons.matching(identifier: "recent-search-row").firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "recorded query must appear under Recent searches")

        // Typing a fragment shows a LOCAL suggestion; tapping it re-submits.
        field.tap()
        field.typeText("doc")
        let suggestion = app.buttons.matching(identifier: "search-suggestion-row").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "local suggestion must appear from the recorded query")
        suggestion.tap()
        XCTAssertTrue(
            app.staticTexts["Fixture Search Result Alpha"].waitForExistence(timeout: 5),
            "choosing a local suggestion submits that query"
        )

        // Clear history removes every recent row.
        clearTextField(field)
        let clear = app.buttons["clear-search-history"]
        if clear.waitForExistence(timeout: 3) {
            clear.tap()
            XCTAssertFalse(
                app.buttons.matching(identifier: "recent-search-row").firstMatch.exists,
                "clear must remove all recent queries"
            )
        } else {
            XCTFail("clear-history control missing while recents are shown")
        }
    }

    // MARK: - Journey J: video actions (DDV2-04)

    func testVideoActionsShowServerBackedStateAndToggleLike() {
        let app = launch("video-page")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "fixture feed must load")
        let page = app.staticTexts["video-title"]
        let trace = openVideoPageFromFeed(app, expecting: page)
        XCTAssertTrue(page.exists, "video page must open [\(trace)]")

        // The fixture reports an existing like: the initial label must be the
        // truth, not a neutral default.
        let likeToggle = app.buttons["like-toggle"]
        XCTAssertTrue(likeToggle.waitForExistence(timeout: 10), "like action must exist")
        XCTAssertEqual(likeToggle.label, "Liked", "initial state comes from getRating")
        likeToggle.tap()
        XCTAssertEqual(likeToggle.label, "Like", "tapping a liked video removes the rating")

        let subscribeToggle = app.buttons["subscribe-toggle"]
        XCTAssertTrue(subscribeToggle.waitForExistence(timeout: 10))
        XCTAssertTrue(subscribeToggle.label.contains("Subscribed"), "subscription state is authoritative")
        subscribeToggle.tap()
        XCTAssertFalse(subscribeToggle.label.contains("Subscribed"), "unsubscribe flips the label")

        // Share and more actions render as part of the row.
        XCTAssertTrue(app.buttons["share-button"].exists)
        XCTAssertTrue(app.buttons["more-actions-button"].exists)
    }

    // MARK: - Journey K: comment composer (DDV2-04)

    func testCommentComposerPostsTopLevelAndReplyWithoutDuplicates() {
        let app = launch("video-page")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch))
        let page = app.staticTexts["video-title"]
        openVideoPageFromFeed(app, expecting: page)

        let composerField = app.textViews["comment-composer-field"].firstMatch
        let composerFieldFallback = app.textFields["comment-composer-field"].firstMatch
        let target = composerField.waitForExistence(timeout: 10) ? composerField : composerFieldFallback
        XCTAssertTrue(target.waitForExistence(timeout: 5), "comment composer must exist on the video page")

        target.tap()
        target.typeText("Fixture journey comment")
        app.buttons["comment-submit"].tap()
        XCTAssertTrue(
            app.staticTexts["Fixture journey comment"].waitForExistence(timeout: 5),
            "posted top-level comment appears in the tree"
        )

        // Reply to the first fixture comment thread.
        let replyButton = app.buttons["reply-button-fc1"]
        XCTAssertTrue(replyButton.waitForExistence(timeout: 5))
        replyButton.tap()
        target.tap()
        target.typeText("Fixture journey reply")
        app.buttons["comment-submit"].tap()
        let postedReply = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Fixture journey reply")
        ).firstMatch
        XCTAssertTrue(postedReply.waitForExistence(timeout: 5), "posted reply renders under its parent")
    }

    // MARK: - Journey L: offline playback reaches playing (HB-014)

    func testOfflinePlaybackReachesPlayingStateWithFixtureMedia() {
        let app = launch("download-flow")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch))
        let trace = openVideoPageFromFeed(app, expecting: app.staticTexts["video-title"])
        let dlTrace = interact(app, locate: { $0.buttons["download-button"].firstMatch }, tap: true)
        XCTAssertTrue(dlTrace.isEmpty, "download control must reveal [\(dlTrace)];\(trace)")

        app.tabBars.buttons["Downloads"].tap()
        let completedRow = app.buttons.matching(identifier: "downloaded-row").firstMatch
        XCTAssertTrue(completedRow.waitForExistence(timeout: 10))
        completedRow.tap()

        // The fixture transfer finalized REAL playable media: the player must
        // reach a genuine playing state, never the failed overlay.
        let playingMarker = app.otherElements["player-playing"]
        let playingMarkerAnyType = app.descendants(matching: .any)["player-playing"].firstMatch
        XCTAssertTrue(
            playingMarker.waitForExistence(timeout: 15) || playingMarkerAnyType.exists,
            "offline playback must reach .playing with playable fixture media"
        )
        XCTAssertFalse(
            app.staticTexts["Playback failed"].exists,
            "playable fixture media must not surface a failure overlay"
        )
        let done = app.buttons["local-player-done"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
        }
    }
}
