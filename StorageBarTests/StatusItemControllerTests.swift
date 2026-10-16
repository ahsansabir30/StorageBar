import AppKit
import Foundation
import Testing
@testable import StorageBar

/// Exercises the real AppKit controller (creates and removes a real status item) without relying
/// on mouse clicks, which are not reliably automatable when the menu bar auto-hides.
@MainActor
struct StatusItemControllerTests {
    private func makeController() -> StatusItemController {
        StatusItemController(model: AppModel(
            provider: FakeProvider([.success(makeSnapshot(freePercent: 40))]),
            preferences: Preferences(defaults: makeDefaults()),
            notifier: RecordingNotifier(),
            loginItem: StubLoginItem()
        ))
    }

    @Test func showPreferencesCreatesAndShowsOneTitledWindow() {
        let controller = makeController()
        defer {
            NSApp.windows.filter { $0.title == "StorageBar Preferences" }.forEach { $0.close() }
            controller.tearDown()
        }
        #expect(!controller.isPreferencesVisible)

        controller.showPreferences()
        controller.showPreferences()   // reopening must reuse the window, not stack new ones

        let windows = NSApp.windows.filter { $0.title == "StorageBar Preferences" }
        #expect(windows.count == 1)
        #expect(controller.isPreferencesVisible)
    }

    @Test func statusItemUsesStableAutosaveName() {
        #expect(StatusItemController.autosaveName == "StorageBar")
    }
}

@MainActor
private final class StubLoginItem: LoginItemControlling {
    var isEnabled = false
    var requiresApproval = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
