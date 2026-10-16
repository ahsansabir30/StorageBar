import SwiftUI

struct PreferencesView: View {
    static let windowID = "preferences"

    @Bindable private var preferences: Preferences
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        _preferences = Bindable(model.preferences)
    }

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Display", selection: $preferences.displayFormat) {
                    ForEach(DisplayFormat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show storage icon", isOn: $preferences.showIcon)
                    .disabled(preferences.displayFormat.forcesIcon)
            }

            Section("Monitoring") {
                Picker("Refresh every", selection: $preferences.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: preferences.refreshInterval) { model.restartPolling() }

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
            }

            Section("Low Storage Alerts") {
                Toggle("Notify when storage is low", isOn: Binding(
                    get: { preferences.notificationsEnabled },
                    set: { enabled in Task { await model.setNotifications(enabled: enabled) } }
                ))
                if model.notificationsDenied {
                    note("Notifications are blocked. Allow them in System Settings › Notifications.")
                }
                Stepper(
                    "Warn below \(preferences.warningPercent)% available",
                    value: $preferences.warningPercent,
                    in: StorageThresholds.warningRange
                )
                note("Critical alert below \(preferences.thresholds.criticalPercent)%.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.syncLoginItem() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
