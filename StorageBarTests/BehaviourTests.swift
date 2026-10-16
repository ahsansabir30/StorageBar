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

    init(grants: Bool = true) { self.grants = grants }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return grants
    }

    func post(level: StorageLevel, snapshot: StorageSnapshot) async {
        posted.append(level)
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

func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "StorageBarTests-\(UUID().uuidString)")!
}

// MARK: - Preferences

@MainActor
struct PreferencesTests {
    @Test func defaultsMatchSpecification() {
        let p = Preferences(defaults: makeDefaults())
        #expect(p.displayFormat == .freeGB)
        #expect(p.refreshInterval == .oneMinute)
        #expect(p.showIcon == false)
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

    @Test func launchAtLoginFailureIsSurfacedAndStateStaysTrue() {
        let login = FakeLoginItem()
        login.shouldFail = true
        let model = make(login: login)
        model.setLaunchAtLogin(true)
        #expect(!model.launchAtLogin)
        #expect(model.loginItemError != nil)
    }
}
