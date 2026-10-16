import AppKit
import SwiftUI
import Testing
@testable import StorageBar

/// Design-review tool, not a behavioural test: renders the real views offscreen to PNG so layout,
/// typography and light/dark appearance can be inspected without Screen Recording permission.
/// Runs only with `TEST_RUNNER_STORAGEBAR_RENDER=1`. Output: the test host's temp directory.
@MainActor
struct RenderPreviews {
    nonisolated static let enabled = ProcessInfo.processInfo.environment["STORAGEBAR_RENDER"] != nil

    private func render(_ view: some View, name: String, dark: Bool) {
        let content = view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("RENDERED \(url.path) \(Int(size.width))x\(Int(size.height))")
    }

    private func model(freePercent: Double?) async -> AppModel {
        let result: Result<StorageSnapshot, StorageError> = freePercent.map {
            .success(StorageSnapshot(
                volumeName: "Macintosh HD",
                totalBytes: 494_000_000_000,
                freeBytes: Int64($0 / 100 * 494_000_000_000),
                availableForImportantUsageBytes: nil,
                date: Date()
            ))
        } ?? .failure(.volumeInfoUnavailable)
        let model = AppModel(
            provider: FakeProvider([result]),
            preferences: Preferences(defaults: makeDefaults()),
            notifier: RecordingNotifier(),
            loginItem: RenderLoginItem()
        )
        await model.monitor.refresh()
        return model
    }

    @Test(.enabled(if: RenderPreviews.enabled))
    func renderAll() async {
        for dark in [false, true] {
            for (label, free) in [("normal", 55.0), ("warning", 8.0), ("critical", 3.0), ("error", nil)] as [(String, Double?)] {
                let m = await model(freePercent: free)
                render(PopupView(model: m), name: "popup-\(label)", dark: dark)
            }
            let m = await model(freePercent: 55)
            render(PreferencesView(model: m), name: "preferences", dark: dark)
        }
    }
}

@MainActor
private final class RenderLoginItem: LoginItemControlling {
    var isEnabled = false
    var requiresApproval = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
