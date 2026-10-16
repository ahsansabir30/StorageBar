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

    /// With "automatically hide the menu bar" on, the item sits above the screen edge until the
    /// pointer touches the top. Move there, wait for the bar to drop, then click like a user.
    private func revealMenuBarIfHidden() {
        guard !statusItem.isHittable else { return }
        let aboveScreen = statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        aboveScreen.withOffset(CGVector(dx: 0, dy: -statusItem.frame.midY + 1)).hover()
        let hittable = NSPredicate(format: "isHittable == true")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: statusItem)], timeout: 4)
    }

    private func openPopup() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "StorageBar status item not found")
        revealMenuBarIfHidden()
        try XCTSkipUnless(statusItem.isHittable, "Menu bar is auto-hidden and could not be revealed")
        for _ in 0..<3 {
            statusItem.click()
            if element("refreshButton").waitForExistence(timeout: 3) { return }
        }
        XCTFail("Popup did not open after repeated clicks")
    }

    func testThereIsExactlyOneStatusItem() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        XCTAssertEqual(app.statusItems.matching(identifier: "menuBarLabel").count, 1)
    }

    func testStatusItemExistsAndShowsStorageValue() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "StorageBar status item not found")
        // Visible text is the button title ("277 GB"); VoiceOver reads the label ("277 GB available").
        let text = statusItem.title
        XCTAssertNotNil(
            text.range(of: #"^\d+(\.\d)? (MB|GB|TB)$"#, options: .regularExpression),
            "Unexpected status item text: '\(text)'"
        )
        XCTAssertTrue(statusItem.label.hasSuffix("available"), "Unexpected spoken label: '\(statusItem.label)'")
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
