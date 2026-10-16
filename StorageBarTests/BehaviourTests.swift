import Foundation
import Testing
@testable import StorageBar

// MARK: - Test doubles

actor FakeProvider: StorageProviding {
    private var results: [Result<StorageSnapshot, StorageError>]
    private(set) var callCount = 0

    init(_ results: [Result<StorageSnapshot, StorageError>]) {
        self.results = results
    }

    func snapshot() async throws -> StorageSnapshot {
        callCount += 1
        let next = results.count > 1 ? results.removeFirst() : results[0]
        return try next.get()
    }
}

actor RecordingNotifier: Notifying {
    private(set) var posted: [StorageLevel] = []
    private(set) var authorizationRequests = 0
    let grants: Bool
    private(set) var delivers: Bool

    init(grants: Bool = true, delivers: Bool = true) {
        self.grants = grants
        self.delivers = delivers
    }

    func setDelivers(_ value: Bool) { delivers = value }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return grants
    }

    func post(level: StorageLevel, snapshot: StorageSnapshot) async -> Bool {
        posted.append(level)
        return delivers
    }
}

func makeSnapshot(freePercent: Double) -> StorageSnapshot {
    StorageSnapshot(
        volumeName: "Macintosh HD",
        totalBytes: 1_000_000,
        freeBytes: Int64(freePercent / 100 * 1_000_000),
        availableForImportantUsageBytes: nil,
        date: Date()
    )
}

actor AsyncGate {
    private var isOpen = false
    private var hasBlocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends only the first caller until `open()`; later callers pass straight through.
    func waitOnce() async {
        if isOpen || hasBlocked { return }
        hasBlocked = true
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Throwaway defaults suite per test. Stale plists from earlier runs are removed once per process
/// so repeated test runs do not accumulate files in the app container.
func makeDefaults() -> UserDefaults {
    _ = removeStaleTestDefaults
    return UserDefaults(suiteName: "StorageBarTests-\(UUID().uuidString)")!
}

private let removeStaleTestDefaults: Void = {
    let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Preferences")
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for file in files where file.lastPathComponent.hasPrefix("StorageBarTests-") {
        try? FileManager.default.removeItem(at: file)
    }
}()

// MARK: - Preferences

@MainActor
struct PreferencesTests {
    @Test func defaultsMatchSpecification() {
        let p = Preferences(defaults: makeDefaults())
        #expect(p.displayFormat == .freeGB)
        #expect(p.refreshInterval == .oneMinute)
        #expect(p.showIcon == true)
        #expect(p.warningPercent == 10)
        #expect(p.notificationsEnabled == false)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = Preferences(defaults: defaults)
        first.displayFormat = .usedPercent
        first.refreshInterval = .fiveMinutes
        first.showIcon = true
        first.warningPercent = 20
        first.notificationsEnabled = true

        let second = Preferences(defaults: defaults)
        #expect(second.displayFormat == .usedPercent)
        #expect(second.refreshInterval == .fiveMinutes)
        #expect(second.showIcon)
        #expect(second.warningPercent == 20)
        #expect(second.notificationsEnabled)
    }

    @Test func corruptStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: "displayFormat")
        defaults.set(7, forKey: "refreshIntervalSeconds")
        defaults.set(500, forKey: "warningThresholdPercent")
        let p = Preferences(defaults: defaults)
        #expect(p.displayFormat == .freeGB)
        #expect(p.refreshInterval == .oneMinute)
        #expect(p.warningPercent == 30)
    }

    @Test func outOfRangeWarningIsClampedAndPersisted() {
        let defaults = makeDefaults()
        let p = Preferences(defaults: defaults)
        p.warningPercent = 1
        #expect(p.warningPercent == 5)
        #expect(Preferences(defaults: defaults).warningPercent == 5)
    }

    @Test func iconFormatForcesIconEvenWhenToggleIsOff() {
        let p = Preferences(defaults: makeDefaults())
        p.showIcon = false
        #expect(p.effectiveShowIcon == false)
        p.displayFormat = .iconAndGB
        #expect(p.effectiveShowIcon)
    }
}

// MARK: - Monitor

@MainActor
struct StorageMonitorTests {
    @Test func successfulRefreshPublishesSnapshot() async {
        let good = makeSnapshot(freePercent: 40)
        let monitor = StorageMonitor(provider: FakeProvider([.success(good)]))
        await monitor.refresh()
        #expect(monitor.snapshot == good)
        #expect(monitor.lastError == nil)
        #expect(!monitor.isRefreshing)
    }

    @Test func failureKeepsLastGoodSnapshotAndReportsError() async {
        let good = makeSnapshot(freePercent: 40)
        let monitor = StorageMonitor(
            provider: FakeProvider([.success(good), .failure(.volumeInfoUnavailable)])
        )
        await monitor.refresh()
        await monitor.refresh()
        #expect(monitor.snapshot == good)
        #expect(monitor.lastError == .volumeInfoUnavailable)
    }

    @Test func recoveryClearsError() async {
        let good = makeSnapshot(freePercent: 40)
        let monitor = StorageMonitor(
            provider: FakeProvider([.failure(.volumeInfoUnavailable), .success(good)])
        )
        await monitor.refresh()
        #expect(monitor.snapshot == nil)
        #expect(monitor.lastError != nil)
        await monitor.refresh()
        #expect(monitor.lastError == nil)
        #expect(monitor.snapshot == good)
    }

    @Test func onSnapshotFiresOnlyOnSuccess() async {
        let monitor = StorageMonitor(
            provider: FakeProvider([.success(makeSnapshot(freePercent: 40)), .failure(.volumeInfoUnavailable)])
        )
        var count = 0
        monitor.onSnapshot = { _ in count += 1 }
        await monitor.refresh()
        await monitor.refresh()
        #expect(count == 1)
    }

    @Test func slowCallbackDoesNotBlockLaterRefreshes() async {
        let provider = FakeProvider([.success(makeSnapshot(freePercent: 40))])
        let monitor = StorageMonitor(provider: provider)
        let gate = AsyncGate()
        monitor.onSnapshot = { _ in await gate.waitOnce() }

        let first = Task { await monitor.refresh() }
        while await provider.callCount == 0 { await Task.yield() }
        while monitor.isRefreshing { await Task.yield() }   // guard released before callback finishes
        await monitor.refresh()
        #expect(await provider.callCount == 2)
        await gate.open()
        await first.value
    }

    @Test func overlappingRefreshesAreCoalesced() async {
        let provider = FakeProvider([.success(makeSnapshot(freePercent: 40))])
        let monitor = StorageMonitor(provider: provider)
        async let a: Void = monitor.refresh()
        async let b: Void = monitor.refresh()
        _ = await (a, b)
        #expect(await provider.callCount == 1)
    }

    @Test func pollingLoopRefreshesRepeatedlyUntilStopped() async throws {
        let provider = FakeProvider([.success(makeSnapshot(freePercent: 40))])
        let monitor = StorageMonitor(provider: provider)
        monitor.start(every: .milliseconds(20))

        let deadline = ContinuousClock.now + .seconds(3)
        while await provider.callCount < 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        monitor.stop()
        #expect(await provider.callCount >= 3)

        try await Task.sleep(for: .milliseconds(100))
        let settled = await provider.callCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(await provider.callCount == settled)
    }
}

// MARK: - Notifications

@MainActor
struct LowStorageAlerterTests {
    private func make(enabled: Bool = true, notifier: RecordingNotifier) -> LowStorageAlerter {
        let prefs = Preferences(defaults: makeDefaults())
        prefs.notificationsEnabled = enabled
        return LowStorageAlerter(preferences: prefs, notifier: notifier)
    }

    @Test func disabledNotificationsNeverPost() async {
        let notifier = RecordingNotifier()
        let alerter = make(enabled: false, notifier: notifier)
        await alerter.handle(makeSnapshot(freePercent: 2))
        #expect(await notifier.posted.isEmpty)
    }

    @Test func repeatedLowReadingsPostOnce() async {
        let notifier = RecordingNotifier()
        let alerter = make(notifier: notifier)
        for _ in 0..<5 { await alerter.handle(makeSnapshot(freePercent: 8)) }
        #expect(await notifier.posted == [.warning])
    }

    @Test func escalationPostsCriticalAfterWarning() async {
        let notifier = RecordingNotifier()
        let alerter = make(notifier: notifier)
        await alerter.handle(makeSnapshot(freePercent: 8))
        await alerter.handle(makeSnapshot(freePercent: 3))
        await alerter.handle(makeSnapshot(freePercent: 3))
        #expect(await notifier.posted == [.warning, .critical])
    }

    @Test func healthyStoragePostsNothing() async {
        let notifier = RecordingNotifier()
        let alerter = make(notifier: notifier)
        await alerter.handle(makeSnapshot(freePercent: 50))
        #expect(await notifier.posted.isEmpty)
    }

    @Test func recoveryWhileDisabledRearmsAlerts() async {
        let notifier = RecordingNotifier()
        let prefs = Preferences(defaults: makeDefaults())
        prefs.notificationsEnabled = true
        let alerter = LowStorageAlerter(preferences: prefs, notifier: notifier)

        await alerter.handle(makeSnapshot(freePercent: 8))   // warning posted
        prefs.notificationsEnabled = false
        await alerter.handle(makeSnapshot(freePercent: 40))  // recovered while alerts are off
        prefs.notificationsEnabled = true
        await alerter.handle(makeSnapshot(freePercent: 8))   // must alert again
        #expect(await notifier.posted == [.warning, .warning])
    }

    @Test func undeliveredAlertIsRetriedOnNextRefresh() async {
        let notifier = RecordingNotifier(delivers: false)
        let alerter = make(notifier: notifier)
        await alerter.handle(makeSnapshot(freePercent: 8))
        await notifier.setDelivers(true)
        await alerter.handle(makeSnapshot(freePercent: 8))
        await alerter.handle(makeSnapshot(freePercent: 8))
        #expect(await notifier.posted == [.warning, .warning])
    }
}

// MARK: - App model

@MainActor
struct AppModelTests {
    final class FakeLoginItem: LoginItemControlling {
        var isEnabled = false
        var requiresApproval = false
        var shouldFail = false
        func setEnabled(_ enabled: Bool) throws {
            if shouldFail { throw CocoaError(.featureUnsupported) }
            isEnabled = enabled
        }
    }

    private func make(notifier: RecordingNotifier = .init(), login: FakeLoginItem = .init()) -> AppModel {
        AppModel(
            provider: FakeProvider([.success(makeSnapshot(freePercent: 40))]),
            preferences: Preferences(defaults: makeDefaults()),
            notifier: notifier,
            loginItem: login
        )
    }

    @Test func enablingNotificationsRequestsPermissionAndStoresGrant() async {
        let notifier = RecordingNotifier(grants: true)
        let model = make(notifier: notifier)
        await model.setNotifications(enabled: true)
        #expect(model.preferences.notificationsEnabled)
        #expect(await notifier.authorizationRequests == 1)
    }

    @Test func deniedPermissionLeavesNotificationsOff() async {
        let model = make(notifier: RecordingNotifier(grants: false))
        await model.setNotifications(enabled: true)
        #expect(!model.preferences.notificationsEnabled)
        #expect(model.notificationsDenied)
    }

    @Test func disablingNotificationsDoesNotAskForPermission() async {
        let notifier = RecordingNotifier()
        let model = make(notifier: notifier)
        await model.setNotifications(enabled: false)
        #expect(await notifier.authorizationRequests == 0)
    }

    @Test func launchAtLoginReflectsSystemState() {
        let login = FakeLoginItem()
        let model = make(login: login)
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin)
        model.setLaunchAtLogin(false)
        #expect(!model.launchAtLogin)
    }

    @Test func launchAtLoginFailureIsSurfacedAndStateStaysOff() {
        let login = FakeLoginItem()
        login.shouldFail = true
        let model = make(login: login)
        model.setLaunchAtLogin(true)
        #expect(!model.launchAtLogin)
        #expect(model.loginItemError != nil)
    }

    @Test func loginItemAwaitingApprovalIsReported() {
        let login = FakeLoginItem()
        login.requiresApproval = true
        let model = make(login: login)
        #expect(model.loginItemNeedsApproval)
        #expect(!model.launchAtLogin)
    }

    @Test func notificationsCanBeToggledOffThenOn() async {
        let notifier = RecordingNotifier()
        let model = make(notifier: notifier)
        await model.setNotifications(enabled: true)
        await model.setNotifications(enabled: false)
        #expect(!model.preferences.notificationsEnabled)
        await model.setNotifications(enabled: true)
        #expect(model.preferences.notificationsEnabled)
        #expect(!model.notificationsDenied)
        #expect(await notifier.authorizationRequests == 2)
    }

    @Test func startWiresPollingToAlerts() async throws {
        let notifier = RecordingNotifier()
        let model = AppModel(
            provider: FakeProvider([.success(makeSnapshot(freePercent: 3))]),
            preferences: Preferences(defaults: makeDefaults()),
            notifier: notifier,
            loginItem: FakeLoginItem()
        )
        model.preferences.notificationsEnabled = true
        model.start()
        defer { model.stop() }

        let deadline = ContinuousClock.now + .seconds(3)
        while await notifier.posted.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.monitor.snapshot != nil)
        #expect(await notifier.posted == [.critical])
    }
}
