import Foundation
import Photos

struct ExportOutcome: Identifiable {
    let asset: PHAsset
    let label: String
    let bytesWritten: Int64
    let writtenFiles: [URL]
    /// nil means verified-good. Anything else and the asset is NOT eligible for deletion.
    let failure: String?

    var id: String { asset.localIdentifier }
    var succeeded: Bool { failure == nil }
}

/// Copies originals out to a folder the user picked, then reports exactly which
/// assets are provably safe to delete.
///
/// The contract that makes "export then delete" safe: an asset is only reported as
/// succeeded when every one of its resources was written AND the bytes on disk match
/// what PhotoKit said to expect. A partial or unverifiable write is a failure, and
/// failures are never deleted.
enum AssetExporter {
    /// Exports land in a subfolder so picking a drive root doesn't scatter files.
    static let folderName = "Heft Export"

    static func export(
        _ items: [AssetItem],
        into destination: URL,
        onTick: @MainActor @escaping (ExportTick) -> Void
    ) async -> [ExportOutcome] {
        let folder = destination.appendingPathComponent(folderName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            let reason = "Couldn't create \(folderName): \(error.localizedDescription)"
            return items.map {
                ExportOutcome(
                    asset: $0.asset,
                    label: label(for: $0),
                    bytesWritten: 0,
                    writtenFiles: [],
                    failure: reason
                )
            }
        }

        let names = NameAllocator(existingIn: folder)
        var outcomes: [ExportOutcome] = []
        var bytesDone: Int64 = 0

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }

            // Fetch the resource list ONCE and thread it through. Querying it again
            // inside exportOne let the caption name a different snapshot than the files
            // actually written, if the library changed mid-run.
            let resources = PHAssetResource.assetResources(for: item.asset)
            let name = resources.first?.originalFilename
                ?? (item.isVideo ? "Video" : "Photo")

            // Announce the item BEFORE work starts so the sheet names the current file
            // immediately, but report `index` as *completed* — which it is, since index
            // items are behind us.
            let settled = bytesDone
            await onTick(ExportTick(
                completedItems: index,
                bytesDone: settled,
                currentLabel: name,
                currentFraction: 0
            ))

            let outcome = await exportOne(
                item,
                label: name,
                resources: resources,
                into: folder,
                names: names
            ) { fraction, partialBytes in
                // Sub-file progress, so a single huge video still moves the bar.
                await onTick(ExportTick(
                    completedItems: index,
                    bytesDone: settled + partialBytes,
                    currentLabel: name,
                    currentFraction: fraction
                ))
            }

            outcomes.append(outcome)
            // Credit the expected size even on failure, else the bar stalls short of the
            // end whenever something couldn't be copied.
            bytesDone += outcome.succeeded
                ? outcome.bytesWritten
                : (item.bytes ?? 0)

            await onTick(ExportTick(
                completedItems: index + 1,
                bytesDone: bytesDone,
                currentLabel: name,
                currentFraction: 0
            ))
        }

        return outcomes
    }

    // MARK: - One asset

    private static func exportOne(
        _ item: AssetItem,
        label: String,
        resources: [PHAssetResource],
        into folder: URL,
        names: NameAllocator,
        onPartial: @escaping (Double, Int64) async -> Void
    ) async -> ExportOutcome {
        guard !resources.isEmpty else {
            return ExportOutcome(
                asset: item.asset,
                label: label,
                bytesWritten: 0,
                writtenFiles: [],
                failure: "No exportable file behind this asset."
            )
        }

        // Expected sizes let sub-file progress be weighted properly across a Live
        // Photo's still + video pair.
        let expectations = resources.map { AssetSizer.reportedSize(of: $0) ?? 0 }
        let expectedTotal = expectations.reduce(0, +)

        var written: [URL] = []
        var confirmedBytes: Int64 = 0

        func fail(_ reason: String, cleaning extra: [URL] = []) -> ExportOutcome {
            cleanUp(written + extra)
            return ExportOutcome(
                asset: item.asset,
                label: label,
                bytesWritten: 0,
                writtenFiles: [],
                failure: reason
            )
        }

        for (offset, resource) in resources.enumerated() {
            let target = folder.appendingPathComponent(
                names.claim(prefix: datePrefix(item), original: resource.originalFilename)
            )

            // writeData refuses to overwrite, so clear any stale file at the path.
            try? FileManager.default.removeItem(at: target)

            let priorBytes = confirmedBytes
            let thisExpected = expectations[offset]

            let problem = await write(resource, to: target) { fraction in
                let within = Int64(Double(thisExpected) * fraction)
                let itemFraction = expectedTotal > 0
                    ? Double(priorBytes + within) / Double(expectedTotal)
                    : 0
                await onPartial(min(itemFraction, 1), priorBytes + within)
            }

            if let problem {
                return fail(problem)
            }

            // Verify on disk. An asset that can't be proven intact must not be deleted.
            guard let actual = fileSize(at: target), actual > 0 else {
                return fail(
                    "Wrote \(resource.originalFilename) but it landed empty.",
                    cleaning: [target]
                )
            }

            // Two tiers, because "no expected size" must never mean "verified".
            //
            // `thisExpected == 0` means PhotoKit withheld `fileSize` — common for
            // iCloud-optimized originals, i.e. precisely the files just pulled over the
            // network and most exposed to a partial write. Passing those on `actual > 0`
            // alone would accept a 40-byte truncation of a 4 GB video and then delete
            // the original. So they get parsed instead.
            if thisExpected > 0 {
                if thisExpected != actual {
                    return fail(
                        "Size mismatch on \(resource.originalFilename): "
                            + "expected \(thisExpected) bytes, wrote \(actual).",
                        cleaning: [target]
                    )
                }
            } else {
                let treatAsVideo = FileIntegrity.isVideoResource(resource)
                if case let .damaged(reason) = await FileIntegrity.verify(
                    target,
                    isVideo: treatAsVideo
                ) {
                    return fail(
                        "Couldn't confirm \(resource.originalFilename): \(reason). "
                            + "PhotoKit reported no expected size, so it was checked by "
                            + "decoding — and the copy didn't hold up.",
                        cleaning: [target]
                    )
                }
            }

            written.append(target)
            confirmedBytes += actual
        }

        return ExportOutcome(
            asset: item.asset,
            label: label,
            bytesWritten: confirmedBytes,
            writtenFiles: written,
            failure: nil
        )
    }

    /// Returns a description of what went wrong, or nil on success.
    private static func write(
        _ resource: PHAssetResource,
        to url: URL,
        onFraction: @escaping (Double) async -> Void
    ) async -> String? {
        let options = PHAssetResourceRequestOptions()
        // Unlike measurement, export MUST be allowed to pull iCloud originals —
        // otherwise we'd hand back a success for a file we never actually copied.
        options.isNetworkAccessAllowed = true
        // Without this the UI has no signal at all while a large or cloud-resident
        // file is fetched, which reads as a frozen progress bar.
        options.progressHandler = { fraction in
            Task { await onFraction(fraction) }
        }

        return await withCheckedContinuation { continuation in
            var finished = false
            let lock = NSLock()

            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: error?.localizedDescription)
            }
        }
    }

    private static func cleanUp(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private static func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    // MARK: - Naming

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func datePrefix(_ item: AssetItem) -> String {
        guard let date = item.creationDate else { return "undated" }
        return stamp.string(from: date)
    }

    private static func label(for item: AssetItem) -> String {
        PHAssetResource.assetResources(for: item.asset).first?.originalFilename
            ?? (item.isVideo ? "Video" : "Photo")
    }
}

/// Hands out collision-free filenames. Two different assets can easily share an
/// `originalFilename` (every camera roll has several IMG_0001.JPG), and a folder may
/// already hold files from a previous export.
private final class NameAllocator {
    private var taken: Set<String>

    init(existingIn folder: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        taken = Set(contents.map { $0.lowercased() })
    }

    func claim(prefix: String, original: String) -> String {
        let ext = (original as NSString).pathExtension
        let base = (original as NSString).deletingPathExtension
        let stem = "\(prefix)_\(base)"

        var candidate = ext.isEmpty ? stem : "\(stem).\(ext)"
        var counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            counter += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }
}
