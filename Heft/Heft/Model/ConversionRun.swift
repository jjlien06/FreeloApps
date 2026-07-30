import Foundation

/// Live state of one RAW→compressed conversion pass.
struct ConversionRun {
    enum Phase {
        case converting
        case deleting
        case finished
    }

    let totalItems: Int
    let format: RawConverter.Format
    let deletingOriginals: Bool
    let startedAt: Date

    var completed = 0
    var currentLabel = ""
    var phase: Phase = .converting
    var outcomes: [ConversionOutcome] = []
    var deletedCount = 0
    var deleteError: String?
    var wasCancelled = false

    init(
        totalItems: Int,
        format: RawConverter.Format,
        deletingOriginals: Bool,
        startedAt: Date
    ) {
        self.totalItems = totalItems
        self.format = format
        self.deletingOriginals = deletingOriginals
        self.startedAt = startedAt
    }

    var fraction: Double {
        guard totalItems > 0 else { return 1 }
        return min(Double(completed) / Double(totalItems), 1)
    }

    var converted: [ConversionOutcome] { outcomes.filter(\.succeeded) }
    var failed: [ConversionOutcome] { outcomes.filter { !$0.succeeded } }

    var originalBytes: Int64 {
        converted.reduce(into: Int64(0)) { $0 += $1.originalBytes }
    }

    var newBytes: Int64 {
        converted.reduce(into: Int64(0)) { $0 += $1.newBytes }
    }

    /// Only meaningful when originals were removed — otherwise both copies still exist.
    var reclaimed: Int64 { max(originalBytes - newBytes, 0) }

    var isFinished: Bool { phase == .finished }
}
