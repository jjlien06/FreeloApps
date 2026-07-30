import Foundation

/// Persistent append-only text buffer: every capture is added, the whole
/// buffer can be copied at once, and it survives restarts. Plain UTF-8 file
/// so the data stays user-inspectable.
public struct HistoryStore {
    public let fileURL: URL

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("history.txt")
    }

    public func append(_ text: String) throws {
        var buffer = loadAll()
        if !buffer.isEmpty { buffer += "\n\n" }
        buffer += text
        try buffer.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func loadAll() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public var isEmpty: Bool { loadAll().isEmpty }
}
