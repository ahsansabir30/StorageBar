import Foundation
import Observation

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
    var duration: Duration { .seconds(rawValue) }

    var title: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

/// User settings persisted in `UserDefaults`. Launch-at-login is owned by the system
/// (`SMAppService`) and deliberately not stored here.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let displayFormat = "displayFormat"
        static let refreshInterval = "refreshIntervalSeconds"
        static let showIcon = "showIcon"
        static let warningPercent = "warningThresholdPercent"
        static let notificationsEnabled = "notificationsEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var displayFormat: DisplayFormat {
        didSet { defaults.set(displayFormat.rawValue, forKey: Key.displayFormat) }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    var showIcon: Bool {
        didSet { defaults.set(showIcon, forKey: Key.showIcon) }
    }

    var warningPercent: Int {
        didSet {
            let clamped = StorageThresholds(warningPercent: warningPercent).warningPercent
            if clamped != warningPercent { warningPercent = clamped; return }
            defaults.set(warningPercent, forKey: Key.warningPercent)
        }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayFormat = defaults.string(forKey: Key.displayFormat).flatMap(DisplayFormat.init) ?? .freeGB
        refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .oneMinute
        showIcon = defaults.object(forKey: Key.showIcon) as? Bool ?? true
        warningPercent = StorageThresholds(
            warningPercent: defaults.object(forKey: Key.warningPercent) as? Int ?? 10
        ).warningPercent
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
    }

    var thresholds: StorageThresholds { StorageThresholds(warningPercent: warningPercent) }

    /// Icon shown if the user asked for it or the chosen format requires it.
    var effectiveShowIcon: Bool { showIcon || displayFormat.forcesIcon }
}
