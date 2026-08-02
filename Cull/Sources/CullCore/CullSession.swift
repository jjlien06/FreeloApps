import Foundation
import Observation

/// The state of one culling pass over one folder.
///
/// Lives in the core rather than the app target because it holds no view code:
/// it is the cull workflow expressed as state transitions, which is where the
/// behaviour worth testing lives.
@MainActor
@Observable
public final class CullSession {
    public enum Filter: CaseIterable, Sendable {
        case all, passes, fails, unrated, threeStarsPlus

        public var label: String {
            switch self {
            case .all: "All"
            case .passes: "Passes"
            case .fails: "Fails"
            case .unrated: "Unrated"
            case .threeStarsPlus: "3★ and up"
            }
        }

        public func matches(_ rating: Rating) -> Bool {
            switch self {
            case .all: true
            case .passes: rating.verdict == .pass
            case .fails: rating.verdict == .fail
            case .unrated: rating.verdict == nil
            case .threeStarsPlus: rating.stars >= 3
            }
        }

        public var next: Filter {
            let all = Filter.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    public enum ViewMode: Sendable { case loupe, grid }

    public private(set) var folder: URL?
    public private(set) var allItems: [PhotoItem] = []
    public private(set) var ratings: [String: Rating] = [:]
    public private(set) var loadError: String?
    /// Surfaced once after a damaged sidecar was moved aside on open.
    public var recoveryNotice: String?

    public var filter: Filter = .all { didSet { clampCursor() } }
    public var cursor = 0
    public var viewMode: ViewMode = .loupe
    public var autoAdvance = true
    public var isZoomed = false

    private var store: RatingStore?
    private var saveTask: Task<Void, Never>?

    public init() {}

    // MARK: - Derived state

    /// The items the filter currently admits, in scan order.
    public var items: [PhotoItem] {
        guard filter != .all else { return allItems }
        return allItems.filter { filter.matches(rating(for: $0.filename)) }
    }

    public var current: PhotoItem? {
        let visible = items
        guard visible.indices.contains(cursor) else { return nil }
        return visible[cursor]
    }

    public var currentRating: Rating {
        current.map { rating(for: $0.filename) } ?? Rating()
    }

    public var passCount: Int { ratings.values.count { $0.verdict == .pass } }
    public var failCount: Int { ratings.values.count { $0.verdict == .fail } }
    public var unratedCount: Int { allItems.count - passCount - failCount }

    public var folderName: String { folder?.lastPathComponent ?? "No folder" }

    public func rating(for filename: String) -> Rating {
        ratings[filename] ?? Rating()
    }

    // MARK: - Opening

    public func open(folder url: URL) {
        flushSave()

        folder = url
        loadError = nil
        recoveryNotice = nil
        cursor = 0

        let store = RatingStore(folder: url)
        self.store = store
        ratings = store.ratings
        if let backup = store.recoveredFromCorruptFile {
            recoveryNotice = "The existing ratings file could not be read. It was kept as \(backup.lastPathComponent) and a new one started."
        }

        do {
            allItems = try FolderScanner.scan(folder: url)
            if allItems.isEmpty {
                loadError = "No images in this folder."
            }
        } catch {
            allItems = []
            loadError = "Could not read that folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Navigation

    public func next() { move(by: 1) }
    public func previous() { move(by: -1) }

    private func move(by delta: Int) {
        let count = items.count
        guard count > 0 else { cursor = 0; return }
        cursor = min(max(cursor + delta, 0), count - 1)
        // Zoom is per-photo: staying zoomed while flicking through frames means
        // every advance stalls on a 6000px decode.
        isZoomed = false
    }

    public func select(_ item: PhotoItem) {
        if let index = items.firstIndex(of: item) { cursor = index }
    }

    private func clampCursor() {
        let count = items.count
        cursor = count == 0 ? 0 : min(cursor, count - 1)
    }

    // MARK: - Rating

    public func setVerdict(_ verdict: Verdict?) {
        mutateCurrent(advancing: true) { $0.verdict = verdict }
    }

    public func setStars(_ stars: Int) {
        // Deliberately does not advance: stars are often set before the verdict.
        mutateCurrent(advancing: false) { $0.stars = Rating.clamp(stars) }
    }

    public func setNote(_ note: String) {
        mutateCurrent(advancing: false) { $0.note = note.isEmpty ? nil : note }
    }

    private func mutateCurrent(advancing: Bool, _ change: (inout Rating) -> Void) {
        guard let item = current else { return }
        let visibleCountBefore = items.count

        var rating = self.rating(for: item.filename)
        change(&rating)
        store?.setRating(rating, for: item.filename)
        ratings = store?.ratings ?? [:]

        // Under a filter, rating a photo can remove it from view — in which case
        // the cursor already points at the next photo and must not move again.
        let stillVisible = items.count == visibleCountBefore
        if advancing && autoAdvance && stillVisible {
            move(by: 1)
        } else {
            clampCursor()
        }

        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.writeSidecar()
        }
    }

    /// Writes immediately — used when closing the folder or quitting, where a
    /// pending debounce would otherwise lose the last few decisions.
    public func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        writeSidecar()
    }

    private func writeSidecar() {
        do {
            try store?.save()
        } catch {
            loadError = "Could not save ratings: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    public func exportPasses() throws -> ExportService.Summary {
        guard let folder else { return ExportService.Summary() }
        flushSave()
        return try ExportService.exportPasses(
            items: allItems,
            ratings: ratings,
            to: folder.appendingPathComponent(ExportService.defaultSubfolderName, isDirectory: true)
        )
    }
}
