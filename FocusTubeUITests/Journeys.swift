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
        let statusProbe = app.descendants(matching: .any)["player-status"].firstMatch
        facts.append(statusProbe.exists ? "pstate=\(statusProbe.label)" : "pstate=no")
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
                         "fixture-media-diagnostic", "search-field", "player-status"]
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
    /// While the keyboard is presented it owns the lower screen and swallows
    /// gestures originating inside its glass (run 2eeaba6: target frame frozen
    /// at y=1160 across every attempt) — such attempts drag from the safe band
    /// near the top of the window instead.
    private func scrollOnce(_ app: XCUIApplication, direction: SwipeDirection, attempt: Int) {
        if app.keyboards.firstMatch.exists {
            let win = app.frame
            guard win.height > 200 else { return }
            let x = win.midX
            let startY: CGFloat = direction == .up ? win.minY + 180 : win.midY
            let endY: CGFloat = direction == .up ? win.midY : win.minY + 180
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: x, dy: startY))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: x, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
            return
        }
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
                if late.exists {
                    // Existence double-read before ANY snapshot fetch: lazy
                    // rows can deallocate between exists and frame, and a
                    // vanished mid-query element throws an uncatchable
                    // snapshot failure (run 46844a8) instead of returning a
                    // diagnostic trace.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                    let confirm = locate(app)
                    if confirm.exists {
                        let screen = app.frame
                        let f = confirm.frame
                        if f.width > 1, f.height > 1,
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


    private func clearTextField(_ app: XCUIApplication, _ field: XCUIElement) {
        focusAndType(app, field, "")
        for _ in 0..<90 {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
    }

    private func submitLink(_ app: XCUIApplication, _ link: String) -> XCUIElement {
        let field = app.textFields["add-link-field"]
        XCTAssertTrue(waitExists(field), "Add tab must show the link field;\(treeDiagnostics(app))")
        clearTextField(app, field)
        field.typeText(link)
        dismissKeyboard(app)
        app.buttons["add-submit"].firstMatch.tap()
        return app.staticTexts["add-message"]
    }

    private func waitLabel(_ element: XCUIElement, contains text: String, _ timeout: TimeInterval = 10) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: p, object: element)], timeout: timeout) == .completed
    }

    // MARK: - Journey A: shell (ADR-0008: Home / Add / Library)

    func testShellTabsExistAndSwitchWithoutCorruption() {
        let app = launch("empty")
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Add"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertFalse(app.tabBars.buttons["Search"].exists, "ADR-0008: Search became Add")
        XCTAssertFalse(app.tabBars.buttons["Downloads"].exists, "ADR-0007: no Downloads tab")

        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["Add"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
    }

    // MARK: - Journey B: fresh install, no sign-in

    func testEmptyHomeInvitesAddingAChannelWithoutSignIn() {
        let app = launch("empty")
        XCTAssertTrue(
            app.descendants(matching: .any)["feed-empty"].firstMatch.waitForExistence(timeout: 15),
            "empty library must explain how to add channels;\(treeDiagnostics(app))"
        )
        XCTAssertFalse(app.buttons["Sign in with Google"].exists, "ADR-0008: no Google sign-in")
    }

    // MARK: - Journey C: subscriptions feed + Shorts firewall

    func testHomeFeedLoadsFromLocalSubscriptionsAndDropsShorts() {
        let app = launch("home-loaded")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "feed must load;\(treeDiagnostics(app))")
        XCTAssertTrue(app.staticTexts["Fixture Documentary One"].firstMatch.exists)
        // The List is lazy, so off-screen rows may not be realized; the Short is
        // asserted absent by title instead of by an exact row count.
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "feed-video-row").count, 1)
        XCTAssertFalse(app.staticTexts["Fixture Sneaky Short"].exists, "Shorts never reach the feed")
    }

    func testFeedFailureIsVisibleNotSilent() {
        let app = launch("home-network-error")
        XCTAssertTrue(
            app.descendants(matching: .any)["feed-partial-failure"].firstMatch.waitForExistence(timeout: 15),
            "a failing channel feed must be surfaced;\(treeDiagnostics(app))"
        )
    }

    // MARK: - Journey D: video page (IFrame engine + local actions)

    func testVideoPageShowsMetadataSaveSubscribeAndCloses() {
        let app = launch("video-page")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "fixture feed must load")
        let title = app.staticTexts["video-title"]
        let trace = openVideoPageFromFeed(app, expecting: title)
        XCTAssertTrue(title.exists, "video title must render [\(trace)]")
        XCTAssertEqual(title.label, "Fixture Documentary One")
        XCTAssertTrue(
            app.descendants(matching: .any)["player-playing"].firstMatch.waitForExistence(timeout: 10),
            "fake IFrame engine must drive the player to .playing;\(treeDiagnostics(app))"
        )
        XCTAssertTrue(app.buttons["subscribe-toggle"].firstMatch.waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons["save-toggle"].firstMatch.waitForExistence(timeout: 10), "save action must render")
        XCTAssertEqual(app.buttons["save-toggle"].firstMatch.label, "Save video")
        var toggled = false
        for _ in 0..<3 {
            let t = interact(app, locate: { $0.buttons["save-toggle"].firstMatch }, tap: true)
            XCTAssertTrue(t.isEmpty, "save action must be tappable [\(t)]")
            if waitLabel(app.buttons["save-toggle"].firstMatch, contains: "Remove from saved", 3) { toggled = true; break }
        }
        XCTAssertTrue(toggled, "save toggle must reflect saved state")
        XCTAssertFalse(app.buttons["download-button"].exists, "ADR-0007: no download control")
        XCTAssertFalse(app.staticTexts["Comments"].exists, "ADR-0008: comments need the Data API; removed")

        app.buttons["Close"].tap()
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "dismissal returns to the feed")
    }

    // MARK: - Journey F: library persistence + relaunch

    func testLibraryRowsAreActionableAndSurviveRelaunch() {
        let app = launch("library-seeded")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(waitExists(app.buttons["library-history-row"]))
        XCTAssertTrue(app.buttons["library-saved-row"].exists)

        app.terminate()
        let relaunched = launch("library-seeded")
        relaunched.tabBars.buttons["Library"].tap()
        XCTAssertTrue(waitExists(relaunched.buttons["library-history-row"]))
        XCTAssertTrue(relaunched.buttons["library-saved-row"].exists)

        relaunched.buttons["library-history-row"].firstMatch.tap()
        let resumedTitle = relaunched.staticTexts["video-title"]
        XCTAssertTrue(
            resumedTitle.waitForExistence(timeout: 15),
            "tapping Continue Watching must open the stored video; \(treeDiagnostics(relaunched))"
        )
        XCTAssertEqual(resumedTitle.label, "Seeded In-Progress Video")
    }

    // MARK: - Journey G: Add by link (ADR-0008)

    func testAddChannelLinkSubscribesLocally() {
        let app = launch("add-flow")
        app.tabBars.buttons["Add"].tap()
        let message = submitLink(app, "https://www.youtube.com/channel/UCfixturefixturefixture0")
        XCTAssertTrue(waitLabel(message, contains: "Subscribed to Fixture Channel", 15), "subscribe must confirm;\(treeDiagnostics(app))")
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5), "Home tab must open;\(treeDiagnostics(app))")
        XCTAssertTrue(waitExists(app.buttons["feed-video-row"].firstMatch), "new subscription feeds Home;\(treeDiagnostics(app))")
    }

    func testAddRejectsShortsAndHandleLinksWithGuidance() {
        let app = launch("add-flow")
        app.tabBars.buttons["Add"].tap()
        let message = submitLink(app, "https://www.youtube.com/shorts/abcdefghijk")
        XCTAssertTrue(waitLabel(message, contains: "Shorts aren't supported"), "Shorts links are rejected;\(treeDiagnostics(app))")
        _ = submitLink(app, "https://www.youtube.com/@somehandle")
        XCTAssertTrue(waitLabel(message, contains: "channel ID"), "handles get Copy-channel-ID guidance; label='\(message.label)'")
    }

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
    /// swallowed by keyboard glass. iOS 26 simulators swallow single injected
    /// taps often enough that one attempt is not a verdict — retries are
    /// bounded and each attempt verifies disappearance.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let gone = NSPredicate(format: "exists == false")
        for _ in 0..<3 {
            let bar = app.navigationBars.firstMatch
            if bar.exists, bar.isHittable {
                bar.tap()
            } else {
                app.swipeDown()
            }
            if XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: gone, object: app.keyboards.firstMatch)],
                timeout: 3
            ) == .completed {
                return
            }
        }
    }

}

