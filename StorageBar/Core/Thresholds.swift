import Foundation

enum StorageLevel: Int, Comparable, Sendable {
    case normal
    case warning
    case critical

    static func < (lhs: StorageLevel, rhs: StorageLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Warning is user-configurable; critical is always half of it (default 10% / 5%).
struct StorageThresholds: Equatable, Sendable {
    static let warningRange = 5...30

    var warningPercent: Int

    init(warningPercent: Int = 10) {
        self.warningPercent = min(max(warningPercent, Self.warningRange.lowerBound), Self.warningRange.upperBound)
    }

    var criticalPercent: Int { max(warningPercent / 2, 1) }

    func level(forAvailableFraction fraction: Double) -> StorageLevel {
        let percent = fraction * 100
        if percent < Double(criticalPercent) { return .critical }
        if percent < Double(warningPercent) { return .warning }
        return .normal
    }
}

/// Decides when a notification should be sent so one low-storage state notifies once.
/// A notification fires only when the level rises above the last notified level. The level
/// resets to normal only after free space recovers one point above the warning threshold,
/// so values hovering at the threshold cannot re-trigger.
struct AlertGate: Equatable, Sendable {
    private(set) var notifiedLevel: StorageLevel = .normal

    /// Re-arms the gate once free space has clearly recovered. Safe to call while alerts are off.
    mutating func observeRecovery(availableFraction: Double, thresholds: StorageThresholds) {
        if availableFraction * 100 >= Double(thresholds.warningPercent + 1) {
            notifiedLevel = .normal
        }
    }

    mutating func levelToNotify(
        availableFraction: Double,
        thresholds: StorageThresholds
    ) -> StorageLevel? {
        observeRecovery(availableFraction: availableFraction, thresholds: thresholds)
        let level = thresholds.level(forAvailableFraction: availableFraction)
        if level == .normal { return nil }
        guard level > notifiedLevel else { return nil }
        notifiedLevel = level
        return level
    }
}

/// How the menu bar item should look for a reading. At the critical level the item turns red and
/// always shows its icon, even if the user hides it, so a nearly full disk cannot go unnoticed.
struct MenuBarStyle: Equatable, Sendable {
    let isCritical: Bool
    let showsIcon: Bool

    init(snapshot: StorageSnapshot?, thresholds: StorageThresholds, iconPreferred: Bool) {
        let level = snapshot.map { thresholds.level(forAvailableFraction: $0.availableFraction) } ?? .normal
        isCritical = level == .critical
        showsIcon = iconPreferred || isCritical
    }
}
