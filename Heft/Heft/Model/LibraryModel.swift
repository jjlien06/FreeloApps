import Foundation
import Photos
import SwiftUI

@MainActor
@Observable
final class LibraryModel {
    // MARK: Published state

    private(set) var status: PHAuthorizationStatus = PhotoLibraryAuthorizer.status
    private(set) var visibleItems: [AssetItem] = []
    private(set) var isLoading = false
    private(set) var fastPassProgress: Double = 0
    private(set) var deepScanRemaining = 0
    private(set) var resolvedBytes: Int64 = 0
    private(set) var resolvedCount = 0

    private(set) var sort: SortOrder = .largestFirst
    private(set) var filter: MediaFilter = .all

    var isSelecting = false
    var selection: Set<String> = []
    var errorMessage: String?

    /// Where "Export & Delete" copies to, and whether that place is currently there.
    let destination = ExportDestination()
    private(set) var exportRun: ExportRun?
    private(set) var conversionRun: ConversionRun?

    // MARK: Private state

    private var allItems: [AssetItem] = []
    private var offsetByID: [String: Int] = [:]
    private let index = AssetSizeIndex()
    private var observer: LibraryChangeObserver?
    private var indexTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var conversionTask: Task<Void, Never>?
    private var batchesSinceResort = 0

    /// Batches arrive every 250 assets; re-sorting on each one would churn a large
    /// library. Re-sort every few batches instead, plus once when the pass ends.
    private static let resortInterval = 6

    // MARK: Derived

    var isIndexing: Bool { fastPassProgress < 1 || deepScanRemaining > 0 }

    var selectedBytes: Int64 {
        selection.reduce(into: Int64(0)) { total, id in
            guard let offset = offsetByID[id] else { return }
            total += allItems[offset].bytes ?? 0
        }
    }

    var canSortBySize: Bool { resolvedCount > 0 }

    // MARK: Lifecycle

    func start() async {
        #if DEBUG
        // Lets the harness land directly on a filtered grid, since driving the menu
        // needs taps the simulator can't be given.
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-HeftStartFilter"), flag + 1 < args.count,
           let preset = MediaFilter(rawValue: args[flag + 1]) {
            filter = preset
        }
        #endif

        if status == .notDetermined {
            status = await PhotoLibraryAuthorizer.request()
        } else {
            status = PhotoLibraryAuthorizer.status
        }
        guard status == .authorized || status == .limited else { return }

        if observer == nil {
            observer = LibraryChangeObserver { [weak self] in
                self?.scheduleRefresh()
            }
        }
        await refresh()
    }

    /// iCloud sync can fire change notifications in bursts; coalesce them so the
    /// library isn't re-fetched and re-indexed a dozen times in a row.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func setSort(_ order: SortOrder) {
        guard order != sort else { return }
        sort = order
        rebuildVisible()
    }

    func setFilter(_ media: MediaFilter) {
        guard media != filter else { return }
        filter = media
        rebuildVisible()
    }

    /// Throws away the cache and re-measures everything.
    func rescan() async {
        index.reset()
        await refresh()
    }

    // MARK: Selection

    /// Re-tests the export destination on the way in, so the Export button is present
    /// from the first frame of Select mode whenever the drive is currently attached.
    func beginSelection() {
        destination.refresh()
        isSelecting = true
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func exitSelection() {
        isSelecting = false
        selection.removeAll()
    }

    func selectAllVisible() {
        selection = Set(visibleItems.map(\.id))
    }

    // MARK: RAW conversion

    /// The RAW items inside the current selection.
    var selectedRawItems: [AssetItem] {
        selection.compactMap { offsetByID[$0] }
            .map { allItems[$0] }
            .filter(\.isRaw)
    }

    var selectedRawBytes: Int64 {
        selectedRawItems.reduce(into: Int64(0)) { $0 += $1.bytes ?? 0 }
    }

    func startRawConversion(to format: RawConverter.Format, deletingOriginals: Bool) {
        conversionTask?.cancel()
        conversionTask = Task { [weak self] in
            await self?.convertSelectedRaw(to: format, deletingOriginals: deletingOriginals)
        }
    }

    func cancelConversion() {
        conversionTask?.cancel()
        conversionRun?.wasCancelled = true
    }

    func dismissConversionSummary() {
        conversionRun = nil
    }

    /// Renders each selected RAW to `format`, adds it to the library, and — only for
    /// assets whose replacement was confirmed present — optionally deletes the original.
    private func convertSelectedRaw(
        to format: RawConverter.Format,
        deletingOriginals: Bool
    ) async {
        let items = selectedRawItems
        guard !items.isEmpty else { return }

        conversionRun = ConversionRun(
            totalItems: items.count,
            format: format,
            deletingOriginals: deletingOriginals,
            startedAt: Date()
        )

        let outcomes = await RawConverter.convert(items, to: format) { tick in
            self.conversionRun?.completed = tick.completed
            self.conversionRun?.currentLabel = tick.currentLabel
        }
        conversionRun?.outcomes = outcomes

        let cancelled = Task.isCancelled || (conversionRun?.wasCancelled ?? false)
        if cancelled { conversionRun?.wasCancelled = true }

        // Converted-and-confirmed only. A RAW whose replacement didn't land keeps living.
        let replaced = outcomes.filter(\.succeeded).map(\.asset)

        guard deletingOriginals, !cancelled, !replaced.isEmpty else {
            conversionRun?.phase = .finished
            return
        }

        conversionRun?.phase = .deleting
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(replaced as NSArray)
            }
            conversionRun?.deletedCount = replaced.count
            let removed = Set(replaced.map(\.localIdentifier))
            selection = selection.filter { !removed.contains($0) }
            if selection.isEmpty { isSelecting = false }
        } catch {
            let userCancelled = (error as NSError).code
                == PHPhotosError.Code.userCancelled.rawValue
            conversionRun?.deleteError = userCancelled
                ? "Kept the RAW files — the converted copies are in your library too."
                : error.localizedDescription
        }

        conversionRun?.phase = .finished
    }

    // MARK: Export

    /// Kicks off an export in a task we can cancel. A single iCloud-resident 4K video can
    /// take minutes to fetch, and there has to be a way out of that screen.
    func startExportThenDelete() {
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            await self?.exportThenDeleteSelected()
        }
    }

    /// Takes effect between files — `PHAssetResourceManager.writeData` exposes no cancel,
    /// so an in-flight download has to finish before the loop notices.
    func cancelExport() {
        exportTask?.cancel()
        exportRun?.wasCancelled = true
    }

    /// Copies every selected asset out to the export destination, then deletes only
    /// the ones that were verified byte-for-byte. Anything that failed to export is
    /// kept, deliberately — a failed backup must never cost you the original.
    func exportThenDeleteSelected() async {
        let items = selection.compactMap { offsetByID[$0] }.map { allItems[$0] }
        guard !items.isEmpty else { return }
        guard destination.isUsable else {
            errorMessage = "The export destination isn't available. Reconnect the drive "
                + "or choose a new folder."
            return
        }

        let known = items.reduce(into: Int64(0)) { $0 += $1.bytes ?? 0 }
        exportRun = ExportRun(
            totalItems: items.count,
            totalBytes: known,
            startedAt: Date()
        )

        let outcomes = await destination.withAccess { folder in
            await AssetExporter.export(items, into: folder) { tick in
                self.exportRun?.apply(tick)
            }
        }

        guard let outcomes else {
            destination.refresh()
            exportRun = nil
            errorMessage = "Lost access to the export folder. Is the drive still connected?"
            return
        }

        exportRun?.outcomes = outcomes

        // Cancelled means stop, not "delete what you managed to copy".
        if Task.isCancelled || (exportRun?.wasCancelled ?? false) {
            exportRun?.wasCancelled = true
            exportRun?.phase = .finished
            return
        }

        let verified = outcomes.filter(\.succeeded)

        guard !verified.isEmpty else {
            exportRun?.phase = .finished
            return
        }

        exportRun?.phase = .deleting
        do {
            let doomed = verified.map(\.asset)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(doomed as NSArray)
            }
            exportRun?.deletedCount = doomed.count
            selection = selection.filter { id in !verified.contains { $0.id == id } }
            if selection.isEmpty { isSelecting = false }
        } catch {
            let cancelled = (error as NSError).code == PHPhotosError.Code.userCancelled.rawValue
            // The copies are already on disk either way, so this is only about deletion.
            exportRun?.deleteError = cancelled
                ? "Deletion cancelled — your exported copies were kept."
                : error.localizedDescription
        }

        exportRun?.phase = .finished
    }

    func dismissExportSummary() {
        exportRun = nil
    }

    func deleteSelected() async {
        let doomed = selection.compactMap { offsetByID[$0] }.map { allItems[$0].asset }
        guard !doomed.isEmpty else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(doomed as NSArray)
            }
            selection.removeAll()
            isSelecting = false
            // The change observer picks it up from here and triggers a refresh.
        } catch {
            // Declining the system confirmation sheet surfaces as an error too —
            // that's a normal outcome, not something worth alerting about.
            let cancelled = (error as NSError).code == PHPhotosError.Code.userCancelled.rawValue
            if !cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Loading

    private func refresh() async {
        indexTask?.cancel()
        isLoading = allItems.isEmpty

        let assets = await fetchAssets()
        allItems = assets.map {
            AssetItem(
                asset: $0,
                bytes: index.cachedSize(for: $0),
                isRaw: index.cachedIsRaw(for: $0) ?? false
            )
        }
        offsetByID = Dictionary(
            uniqueKeysWithValues: allItems.enumerated().map { ($0.element.id, $0.offset) }
        )

        // Drop selections pointing at assets that no longer exist.
        selection = selection.filter { offsetByID[$0] != nil }
        if selection.isEmpty { isSelecting = false }

        recomputeTotals()
        rebuildVisible()
        isLoading = false
        startIndexing()
    }

    private func fetchAssets() async -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.includeHiddenAssets = false

            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in assets.append(asset) }
            return assets
        }.value
    }

    private func startIndexing() {
        fastPassProgress = 0
        deepScanRemaining = 0
        batchesSinceResort = 0

        let snapshot = allItems
        indexTask = Task { [weak self] in
            guard let self else { return }
            await self.index.build(for: snapshot) { update in
                self.apply(update)
            }
            guard !Task.isCancelled else { return }
            self.rebuildVisible()
            self.index.prune(keeping: Set(self.allItems.map(\.id)))
        }
    }

    private func apply(_ update: AssetSizeIndex.Update) {
        fastPassProgress = update.fastPassProgress
        deepScanRemaining = update.deepScanRemaining

        guard !update.sizes.isEmpty || !update.rawIds.isEmpty else { return }

        for id in update.rawIds {
            guard let offset = offsetByID[id] else { continue }
            allItems[offset].isRaw = true
        }

        for (id, bytes) in update.sizes {
            guard let offset = offsetByID[id] else { continue }
            if let previous = allItems[offset].bytes {
                resolvedBytes += bytes - previous
            } else {
                resolvedBytes += bytes
                resolvedCount += 1
            }
            allItems[offset].bytes = bytes
        }

        batchesSinceResort += 1
        if batchesSinceResort >= Self.resortInterval || update.fastPassProgress >= 1 {
            batchesSinceResort = 0
            rebuildVisible()
        }
    }

    private func recomputeTotals() {
        resolvedBytes = 0
        resolvedCount = 0
        for item in allItems {
            guard let bytes = item.bytes else { continue }
            resolvedBytes += bytes
            resolvedCount += 1
        }
    }

    private func rebuildVisible() {
        let filtered = filter == .all ? allItems : allItems.filter { filter.matches($0) }
        visibleItems = AssetSorting.sort(filtered, by: sort)
    }
}
