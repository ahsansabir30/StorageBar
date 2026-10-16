import Testing
@testable import StorageBar

struct ThresholdTests {
    @Test func defaultsAreTenAndFivePercent() {
        let t = StorageThresholds()
        #expect(t.warningPercent == 10)
        #expect(t.criticalPercent == 5)
    }

    @Test func warningIsClampedToSupportedRange() {
        #expect(StorageThresholds(warningPercent: 1).warningPercent == 5)
        #expect(StorageThresholds(warningPercent: 99).warningPercent == 30)
    }

    @Test(arguments: [
        (0.50, StorageLevel.normal),
        (0.10, .normal),
        (0.0999, .warning),
        (0.05, .warning),
        (0.0499, .critical),
        (0.0, .critical),
    ])
    func levelBoundaries(fraction: Double, expected: StorageLevel) {
        #expect(StorageThresholds().level(forAvailableFraction: fraction) == expected)
    }

    @Test func customThresholdMovesBothLevels() {
        let t = StorageThresholds(warningPercent: 20)
        #expect(t.criticalPercent == 10)
        #expect(t.level(forAvailableFraction: 0.15) == .warning)
        #expect(t.level(forAvailableFraction: 0.09) == .critical)
    }
}

struct AlertGateTests {
    private let t = StorageThresholds()

    @Test func notifiesOnceForTheSameState() {
        var gate = AlertGate()
        #expect(gate.levelToNotify(availableFraction: 0.09, thresholds: t) == .warning)
        #expect(gate.levelToNotify(availableFraction: 0.08, thresholds: t) == nil)
        #expect(gate.levelToNotify(availableFraction: 0.07, thresholds: t) == nil)
    }

    @Test func escalationNotifiesAgain() {
        var gate = AlertGate()
        #expect(gate.levelToNotify(availableFraction: 0.09, thresholds: t) == .warning)
        #expect(gate.levelToNotify(availableFraction: 0.04, thresholds: t) == .critical)
        #expect(gate.levelToNotify(availableFraction: 0.03, thresholds: t) == nil)
    }

    @Test func jumpingStraightToCriticalNotifiesCritical() {
        var gate = AlertGate()
        #expect(gate.levelToNotify(availableFraction: 0.01, thresholds: t) == .critical)
    }

    @Test func hoveringAtThresholdDoesNotRetrigger() {
        var gate = AlertGate()
        #expect(gate.levelToNotify(availableFraction: 0.099, thresholds: t) == .warning)
        #expect(gate.levelToNotify(availableFraction: 0.101, thresholds: t) == nil)
        #expect(gate.levelToNotify(availableFraction: 0.099, thresholds: t) == nil)
    }

    @Test func clearRecoveryRearmsTheGate() {
        var gate = AlertGate()
        #expect(gate.levelToNotify(availableFraction: 0.09, thresholds: t) == .warning)
        #expect(gate.levelToNotify(availableFraction: 0.30, thresholds: t) == nil)
        #expect(gate.levelToNotify(availableFraction: 0.09, thresholds: t) == .warning)
    }

    @Test func healthyStorageNeverNotifies() {
        var gate = AlertGate()
        #expect(gate.levelToNotify(availableFraction: 0.5, thresholds: t) == nil)
    }
}
