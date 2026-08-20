import XCTest

final class LaunchTests: XCTestCase {
    func testRootTabsExist() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTesting")
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Search"].exists)
        XCTAssertTrue(app.tabBars.buttons["Downloads"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
    }
}
