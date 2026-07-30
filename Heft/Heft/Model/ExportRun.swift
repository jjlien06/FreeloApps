import Foundation

/// One tick of export progress. Byte-weighted, because item-count progress sits at zero
/// for minutes when the first selected thing is a 4K video.
struct ExportTick {
    var completedItems: Int
    var bytesDone: Int64
    var currentLabel: String
    /// 0…1 through the item currently being written.
    var currentFraction: Double
}

/// Live state of one export-then-delete pass, drives the progress sheet.
struct ExportRun {
    enum Phase {
        case copying
        case deleting
        case finished
    }

    let totalItems: Int
    /// Sum of the sizes we already measured for the selection. Zero when unknown, in
    /// which case progress falls back to item counting.
    let totalBytes: Int64
    let startedAt: Date

    var completedItems = 0
    var bytesDone: Int64 = 0
    var currentLabel = ""
    var currentFraction: Double = 0
    var phase: Phase = .copying
    var outcomes: [ExportOutcome] = []
    var deletedCount = 0
    var deleteError: String?
    /// Set when the user backs out. Cancelling skips deletion entirely — copies already
    /// on the drive are harmless, but nothing gets removed from the library.
    var wasCancelled = false

    init(totalItems: Int, totalBytes: Int64, startedAt: Date) {
        self.totalItems = totalItems
        self.totalBytes = totalBytes
        self.startedAt = startedAt
    }

    mutating func apply(_ tick: ExportTick) {
        completedItems = tick.completedItems
        bytesDone = tick.bytesDone
        currentLabel = tick.currentLabel
        currentFraction = tick.currentFraction
    }

    /// Includes partial progress through the in-flight item so the bar keeps creeping
    /// during a single large file.
    var fraction: Double {
        guard totalBytes > 0 else {
            guard totalItems > 0 else { return 1 }
            let base = Double(completedItems) + currentFraction
            return min(base / Double(totalItems), 1)
        }
        return min(Double(bytesDone) / Double(totalBytes), 1)
    }

    var exported: [ExportOutcome] { outcomes.filter(\.succeeded) }
    var failed: [ExportOutcome] { outcomes.filter { !$0.succeeded } }

    var bytesExported: Int64 {
        exported.reduce(into: Int64(0)) { $0 += $1.bytesWritten }
    }

    var isFinished: Bool { phase == .finished }

    /// Throughput estimate, nil until there's enough signal to be meaningful.
    func bytesPerSecond(asOf now: Date) -> Double? {
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 1.5, bytesDone > 0 else { return nil }
        return Double(bytesDone) / elapsed
    }

    func estimatedRemaining(asOf now: Date) -> TimeInterval? {
        guard totalBytes > 0, let rate = bytesPerSecond(asOf: now), rate > 0 else { return nil }
        let left = Double(totalBytes - bytesDone)
        guard left > 0 else { return nil }
        return left / rate
    }
}
