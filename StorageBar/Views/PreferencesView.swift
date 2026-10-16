import SwiftUI

struct PreferencesView: View {
    private static let warningChoices = [5, 10, 15, 20, 30]

    @Bindable private var preferences: Preferences
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        _preferences = Bindable(model.preferences)
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.loginItemNeedsApproval {
                    note("Approve StorageBar in System Settings › General › Login Items.")
                }
                if let error = model.loginItemError {
                    note(error)
                }
                Picker("Refresh", selection: $preferences.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { Text("Every \($0.title)").tag($0) }
                }
                .onChange(of: preferences.refreshInterval) { model.restartPolling() }
            }

            Section("Appearance") {
                Picker("Menu bar shows", selection: $preferences.displayFormat) {
                    ForEach(DisplayFormat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show disk icon", isOn: $preferences.showIcon)
                    .disabled(preferences.displayFormat.forcesIcon)
            }

            Section {
                Toggle("Low-storage alerts", isOn: Binding(
                    get: { preferences.notificationsEnabled },
                    set: { enabled in Task { await model.setNotifications(enabled: enabled) } }
                ))
                Picker("Warn when below", selection: $preferences.warningPercent) {
                    ForEach(warningChoices, id: \.self) { Text("\($0)% available").tag($0) }
                }
                .disabled(!preferences.notificationsEnabled)
            } header: {
                Text("Notifications")
            } footer: {
                if model.notificationsDenied {
                    note("Notifications are blocked. Allow them in System Settings › Notifications.")
                } else {
                    note("You’ll also be alerted below \(preferences.thresholds.criticalPercent)%.")
                }
            }

            Section {
                Button("About StorageBar…") { AppInfo.showAbout() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.syncLoginItem() }
    }

    /// Standard choices plus any previously stored value, so the picker never shows a blank selection.
    private var warningChoices: [Int] {
        Array(Set(Self.warningChoices + [preferences.warningPercent])).sorted()
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
