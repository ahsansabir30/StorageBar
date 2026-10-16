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
        // The older copy always wins (ties broken by pid), so two simultaneous launches cannot
        // both quit and leave no item.
        let me = NSRunningApplication.current
        let older = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first { other in
                guard other.processIdentifier != me.processIdentifier else { return false }
                let (theirs, mine) = (other.launchDate ?? .distantFuture, me.launchDate ?? .distantFuture)
                return theirs < mine || (theirs == mine && other.processIdentifier < me.processIdentifier)
            }
        if let older {
            older.activate()
            exit(0)
        }

        let model = makeModel()
        model.start()
        self.model = model
        controller = StatusItemController(model: model)
    }

    private func makeModel() -> AppModel {
        #if DEBUG
        // Debug builds only: preview low-storage states, e.g. STORAGEBAR_FAKE_FREE_PERCENT=3.
        if let raw = ProcessInfo.processInfo.environment["STORAGEBAR_FAKE_FREE_PERCENT"], let percent = Double(raw) {
            return AppModel(provider: DebugFixedProvider(freePercent: percent))
        }
        #endif
        return AppModel()
    }

    /// Launching the app again while it runs (Finder, Spotlight) reveals the item's popup, which
    /// is the way back if the menu bar item was hidden or dragged away.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showMenu()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        controller?.tearDown()
    }
}

#if DEBUG
/// Reports a fixed free-space percentage of a 500 GB disk. Compiled out of Release builds.
private struct DebugFixedProvider: StorageProviding {
    let freePercent: Double

    func snapshot() async throws -> StorageSnapshot {
        let total: Int64 = 500_000_000_000
        return StorageSnapshot(
            volumeName: "Macintosh HD",
            totalBytes: total,
            freeBytes: Int64(Double(total) * freePercent / 100),
            availableForImportantUsageBytes: nil,
            date: Date()
        )
    }
}
#endif
