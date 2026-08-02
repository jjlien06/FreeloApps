import Foundation

/// Owns the `.cull.json` sidecar for one folder.
///
/// Ratings are keyed by filename so the folder can be moved or renamed without
/// losing work. Saves are atomic; a sidecar that fails to parse is moved aside
/// rather than being overwritten in place.
public final class RatingStore {
    public static let sidecarName = ".cull.json"
    public static let schemaVersion = 1

    public let folder: URL
    public private(set) var ratings: [String: Rating]
    /// Set when a corrupt sidecar was moved aside on load, so the UI can say so.
    public private(set) var recoveredFromCorruptFile: URL?

    private let fileManager: FileManager

    public var sidecarURL: URL {
        folder.appendingPathComponent(Self.sidecarName)
    }

    public init(folder: URL, fileManager: FileManager = .default) {
        self.folder = folder
        self.fileManager = fileManager
        self.ratings = [:]
        load()
    }

    // MARK: - Access

    public func rating(for filename: String) -> Rating {
        ratings[filename] ?? Rating()
    }

    /// Stores a rating, dropping the entry entirely once it carries no
    /// information so the sidecar stays a record of decisions actually made.
    public func setRating(_ rating: Rating, for filename: String) {
        if rating.isEmpty {
            ratings.removeValue(forKey: filename)
        } else {
            ratings[filename] = rating
        }
    }

    public func count(of verdict: Verdict) -> Int {
        ratings.values.count { $0.verdict == verdict }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: sidecarURL) else { return }
        do {
            ratings = try JSONDecoder().decode(Sidecar.self, from: data).ratings
        } catch {
            // Never silently discard prior work: keep the unreadable file next to
            // the photos so it can be inspected or recovered by hand.
            let backup = sidecarURL.appendingPathExtension("bak")
            try? fileManager.removeItem(at: backup)
            try? fileManager.moveItem(at: sidecarURL, to: backup)
            recoveredFromCorruptFile = fileManager.fileExists(atPath: backup.path) ? backup : nil
            ratings = [:]
        }
    }

    /// Writes the sidecar atomically. Removes it entirely when nothing is rated,
    /// so an abandoned pass leaves no litter in the folder.
    public func save() throws {
        guard !ratings.isEmpty else {
            if fileManager.fileExists(atPath: sidecarURL.path) {
                try fileManager.removeItem(at: sidecarURL)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Sidecar(version: Self.schemaVersion, ratings: ratings))
        try data.write(to: sidecarURL, options: .atomic)
    }

    private struct Sidecar: Codable {
        var version: Int
        var ratings: [String: Rating]

        init(version: Int, ratings: [String: Rating]) {
            self.version = version
            self.ratings = ratings
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            ratings = try container.decode([String: Rating].self, forKey: .ratings)
        }
    }
}
