import SwiftUI

@main
struct StorageBarApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        // The unit-test host launches this app too; it must not poll or touch real services.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            model.start()
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            PopupView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("StorageBar Preferences", id: PreferencesView.windowID) {
            PreferencesView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
