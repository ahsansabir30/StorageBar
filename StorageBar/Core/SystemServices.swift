import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Notifications

protocol Notifying: Sendable {
    /// Asks the system for permission; returns whether notifications may be delivered.
    func requestAuthorization() async -> Bool
    /// Returns whether the notification was handed to the system.
    func post(level: StorageLevel, snapshot: StorageSnapshot) async -> Bool
}

struct SystemNotifier: Notifying {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(level: StorageLevel, snapshot: StorageSnapshot) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = level == .critical ? "Storage almost full" : "Storage running low"
        content.body = "\(ByteFormatter.compact(snapshot.availableBytes)) available "
            + "(\(snapshot.availablePercent)%) on \(snapshot.volumeName)."
        content.sound = level == .critical ? .default : nil
        // A fixed identifier replaces any earlier low-storage notification instead of stacking.
        do {
            try await center.add(UNNotificationRequest(identifier: "storagebar.low-storage", content: content, trigger: nil))
            return true
        } catch {
            return false
        }
    }
}

/// Sends a notification when free space drops into a worse state, never twice for the same state.
@MainActor
final class LowStorageAlerter {
    private let preferences: Preferences
    private let notifier: any Notifying
    private var gate = AlertGate()

    init(preferences: Preferences, notifier: any Notifying) {
        self.preferences = preferences
        self.notifier = notifier
    }

    func handle(_ snapshot: StorageSnapshot) async {
        let thresholds = preferences.thresholds
        guard preferences.notificationsEnabled else {
            // Keep tracking recovery so re-enabling alerts later starts from the true state.
            gate.observeRecovery(availableFraction: snapshot.availableFraction, thresholds: thresholds)
            return
        }
        let previous = gate
        guard let level = gate.levelToNotify(
            availableFraction: snapshot.availableFraction,
            thresholds: thresholds
        ) else { return }
        // If the system refused delivery, forget this level so the next refresh retries it.
        if await notifier.post(level: level, snapshot: snapshot) == false {
            gate = previous
        }
    }
}

// MARK: - Launch at login

@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItem: LoginItemControlling {
    private var service: SMAppService { .mainApp }

    var isEnabled: Bool { service.status == .enabled }
    var requiresApproval: Bool { service.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}
