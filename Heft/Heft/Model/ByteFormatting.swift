import Foundation

/// Byte-count rendering. Pure and dependency-free.
enum ByteFormatting {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Short form for grid badges: "812 KB", "1.4 GB", "23 MB".
    /// Decimal (1000-based) units, matching Finder and iOS Settings.
    static func compact(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) B" }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unit])
    }

    /// Em dash for assets whose size never resolved.
    static func compactOrDash(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return compact(bytes)
    }

    /// "3:07" / "1:02:44" for video durations.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
