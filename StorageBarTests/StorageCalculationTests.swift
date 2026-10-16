import Foundation
import Testing
@testable import StorageBar

struct StorageCalculationTests {
    private func snapshot(
        total: Int64 = 500_000_000_000,
        free: Int64 = 100_000_000_000,
        important: Int64? = nil
    ) -> StorageSnapshot {
        StorageSnapshot(
            volumeName: "Macintosh HD",
            totalBytes: total,
            freeBytes: free,
            availableForImportantUsageBytes: important,
            date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func availablePrefersImportantUsageCapacity() {
        let s = snapshot(free: 100_000_000_000, important: 130_000_000_000)
        #expect(s.availableBytes == 130_000_000_000)
        #expect(s.purgeableBytes == 30_000_000_000)
    }

    @Test func availableFallsBackToFreeWhenImportantMissing() {
        let s = snapshot(free: 100_000_000_000, important: nil)
        #expect(s.availableBytes == 100_000_000_000)
        #expect(s.purgeableBytes == 0)
    }

    @Test func usedIsTotalMinusAvailable() {
        let s = snapshot(total: 500_000_000_000, free: 100_000_000_000, important: 150_000_000_000)
        #expect(s.usedBytes == 350_000_000_000)
        #expect(s.usedBytes + s.availableBytes == s.totalBytes)
    }

    @Test func percentagesAreComplementary() {
        let s = snapshot(total: 1000, free: 250, important: nil)
        #expect(s.availablePercent == 25)
        #expect(s.usedPercent == 75)
        #expect(s.availableFraction == 0.25)
        #expect(s.usedFraction == 0.75)
    }

    @Test func availableIsClampedToValidRange() {
        #expect(snapshot(total: 1000, free: 5000, important: nil).availableBytes == 1000)
        #expect(snapshot(total: 1000, free: -5, important: nil).availableBytes == 0)
    }

    @Test func zeroCapacityDoesNotDivideByZero() {
        let s = snapshot(total: 0, free: 0)
        #expect(s.availableFraction == 0)
        #expect(s.usedFraction == 0)
    }

    @Test func realVolumeReturnsPlausibleValues() async throws {
        let s = try await VolumeStorageProvider().snapshot()
        #expect(s.totalBytes > 0)
        #expect(s.availableBytes >= 0 && s.availableBytes <= s.totalBytes)
        #expect(!s.volumeName.isEmpty)
    }

    @Test func missingVolumeThrows() async {
        let provider = VolumeStorageProvider(volumePath: "/definitely/not/a/volume-\(UUID().uuidString)")
        await #expect(throws: CocoaError.self) { try await provider.snapshot() }
    }
}

struct FormattingTests {
    @Test(arguments: [
        (Int64(128_000_000_000), "128 GB"),
        (Int64(127_999_999_999), "127 GB"),
        (Int64(1_000_000_000), "1 GB"),
        (Int64(999_999_999_999), "999 GB"),
        (Int64(1_000_000_000_000), "1.0 TB"),
        (Int64(1_560_000_000_000), "1.5 TB"),
        (Int64(500_000_000), "500 MB"),
        (Int64(0), "0 MB"),
        (Int64(-10), "0 MB"),
    ])
    func compactBytes(bytes: Int64, expected: String) {
        #expect(ByteFormatter.compact(bytes) == expected)
    }

    @Test(arguments: [
        (Int64(494_000_000_000), "494", "GB"),
        (Int64(271_700_000_000), "271.7", "GB"),
        (Int64(479_180_000_000), "479.2", "GB"),
        (Int64(14_820_000_000), "14.8", "GB"),
        (Int64(1_500_000_000_000), "1.5", "TB"),
        (Int64(12_000_000), "12", "MB"),
        (Int64(-5), "0", "MB"),
        (Int64(999_960_000_000), "1", "TB"),
        (Int64(999_960_000), "1", "GB"),
    ])
    func detailedPartsUseOneConsistentPrecision(bytes: Int64, value: String, unit: String) {
        let p = ByteFormatter.parts(bytes, locale: Locale(identifier: "en_US"))
        #expect(p.value == value)
        #expect(p.unit == unit)
        #expect(ByteFormatter.detailed(bytes, locale: Locale(identifier: "en_US")) == "\(value) \(unit)")
    }

    private let sample = StorageSnapshot(
        volumeName: "Macintosh HD",
        totalBytes: 500_000_000_000,
        freeBytes: 125_000_000_000,
        availableForImportantUsageBytes: nil,
        date: .distantPast
    )

    @Test func displayFormatsRenderExpectedText() {
        #expect(DisplayFormat.freeGB.text(for: sample) == "125 GB")
        #expect(DisplayFormat.iconAndGB.text(for: sample) == "125 GB")
        #expect(DisplayFormat.freePercent.text(for: sample) == "25%")
        #expect(DisplayFormat.usedPercent.text(for: sample) == "75%")
    }

    @Test func onlyIconFormatForcesIcon() {
        #expect(DisplayFormat.allCases.filter(\.forcesIcon) == [.iconAndGB])
    }
}
