import Foundation

/// A point-in-time reading of the startup volume.
///
/// Definitions (all in bytes, decimal units when displayed, matching Finder):
/// - `totalBytes`: volume capacity.
/// - `freeBytes`: blocks actually free on disk (`volumeAvailableCapacity`).
/// - `availableBytes`: free space plus purgeable space the system can reclaim on demand
///   (`volumeAvailableCapacityForImportantUsage`). This matches Finder and System Settings and
///   is the headline number. Falls back to `freeBytes` when the OS does not report it.
/// - `usedBytes`: `totalBytes - availableBytes`. Computed from the single startup-volume figures,
///   so the APFS System and Data volumes sharing one container are never double-counted.
struct StorageSnapshot: Equatable, Sendable {
    let volumeName: String
    let totalBytes: Int64
    let freeBytes: Int64
    let availableForImportantUsageBytes: Int64?
    let date: Date

    var availableBytes: Int64 {
        let raw = availableForImportantUsageBytes ?? freeBytes
        return min(max(raw, 0), totalBytes)
    }

    var purgeableBytes: Int64 { max(availableBytes - max(freeBytes, 0), 0) }
    var usedBytes: Int64 { totalBytes - availableBytes }

    var availableFraction: Double {
        totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0
    }

    var usedFraction: Double {
        totalBytes > 0 ? 1 - availableFraction : 0
    }

    var availablePercent: Int { Int((availableFraction * 100).rounded()) }
    var usedPercent: Int { Int((usedFraction * 100).rounded()) }
}

enum StorageError: Error, Equatable, LocalizedError {
    case volumeInfoUnavailable

    var errorDescription: String? {
        switch self {
        case .volumeInfoUnavailable: "Storage information is unavailable."
        }
    }
}

protocol StorageProviding: Sendable {
    func snapshot() async throws -> StorageSnapshot
}

/// Reads capacity of a volume via `URLResourceValues`. No directory enumeration, no file access.
struct VolumeStorageProvider: StorageProviding {
    var volumePath: String = "/"

    func snapshot() async throws -> StorageSnapshot {
        // Fresh URL each call so the resource-value cache can never serve a stale reading.
        let url = URL(fileURLWithPath: volumePath)
        let values = try url.resourceValues(forKeys: [
            .volumeLocalizedNameKey,
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard let total = values.volumeTotalCapacity, total > 0 else {
            throw StorageError.volumeInfoUnavailable
        }
        let important = values.volumeAvailableCapacityForImportantUsage
        guard let free = values.volumeAvailableCapacity.map(Int64.init) ?? important else {
            throw StorageError.volumeInfoUnavailable
        }
        return StorageSnapshot(
            volumeName: values.volumeLocalizedName ?? values.volumeName ?? "Startup Disk",
            totalBytes: Int64(total),
            freeBytes: free,
            availableForImportantUsageBytes: important,
            date: Date()
        )
    }
}
