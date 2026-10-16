import AppKit
import SwiftUI

@main
struct StorageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The status item and its UI are AppKit-owned (see StatusItemController); SwiftUI needs a scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controller: StatusItemController?

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test host launches this app too; it must not poll or create a menu bar item.
        guard !isRunningUnitTests else { return }

        // A second copy (e.g. run straight from a disk image) must not add a second menu bar item.
        if let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        let model = AppModel()
        model.start()
        self.model = model
        controller = StatusItemController(model: model)
    }

    /// Launching the app again while it runs (Finder, Spotlight) reveals the item's popup, which
    /// is the way back if the menu bar item was hidden or dragged away.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.togglePopover()
        return false
    }
}
