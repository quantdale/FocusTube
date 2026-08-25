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
        var facts = ["sheets=\(app.sheets.count)", "state=\(app.state.rawValue)", "keyboards=\(app.keyboards.count)"]
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
                         "'Close'", "Playback failed", "feed-video-row", "Window",
                         "Application", "TabBar", "NavigationBar", "downloaded-row",
                         "No downloaded videos yet.", "search-result-row", "load-more",
                         "fixture-media-diagnostic", "search-field"]
                            .contains { line.contains($0) }
                    }
                    .prefix(40)
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

    // MARK: - Scroll helpers

    private enum SwipeDirection { case up, down }

    /// The largest scrollable container (SwiftUI List/ScrollView host) whose
    /// bounds can host a drag, or nil when none is realized. An app-wide swipe
    /// can start on a tappable card button or the video page's horizontal action
    /// scroller, either of which swallows or redirects the vertical drag.
    private func largestScrollContainer(_ app: XCUIApplication) -> (element: XCUIElement, frame: CGRect)? {
        var bestFrame = CGRect.null
        var bestElement: XCUIElement?
        let scrollViews = app.scrollViews
        for index in 0..<scrollViews.count {
            let candidate = scrollViews.element(boundBy: index)
            let f = candidate.frame
            if f.width > 50, f.height > 100, f.width * f.height > bestFrame.width * bestFrame.height {
                bestFrame = f
                bestElement = candidate
            }
        }
        let collections = app.collectionViews
        for index in 0..<collections.count {
            let candidate = collections.element(boundBy: index)
            let f = candidate.frame
            if f.width > 50, f.height > 100, f.width * f.height > bestFrame.width * bestFrame.height {
                bestFrame = f
                bestElement = candidate
            }
        }
        guard let bestElement else { return nil }
        return (bestElement, bestFrame)
    }

    /// One explicit coordinate pan inside `frame` with a MODERATE fixed span.
    /// Full-range velocity flings proved counterproductive on current iOS 26
    /// simulators: each fling traverses the entire scroll range, so a
    /// below-fold target skips over the visible band entirely (CI breadcrumbs:
    /// target minY alternated 802 <-> -44). A moderate pan moves the content a
    /// predictable distance per attempt, letting the reveal loop park the
    /// target inside the window band.
    private func dragScroll(_ app: XCUIApplication, frame: CGRect, direction: SwipeDirection) {
        let span: CGFloat = 320
        let x = frame.midX
        guard frame.height > 2 * span + 40 else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: x, dy: direction == .up ? frame.maxY - span : frame.minY + span))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: x, dy: direction == .up ? frame.minY + span : frame.maxY - span))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Performs one scroll attempt. CI evidence across three runs: only
    /// container-scoped velocity swipes actually move content on this runtime —
    /// moderate coordinate pans produce zero movement, and app-level gestures
    /// land on the player/card layer. Velocity flings traverse a large range,
    /// which is why the video page now keeps its primary actions inside the
    /// first viewport (product-side fix) instead of relying on mid-page
    /// scrolling.
    private func scrollOnce(_ app: XCUIApplication, direction: SwipeDirection, attempt: Int) {
        let container = largestScrollContainer(app)
        if let container {
            if direction == .up { container.element.swipeUp(velocity: .fast) } else { container.element.swipeDown(velocity: .fast) }
        } else {
            dragScroll(app, frame: app.frame, direction: direction)
        }
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
        var frames: [String] = []
        while swipes < 18 {
            let current = locate(app)
            if current.exists {
                let f = current.frame
                if visible(f) {
                    // Tolerance double-read stability: two reads ~0.6s apart
                    // within 1pt of each other mean deceleration finished.
                    // Exact equality never converged on lazy List rows, whose
                    // frames keep micro-adjusting after every fling.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                    let recheckA = locate(app)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    let recheckB = locate(app)
                    func near(_ a: CGRect, _ b: CGRect) -> Bool {
                        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1
                            && abs(a.maxX - b.maxX) < 1 && abs(a.maxY - b.maxY) < 1
                    }
                    if recheckA.exists, recheckB.exists, near(recheckA.frame, recheckB.frame), visible(recheckB.frame) {
                        settled = recheckB
                        break
                    }
                    // Visible but still moving: NEVER scroll a visible target
                    // away — full-range flings would throw it out of the band.
                } else if f.height > 0 {
                    if f.maxY < win.midY {
                        scrollOnce(app, direction: .down, attempt: swipes)
                    } else {
                        scrollOnce(app, direction: .up, attempt: swipes)
                    }
                    // Bounded breadcrumb of how the target moved between scroll
                    // attempts: distinguishes "gesture scrolled but not enough"
                    // from "no strategy moves the content at all".
                    if frames.last != "\(Int(f.minY))" { frames.append("a\(swipes)y\(Int(f.minY))") }
                }
                // Degenerate frame: cell realized but not laid out yet.
            } else {
                scrollOnce(app, direction: .up, attempt: swipes)
                RunLoop.main.run(until: Date().addingTimeInterval(0.9))
            }
            swipes += 1
        }

        guard let el = settled else {
            // Last-resort tap: when every scroll strategy failed but the target
            // exists with a stable frame INSIDE the physical screen, its reported
            // position may simply disagree with the window band on current iOS
            // 26 simulators. One clamped coordinate tap is harmless if the point
            // is genuinely offscreen (nothing to hit) and decisive when the
            // geometry report lies. The caller's observable post-condition (label
            // flip, presented row, etc.) remains the honest verdict — this can
            // never fabricate a pass, only unblock a mis-reported reveal.
            if tap, swipes >= 12 {
                let late = locate(app)
                let screen = app.frame
                let f = late.frame
                if late.exists, f.width > 1, f.height > 1,
                   f.minY >= screen.minY, f.maxY <= screen.maxY + 1,
                   f.midX >= screen.minX, f.midX <= screen.maxX {
                    let cx = min(max(f.midX, screen.minX + 4), screen.maxX - 4)
                    let cy = min(max(f.midY, screen.minY + 4), screen.maxY - 4)
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                        .withOffset(CGVector(dx: cx, dy: cy))
                        .tap()
                    return ""
                }
            }
            let containerNote = largestScrollContainer(app).map { "container=\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "container=none"
            return "not-revealed-after-\(swipes)-attempts;\(containerNote);ys=\(frames.suffix(8).joined(separator: ","));tree=\(treeDiagnostics(app))"
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

    /// Synchronizes with the download pipeline after tapping the video page's
    /// download control: waits until the button's label returns to the idle
    /// "Download" state, which happens exactly when `DownloadService.download`
    /// returned (transfer finalized, validated, and registered in the offline
    /// library). If the tap never landed, the label was never left, so this
    /// returns immediately without masking a mis-tap — the row assertion below
    /// remains the honest verdict.
    private func waitForDownloadSettle(_ app: XCUIApplication) {
        let button = app.buttons["download-button"].firstMatch
        guard button.exists else { return }
        let idle = NSPredicate(format: "label == %@", "Download")
        let expectation = XCTNSPredicateExpectation(predicate: idle, object: button)
        XCTWaiter.wait(for: [expectation], timeout: 15)
    }

    // MARK: - Journey A: shell

    /// Scrolls until `id` exists, then taps it with a window-clamped
    /// coordinate. Robust against tall cards pushing controls below the fold
    /// and against partially-visible elements whose center lies offscreen.
    @discardableResult
    private func revealAndTap(_ app: XCUIApplication, _ id: String, maxSwipes: Int = 14) -> String {
        for attempt in 0..<maxSwipes {
            let el = app.descendants(matching: .any)[id].firstMatch
            if el.exists {
                let f = el.frame
                let win = app.frame
                if f.width > 1, f.height > 1,
                   f.maxY <= win.maxY - 8, f.minY >= win.minY {
                    let cx = min(max(f.midX, win.minX + 4), win.maxX - 4)
                    let cy = min(max(f.midY, win.minY + 4), win.maxY - 4)
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                        .withOffset(CGVector(dx: cx, dy: cy))
                        .tap()
                    return ""
                }
            }
            scrollOnce(app, direction: .up, attempt: attempt)
        }
        return "not-revealed-after-\(maxSwipes)-swipes"
    }

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

        // Rich cards are taller than the old text rows, so Load more may sit
        // below the fold: reveal via geometry before tapping.
        let loadTrace = interact(app, locate: { $0.buttons["load-more-button"].firstMatch }, tap: true)
        XCTAssertTrue(
            loadTrace.isEmpty,
            "page one must advertise continuation and be tappable [\(loadTrace)]"
        )

        // Page two exhausts the fixture feed (nextPageToken becomes nil), so the
        // load-more control DISAPPEARING is the deterministic append proof — a
        // lazy List may never realize far-below-fold rows for count-based queries.
        let stillAdvertising = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: stillAdvertising, object: app.buttons["load-more-button"].firstMatch)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .timedOut,
            "explicit Load more must consume the fixture's last page (control must disappear);\(treeDiagnostics(app))"
        )
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
            "hydrated long-form result must render after explicit submit;\(treeDiagnostics(app))"
        )
        XCTAssertFalse(
            app.staticTexts["Fixture Sneaky Short"].exists,
            "short-form results are filtered before render, always"
        )
        // Submitting drops field focus (product behavior): the keyboard must
        // not squeeze the results list while the reveal loop hunts load-more.

        let lmTrace = revealAndTap(app, "load-more-button")
        XCTAssertTrue(lmTrace.isEmpty, "load more must be reachable [\(lmTrace);\(treeDiagnostics(app))]")
        // Second page exhausts the fixture results: the disappearing load-more
        // control is the deterministic append proof (lazy List rows far below
        // the fold may never realize for count queries).
        let stillAdvertising = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: stillAdvertising, object: app.buttons["load-more-button"].firstMatch)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .timedOut,
            "Load more must consume the fixture's last result page;\(treeDiagnostics(app))"
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

        // Accessibility contract: the label reflects the ACTION, not the state,
        // before any interaction. The page is a deliberate non-lazy ScrollView,
        // so existence equals rendered — the assertion does not depend on
        // gesture-based scrolling reaching the control.
        XCTAssertTrue(
            app.buttons["save-toggle"].firstMatch.waitForExistence(timeout: 10),
            "save action must render"
        )
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

        let download = app.buttons["download-button"].firstMatch
        XCTAssertTrue(
            download.waitForExistence(timeout: 10),
            "download control must render"
        )
        let downloadReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: download
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [downloadReady], timeout: 15),
            .completed,
            "picker must offer qualities resolved by the extractor"
        )

        // Comments live in the same non-lazy ScrollView: existence proves they
        // rendered without depending on synthesized scroll gestures.
        XCTAssertTrue(
            app.staticTexts["Fixture comment alpha"].firstMatch.waitForExistence(timeout: 10),
            "fixture comment must render"
        )

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
        waitForDownloadSettle(app)

        app.tabBars.buttons["Downloads"].tap()
        // Tab arrival is asserted explicitly: a mis-delivered tab tap must fail
        // HERE with full diagnostics, never masquerade as a registration defect.
        XCTAssertTrue(
            app.navigationBars["Downloads"].waitForExistence(timeout: 8),
            "Downloads tab must come to front;\(treeDiagnostics(app))"
        )
        // SwiftUI Buttons merge their label children, so the row is addressed
        // by its own identifier; the merged label carries the real title.
        let completedRow = app.buttons.matching(identifier: "downloaded-row").firstMatch
        let downloadedRowCount = app.buttons.matching(identifier: "downloaded-row").count
        let emptyCopyVisible = app.staticTexts["No downloaded videos yet."].exists
        XCTAssertTrue(
            completedRow.waitForExistence(timeout: 10),
            "the scripted transfer must finalize, validate, and register offline media; rows=\(downloadedRowCount) emptyCopy=\(emptyCopyVisible);\(treeDiagnostics(app))"
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

    private func clearTextField(_ app: XCUIApplication, _ field: XCUIElement) {
        focusAndType(app, field, "")
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
        clearTextField(app, field)
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
        clearTextField(app, field)
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
        let composerCount = app.textViews.count
        let fieldCount = app.textFields.count
        XCTAssertTrue(
            target.waitForExistence(timeout: 5),
            "comment composer must exist; textViews=\(composerCount) fields=\(fieldCount);\(treeDiagnostics(app))"
        )

        target.tap()
        // Focus proof: typeText without a focused field silently drops input,
        // which would masquerade as a product defect in the reply path.
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "composer must gain keyboard focus before typing;\(treeDiagnostics(app))"
        )
        target.typeText("Fixture journey comment")
        // The keyboard may cover the submit control: dismiss it first so the
        // tap lands on the button, not on keyboard glass.
        dismissKeyboard(app)
        app.buttons["comment-submit"].tap()
        XCTAssertTrue(
            app.staticTexts["Fixture journey comment"].waitForExistence(timeout: 5),
            "posted top-level comment appears in the tree;\(treeDiagnostics(app))"
        )

        // Reply to the first fixture comment thread. Scrolling down to the
        // reply control moves the top composer offscreen: scroll back to it
        // before typing, or the submit tap lands nowhere.
        let replyTrace = interact(app, locate: { $0.buttons["reply-button-fc1"].firstMatch }, tap: true)
        XCTAssertTrue(replyTrace.isEmpty, "reply control must be reachable [\(replyTrace);\(treeDiagnostics(app))]")
        let composerBackTrace = interact(app, locate: { $0.buttons["comment-submit"].firstMatch }, tap: false)
        XCTAssertTrue(composerBackTrace.isEmpty, "composer must scroll back into view [\(composerBackTrace);\(treeDiagnostics(app))]")
        target.tap()
        // Focus proof: typeText without a focused field silently drops input,
        // which would masquerade as a product defect in the reply path.
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "composer must gain keyboard focus before typing;\(treeDiagnostics(app))"
        )
        target.typeText("Fixture journey reply")
        dismissKeyboard(app)
        app.buttons["comment-submit"].tap()
        let postedReply = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Fixture journey reply")
        ).firstMatch
        XCTAssertTrue(
            postedReply.waitForExistence(timeout: 5),
            "posted reply renders under its parent;\(treeDiagnostics(app))"
        )
    }

    /// Focuses a text entry element with one bounded retry (iOS 26 cold taps
    /// sometimes swallow the first focus tap), then types `text`.
    private func focusAndType(_ app: XCUIApplication, _ element: XCUIElement, _ text: String) {
        element.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            element.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(
            app.keyboards.firstMatch.exists,
            "element must gain keyboard focus before typing;\(treeDiagnostics(app))"
        )
        if !text.isEmpty {
            element.typeText(text)
        }
    }

    /// Dismisses the keyboard by tapping a neutral chrome point (the navigation
    /// bar), then waits until it is actually gone so subsequent taps cannot be
    /// swallowed by keyboard glass.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let bar = app.navigationBars.firstMatch
        if bar.exists, bar.isHittable {
            bar.tap()
        } else {
            app.swipeDown()
        }
        let gone = NSPredicate(format: "exists == false")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.keyboards.firstMatch)], timeout: 5)
    }

    // MARK: - Journey L: offline playback reaches playing (HB-014)

    func testOfflinePlaybackReachesPlayingStateWithFixtureMedia() {
        let app = launch("download-flow")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch))
        let trace = openVideoPageFromFeed(app, expecting: app.staticTexts["video-title"])
        let dlTrace = interact(app, locate: { $0.buttons["download-button"].firstMatch }, tap: true)
        XCTAssertTrue(dlTrace.isEmpty, "download control must reveal [\(dlTrace)];\(trace)")
        waitForDownloadSettle(app)

        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(
            app.navigationBars["Downloads"].waitForExistence(timeout: 8),
            "Downloads tab must come to front;\(treeDiagnostics(app))"
        )
        let completedRow = app.buttons.matching(identifier: "downloaded-row").firstMatch
        XCTAssertTrue(
            completedRow.waitForExistence(timeout: 10),
            "completed download row must render;\(treeDiagnostics(app))"
        )
        completedRow.tap()

        // The fixture transfer finalized REAL playable media: the player must
        // reach a genuine playing state, never the failed overlay.
        let playingMarker = app.descendants(matching: .any)["player-playing"].firstMatch
        let doneVisible = app.buttons["local-player-done"].exists
        let failedVisible = app.staticTexts["Playback failed"].exists
        XCTAssertTrue(
            playingMarker.waitForExistence(timeout: 15),
            "offline playback must reach .playing; sheet=\(doneVisible) failed=\(failedVisible);\(treeDiagnostics(app))"
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
