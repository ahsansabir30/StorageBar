import AppKit
import SwiftUI

struct PopupView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private static let storageSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.monitor.snapshot {
                details(snapshot)
            } else {
                Text(model.monitor.lastError?.localizedDescription ?? "Reading storage…")
                    .foregroundStyle(.secondary)
            }
            footer
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 280)
        .task { await model.monitor.refresh() }
    }

    private func details(_ snapshot: StorageSnapshot) -> some View {
        let level = model.preferences.thresholds.level(forAvailableFraction: snapshot.availableFraction)
        return VStack(alignment: .leading, spacing: 12) {
            Label(snapshot.volumeName, systemImage: "internaldrive")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(ByteFormatter.detailed(snapshot.availableBytes)) available")
                    .font(.title3.weight(.semibold))
                UsageBar(fraction: snapshot.usedFraction, level: level)
                Text("\(snapshot.usedPercent)% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Total", ByteFormatter.detailed(snapshot.totalBytes))
                row("Used", ByteFormatter.detailed(snapshot.usedBytes))
                row("Available", ByteFormatter.detailed(snapshot.availableBytes))
                if snapshot.purgeableBytes > 0 {
                    row("Purgeable", ByteFormatter.detailed(snapshot.purgeableBytes))
                }
            }
            .font(.callout)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).gridColumnAlignment(.trailing).monospacedDigit()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = model.monitor.lastError {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let snapshot = model.monitor.snapshot {
            Text("Updated \(snapshot.date.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            ActionButton("Refresh", systemImage: "arrow.clockwise", id: "refreshButton") {
                Task { await model.monitor.refresh() }
            }
            .disabled(model.monitor.isRefreshing)
            ActionButton("Open Storage Settings", systemImage: "gearshape", id: "storageSettingsButton") {
                NSWorkspace.shared.open(Self.storageSettingsURL)
            }
            ActionButton("Preferences…", systemImage: "slider.horizontal.3", id: "preferencesButton") {
                openWindow(id: PreferencesView.windowID)
                NSApp.activate()
            }
            ActionButton("Quit StorageBar", systemImage: "power", id: "quitButton") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let id: String
    let action: () -> Void

    init(_ title: String, systemImage: String, id: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.id = id
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .accessibilityIdentifier(id)
    }
}

struct UsageBar: View {
    let fraction: Double
    let level: StorageLevel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 4))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Storage used")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }

    private var color: Color {
        switch level {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}
