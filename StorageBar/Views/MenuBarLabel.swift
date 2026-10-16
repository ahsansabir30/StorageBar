import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            if model.preferences.effectiveShowIcon {
                Image(systemName: "internaldrive")
            }
            Text(text).monospacedDigit()
        }
        .accessibilityIdentifier("menuBarLabel")
    }

    private var text: String {
        guard let snapshot = model.monitor.snapshot else { return "-- GB" }
        return model.preferences.displayFormat.text(for: snapshot)
    }
}
