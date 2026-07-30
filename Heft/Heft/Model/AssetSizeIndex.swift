import Foundation
import Photos

/// Builds and caches the size map for the library.
///
/// Work is staged so the grid is never blocked: a cache sweep answers instantly on
/// relaunch, a fast pass resolves nearly everything else, and a slow streaming pass
/// mops up the remainder in the background. Results are handed back in batches as
/// they land rather than all at the end.
@MainActor
final class AssetSizeIndex {
    private let store: SizeCacheStore
    private var entries: [String: CachedSize]

    init(store: SizeCacheStore = SizeCacheStore()) {
        self.store = store
        self.entries = store.load()
    }

    /// Batch of newly resolved sizes plus where the fast pass stands.
    struct Update {
        var sizes: [String: Int64]
        /// Assets confirmed to be camera RAW in this batch.
        var rawIds: Set<String> = []
        var fastPassProgress: Double
        var deepScanRemaining: Int
    }

    /// Size and RAW-ness travel together — both come from one resource enumeration.
    private struct Measurement: Sendable {
        let bytes: Int64?
        let isRaw: Bool
    }

    private func freshEntry(for asset: PHAsset) -> CachedSize? {
        guard let entry = entries[asset.localIdentifier], isFresh(entry, for: asset) else {
            return nil
        }
        return entry
    }

    func cachedSize(for asset: PHAsset) -> Int64? {
        freshEntry(for: asset)?.bytes
    }

    func cachedIsRaw(for asset: PHAsset) -> Bool? {
        freshEntry(for: asset)?.isRaw
    }

    func reset() {
        entries.removeAll()
        store.clear()
    }

    /// Resolves sizes for `items`, reporting progress through `onUpdate`.
    /// Honours task cancellation between chunks.
    func build(for items: [AssetItem], onUpdate: @MainActor (Update) -> Void) async {
        guard !items.isEmpty else {
            onUpdate(Update(sizes: [:], fastPassProgress: 1, deepScanRemaining: 0))
            return
        }

        // Cache sweep — dictionary reads only, no PhotoKit traffic.
        var cacheHits: [String: Int64] = [:]
        var cachedRaw: Set<String> = []
        var pending: [AssetItem] = []
        for item in items {
            // `isRaw == nil` means this entry was written before RAW detection existed.
            // Treating it as a hit would skip the fast pass and leave RAW permanently
            // undetected for every already-measured asset, so re-measure it once.
            guard let entry = freshEntry(for: item.asset), entry.isRaw != nil else {
                pending.append(item)
                continue
            }
            cacheHits[item.id] = entry.bytes
            if entry.isRaw == true { cachedRaw.insert(item.id) }
        }

        let total = Double(items.count)
        var settled = Double(cacheHits.count)

        onUpdate(Update(
            sizes: cacheHits,
            rawIds: cachedRaw,
            fastPassProgress: settled / total,
            deepScanRemaining: 0
        ))

        // Fast pass — undocumented `fileSize` key, chunked so the UI stays responsive.
        var needsDeepScan: [AssetItem] = []
        for chunk in pending.chunked(into: 250) {
            if Task.isCancelled { return }

            let measured = await Task.detached(priority: .utility) {
                chunk.map { item -> Measurement in
                    // One resource enumeration answers both questions.
                    let resources = PHAssetResource.assetResources(for: item.asset)
                    var total: Int64 = 0
                    var resolvedAny = false
                    for resource in resources {
                        guard let bytes = AssetSizer.reportedSize(of: resource) else { continue }
                        total += bytes
                        resolvedAny = true
                    }
                    let isRaw = AssetSizer.isRaw(resources)
                    #if DEBUG
                    // Kept deliberately: fires only for RAW-ish assets, so it's quiet, and
                    // it's the only way to tell whether a real camera's ProRAW/CR3/NEF is
                    // being typed as `public.camera-raw-image` on actual hardware.
                    let utis = resources.map(\.uniformTypeIdentifier).joined(separator: ",")
                    if isRaw || utis.lowercased().contains("raw") {
                        NSLog("HEFT| raw %@ utis=%@ detected=%d",
                              resources.first?.originalFilename ?? "?", utis, isRaw ? 1 : 0)
                    }
                    #endif
                    return Measurement(
                        bytes: resolvedAny ? total : nil,
                        isRaw: isRaw
                    )
                }
            }.value

            var batch: [String: Int64] = [:]
            var rawBatch: Set<String> = []
            for (item, measurement) in zip(chunk, measured) {
                settled += 1
                if measurement.isRaw { rawBatch.insert(item.id) }
                guard let bytes = measurement.bytes else {
                    needsDeepScan.append(item)
                    continue
                }
                batch[item.id] = bytes
                entries[item.id] = CachedSize(
                    bytes: bytes,
                    modified: item.asset.modificationDate,
                    isRaw: measurement.isRaw
                )
            }

            onUpdate(Update(
                sizes: batch,
                rawIds: rawBatch,
                fastPassProgress: min(settled / total, 1),
                deepScanRemaining: needsDeepScan.count
            ))
        }

        persist()

        // Deep pass — stream byte counts for whatever the fast pass could not answer.
        var remaining = needsDeepScan.count
        for item in needsDeepScan {
            if Task.isCancelled { break }

            let bytes = await AssetSizer.streamedSize(for: item.asset)
            remaining -= 1

            var batch: [String: Int64] = [:]
            let isRaw = AssetSizer.isRaw(for: item.asset)
            if let bytes {
                batch[item.id] = bytes
                entries[item.id] = CachedSize(
                    bytes: bytes,
                    modified: item.asset.modificationDate,
                    isRaw: isRaw
                )
            }

            onUpdate(Update(
                sizes: batch,
                rawIds: isRaw ? [item.id] : [],
                fastPassProgress: 1,
                deepScanRemaining: remaining
            ))
        }

        persist()
    }

    /// Drops entries for assets that no longer exist, so the cache can't grow forever.
    func prune(keeping ids: Set<String>) {
        guard entries.count > ids.count else { return }
        entries = entries.filter { ids.contains($0.key) }
        persist()
    }

    private func persist() {
        let snapshot = entries
        Task.detached(priority: .background) { [store] in
            store.save(snapshot)
        }
    }

    /// PhotoKit dates round-trip through a plist, so compare with a small tolerance
    /// rather than exact equality.
    private func isFresh(_ entry: CachedSize, for asset: PHAsset) -> Bool {
        switch (entry.modified, asset.modificationDate) {
        case (nil, nil):
            true
        case let (cached?, current?):
            abs(cached.timeIntervalSince(current)) < 1
        default:
            false
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
