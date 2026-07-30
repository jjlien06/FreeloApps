import Foundation

/// One cached measurement. `modified` is the asset's modification date at the time
/// of measurement — if it moves, the entry is stale and gets re-measured.
struct CachedSize: Codable {
    let bytes: Int64
    let modified: Date?
    /// Optional so caches written before RAW detection existed still decode.
    var isRaw: Bool?
}

/// Disk-backed `localIdentifier → CachedSize` map, so relaunches don't rescan the
/// whole library. Stored as a binary plist in Application Support.
final class SizeCacheStore {
    private let url: URL

    init(filename: String = "size-index.plist") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base.appendingPathComponent(filename)
    }

    func load() -> [String: CachedSize] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? PropertyListDecoder().decode([String: CachedSize].self, from: data)) ?? [:]
    }

    func save(_ entries: [String: CachedSize]) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
