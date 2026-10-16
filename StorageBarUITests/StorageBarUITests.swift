import XCTest

/// Drives the real app through the accessibility API. Requires the test runner to be granted
/// Accessibility access. Popup interaction tests are skipped (not passed) when the menu bar is
/// auto-hidden, because the status item cannot be clicked while it sits above the screen edge.
@MainActor
final class StorageBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    private var statusItem: XCUIElement { app.statusItems["menuBarLabel"].firstMatch }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Clicks the status item until the popup appears. The first click can land while the app is
    /// still activating after launch, so a few attempts are made before failing.
    private func openPopup() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "StorageBar status item not found")
        try XCTSkipUnless(statusItem.isHittable, "Menu bar is auto-hidden; status item cannot be clicked")
        for _ in 0..<4 {
            statusItem.click()
            if element("refreshButton").waitForExistence(timeout: 3) { return }
        }
        XCTFail("Popup did not open after repeated clicks")
    }

    func testStatusItemExistsAndShowsStorageValue() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "StorageBar status item not found")
        let text = statusItem.title
        XCTAssertNotNil(
            text.range(of: #"^\d+(\.\d)? (MB|GB|TB)$"#, options: .regularExpression),
            "Unexpected status item text: '\(text)'"
        )
    }

    func testStatusItemOpensPopupWithAllActions() throws {
        try openPopup()
        for id in ["refreshButton", "storageSettingsButton", "preferencesButton", "quitButton"] {
            XCTAssertTrue(element(id).waitForExistence(timeout: 5), "Missing popup action \(id)")
        }
    }

    func testPreferencesWindowOpensFromPopup() throws {
        try openPopup()
        let button = element("preferencesButton")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(app.windows["StorageBar Preferences"].waitForExistence(timeout: 10))
    }
}
