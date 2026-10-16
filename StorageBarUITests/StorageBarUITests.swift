import XCTest

/// Drives the real app through the accessibility API. Requires the test runner to be granted
/// Accessibility access; without it these tests fail to find the status item.
final class StorageBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    func testStatusItemOpensPopupWithAllActions() throws {
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "StorageBar status item not found")
        statusItem.click()

        for id in ["refreshButton", "storageSettingsButton", "preferencesButton", "quitButton"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[id].waitForExistence(timeout: 5),
                "Missing popup action \(id)"
            )
        }
    }

    func testPreferencesWindowOpensFromPopup() throws {
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        app.descendants(matching: .any)["preferencesButton"].click()
        XCTAssertTrue(app.windows["StorageBar Preferences"].waitForExistence(timeout: 5))
    }
}
