import AppKit
import SwiftUI

struct PopupView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private static let storageSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
            Divider()
            actions
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(width: 300)
        .task { await model.monitor.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.monitor.snapshot {
            StorageSummary(
                snapshot: snapshot,
                level: model.preferences.thresholds.level(forAvailableFraction: snapshot.availableFraction),
                refreshFailed: model.monitor.lastError != nil
            )
        } else if model.monitor.lastError != nil {
            VStack(alignment: .leading, spacing: 4) {
                Label("Can’t read disk capacity", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("StorageBar will try again automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading storage…").foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRow("Refresh", systemImage: "arrow.clockwise", id: "refreshButton", key: "r") {
                Task { await model.monitor.refresh() }
            }
            MenuRow("Open Storage Settings", systemImage: "gearshape", id: "storageSettingsButton") {
                NSWorkspace.shared.open(Self.storageSettingsURL)
            }
            MenuRow("Preferences…", systemImage: "slider.horizontal.3", id: "preferencesButton", key: ",") {
                openWindow(id: PreferencesView.windowID)
                NSApp.activate()
            }
            MenuRow("Quit StorageBar", systemImage: "power", id: "quitButton", key: "q") {
                NSApp.terminate(nil)
            }
        }
        // Let the hover highlight reach the popup's content margins, as in a system menu.
        .padding(.horizontal, -8)
    }
}

/// Disk name, one dominant figure, capacity bar and a single supporting line.
private struct StorageSummary: View {
    let snapshot: StorageSnapshot
    let level: StorageLevel
    let refreshFailed: Bool

    var body: some View {
        let available = ByteFormatter.parts(snapshot.availableBytes)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(snapshot.volumeName, systemImage: "internaldrive")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("Updated \(snapshot.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(available.value)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    Text(available.unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text("Available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                UsageBar(fraction: snapshot.usedFraction, level: level)
                HStack {
                    Text("\(ByteFormatter.detailed(snapshot.usedBytes)) used · \(snapshot.usedPercent)%")
                    Spacer(minLength: 8)
                    Text("\(ByteFormatter.detailed(snapshot.totalBytes)) total")
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            if let notice = levelNotice {
                StatusNote(text: notice, color: level == .critical ? .red : .orange)
            }
            if refreshFailed {
                StatusNote(text: "Couldn’t refresh. Showing the last reading.", color: .orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var levelNotice: String? {
        switch level {
        case .normal: nil
        case .warning: "Storage is running low."
        case .critical: "Storage is almost full."
        }
    }

    /// One complete sentence: everything the sighted layout shows, including state.
    private var spokenSummary: String {
        var parts = [
            "\(snapshot.volumeName), \(ByteFormatter.detailed(snapshot.availableBytes)) available",
            "\(ByteFormatter.detailed(snapshot.usedBytes)) used of \(ByteFormatter.detailed(snapshot.totalBytes)), \(snapshot.usedPercent) percent",
        ]
        if let levelNotice { parts.append(levelNotice) }
        if refreshFailed { parts.append("Couldn’t refresh, showing the last reading") }
        parts.append("Updated \(snapshot.date.formatted(date: .omitted, time: .shortened))")
        return parts.joined(separator: ". ")
    }
}

/// Symbol plus primary-colour text, so state is not conveyed by colour alone and contrast stays high.
private struct StatusNote: View {
    let text: String
    let color: Color

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color)
        }
        .font(.caption)
    }
}

/// A menu-style action row: icon, title, shortcut hint and a subtle hover highlight.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let id: String
    let key: Character?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isFocused) private var isFocused

    init(_ title: String, systemImage: String, id: String, key: Character? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.id = id
        self.key = key
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 12)
                if let key {
                    Text("⌘\(String(key).uppercased())")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering || isFocused ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .keyboardShortcut(key.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) })
        .accessibilityIdentifier(id)
    }
}

/// Thin capacity bar. Accent colour normally; orange/red once a low-storage threshold is crossed.
struct UsageBar: View {
    let fraction: Double
    let level: StorageLevel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(proxy.size.width * min(fraction, 1), 6) : 0)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch level {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}
