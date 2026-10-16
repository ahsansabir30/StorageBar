import Foundation

enum ByteFormatter {
    /// Compact decimal size for the menu bar: "128 GB", "1.5 TB", "500 MB".
    /// Rounds down so free space is never overstated.
    static func compact(_ bytes: Int64) -> String {
        let value = Double(max(bytes, 0))
        let gb = value / 1e9
        if gb >= 1000 {
            let tb = (gb / 1000 * 10).rounded(.down) / 10
            return "\(tb.formatted(.number.precision(.fractionLength(1)))) TB"
        }
        if gb >= 1 { return "\(Int(gb.rounded(.down))) GB" }
        return "\(Int((value / 1e6).rounded(.down))) MB"
    }

    /// Finder-style size for the popup (decimal units, locale aware).
    static func detailed(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

enum DisplayFormat: String, CaseIterable, Identifiable, Sendable {
    case freeGB
    case freePercent
    case usedPercent
    case iconAndGB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeGB: "Free storage (GB)"
        case .freePercent: "Free storage (%)"
        case .usedPercent: "Used storage (%)"
        case .iconAndGB: "Icon and free GB"
        }
    }

    /// Whether this format always shows the drive icon regardless of the "Show icon" preference.
    var forcesIcon: Bool { self == .iconAndGB }

    func text(for snapshot: StorageSnapshot) -> String {
        switch self {
        case .freeGB, .iconAndGB: ByteFormatter.compact(snapshot.availableBytes)
        case .freePercent: "\(snapshot.availablePercent)%"
        case .usedPercent: "\(snapshot.usedPercent)%"
        }
    }
}
