import SwiftUI

/// Compact status item: optional drive symbol plus one short value, in the system menu bar font.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        // A system Label lets the menu bar align symbol and text itself; a hand-built stack drifted.
        Group {
            if model.preferences.effectiveShowIcon {
                Label(text, systemImage: "internaldrive")
                    .labelStyle(.titleAndIcon)
            } else {
                Text(text)
            }
        }
        .monospacedDigit()
        .fixedSize()  // a status item must never truncate its value
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier("menuBarLabel")
    }

    private var text: String {
        guard let snapshot = model.monitor.snapshot else { return "-- GB" }
        return model.preferences.displayFormat.text(for: snapshot)
    }

    private var spokenLabel: String {
        guard let snapshot = model.monitor.snapshot else { return "Storage, reading" }
        switch model.preferences.displayFormat {
        case .freeGB, .iconAndGB: return "\(ByteFormatter.detailed(snapshot.availableBytes)) available"
        case .freePercent: return "\(snapshot.availablePercent) percent available"
        case .usedPercent: return "\(snapshot.usedPercent) percent used"
        }
    }
}
