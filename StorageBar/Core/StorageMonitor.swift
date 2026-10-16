import Foundation
import Observation

@MainActor
@Observable
final class StorageMonitor {
    private(set) var snapshot: StorageSnapshot?
    private(set) var lastError: StorageError?
    private(set) var isRefreshing = false

    @ObservationIgnored private let provider: any StorageProviding
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored var onSnapshot: (@MainActor (StorageSnapshot) async -> Void)?

    init(provider: any StorageProviding) {
        self.provider = provider
    }

    /// Reads the volume once. A failure keeps the last good snapshot so the menu bar does not
    /// flicker; the error is exposed for the popup. Overlapping calls are ignored.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let latest = try await provider.snapshot()
            snapshot = latest
            lastError = nil
            await onSnapshot?(latest)
        } catch {
            lastError = (error as? StorageError) ?? .volumeInfoUnavailable
        }
    }

    /// Refreshes now, then every `interval`. Restarts any existing loop.
    /// Sleeps with 10% tolerance so the system can coalesce wakeups.
    func start(every interval: Duration) {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard self != nil else { return }
                try? await Task.sleep(for: interval, tolerance: interval / 10)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
