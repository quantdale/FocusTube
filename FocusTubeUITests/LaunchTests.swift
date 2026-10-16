import XCTest

final class LaunchTests: XCTestCase {
    func testRootTabsExist() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Search"].exists)
        #if FOCUSTUBE_LEGACY_DOWNLOADS
        XCTAssertTrue(app.tabBars.buttons["Downloads"].exists)
        #else
        XCTAssertFalse(app.tabBars.buttons["Downloads"].exists, "ADR-0007: no Downloads tab")
        #endif
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
    }
}
