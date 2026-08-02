import Foundation

/// Copies the keepers out of a culled folder.
///
/// Copy-only by design: originals are never moved, renamed, or deleted, and an
/// existing file at the destination is skipped rather than overwritten.
public enum ExportService {
    public static let defaultSubfolderName = "Selects"

    public struct Summary: Equatable, Sendable {
        public var copied: [String] = []
        public var skippedExisting: [String] = []
        public var failed: [Failure] = []

        public init() {}

        public var isEmpty: Bool {
            copied.isEmpty && skippedExisting.isEmpty && failed.isEmpty
        }
    }

    public struct Failure: Equatable, Sendable {
        public let filename: String
        public let reason: String
    }

    /// Copies every item whose verdict is `.pass` into `destination`, creating
    /// the destination folder if needed.
    @discardableResult
    public static func exportPasses(
        items: [PhotoItem],
        ratings: [String: Rating],
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> Summary {
        let passes = items.filter { ratings[$0.filename]?.verdict == .pass }
        guard !passes.isEmpty else { return Summary() }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        var summary = Summary()
        for item in passes {
            let target = destination.appendingPathComponent(item.filename)
            if fileManager.fileExists(atPath: target.path) {
                summary.skippedExisting.append(item.filename)
                continue
            }
            do {
                try fileManager.copyItem(at: item.url, to: target)
                summary.copied.append(item.filename)
            } catch {
                summary.failed.append(
                    Failure(filename: item.filename, reason: error.localizedDescription)
                )
            }
        }
        return summary
    }
}
