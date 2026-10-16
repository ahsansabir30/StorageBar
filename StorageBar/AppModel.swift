import AppKit
import Observation

/// Composition root: owns the services and wires them together. No logic beyond wiring.
@MainActor
@Observable
final class AppModel {
    let preferences: Preferences
    let monitor: StorageMonitor
    @ObservationIgnored let notifier: any Notifying
    @ObservationIgnored private let alerter: LowStorageAlerter
    @ObservationIgnored private let loginItem: any LoginItemControlling
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var clickMonitor: Any?
    /// The MenuBarExtra popup window, captured by the popup view.
    @ObservationIgnored weak var popupWindow: NSWindow?

    private(set) var launchAtLogin: Bool
    private(set) var loginItemNeedsApproval: Bool
    private(set) var loginItemError: String?
    private(set) var notificationsDenied = false

    init(
        provider: any StorageProviding = VolumeStorageProvider(),
        preferences: Preferences = Preferences(),
        notifier: any Notifying = SystemNotifier(),
        loginItem: any LoginItemControlling = SystemLoginItem()
    ) {
        self.preferences = preferences
        self.notifier = notifier
        self.loginItem = loginItem
        monitor = StorageMonitor(provider: provider)
        alerter = LowStorageAlerter(preferences: preferences, notifier: notifier)
        launchAtLogin = loginItem.isEnabled
        loginItemNeedsApproval = loginItem.requiresApproval
    }

    /// Begins polling and wake-from-sleep refreshes. Safe to call again: it replaces the old ones.
    func start() {
        monitor.onSnapshot = { [alerter] snapshot in await alerter.handle(snapshot) }
        restartPolling()
        installOutsideClickMonitor()
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            let wake = NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification)
            for await _ in wake {
                await self?.monitor.refresh()
            }
        }
    }

    /// A click in any other app, the desktop or another status item never reaches this app, so a
    /// global monitor is the reliable signal to close the popup (it may never become key window).
    private func installOutsideClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissPopup() }
        }
    }

    func dismissPopup() {
        if let window = popupWindow, window.isVisible { window.orderOut(nil) }
    }

    func stop() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        monitor.stop()
        wakeTask?.cancel()
        wakeTask = nil
    }

    func restartPolling() {
        monitor.start(every: preferences.refreshInterval.duration)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        syncLoginItem()
    }

    func syncLoginItem() {
        launchAtLogin = loginItem.isEnabled
        loginItemNeedsApproval = loginItem.requiresApproval
    }

    /// Turning notifications on asks for system permission; it stays off if denied.
    func setNotifications(enabled: Bool) async {
        guard enabled else {
            preferences.notificationsEnabled = false
            notificationsDenied = false
            return
        }
        let granted = await notifier.requestAuthorization()
        preferences.notificationsEnabled = granted
        notificationsDenied = !granted
    }
}
