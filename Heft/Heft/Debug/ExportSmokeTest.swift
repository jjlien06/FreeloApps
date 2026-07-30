#if DEBUG
import Foundation
import Photos

/// Headless exercise of the export path so it can be proven to work without tapping
/// through the document picker.
///
/// Deliberately bypasses `ExportDestination`: a plain filesystem URL is not
/// security-scoped, so `startAccessingSecurityScopedResource()` would return false and
/// `withAccess` would refuse it. What this proves is the part most worth doubting —
/// `PHAssetResourceManager.writeData`, the byte-for-byte verification, the progress
/// callbacks, and the wall-clock cost.
///
/// Run with:
///   xcrun simctl launch --console booted com.jeremylien.Heft \
///       -HeftExportSmokeTest <absolute-destination-path>
enum ExportSmokeTest {
    static var requestedDestination: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-HeftExportSmokeTest"),
              flag + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[flag + 1], isDirectory: true)
    }

    static var requestedConversion: Bool {
        ProcessInfo.processInfo.arguments.contains("-HeftConvertSmokeTest")
    }

    /// Exercises the RAW→compressed pipeline: render, encode, add to library, confirm.
    /// Runs on whatever assets exist — the pipeline doesn't require RAW input, so this
    /// still proves render/encode/create/verify end to end.
    static func runConversion(limit: Int = 2) async {
        note("conversion begin limit=\(limit)")

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            note("ABORT no photo access (\(status.rawValue))")
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(with: options)
        note("library before=\(fetched.count)")

        var rawCount = 0
        var items: [AssetItem] = []
        fetched.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let isRaw = AssetSizer.isRaw(resources)
            if isRaw {
                rawCount += 1
                let utis = resources.map(\.uniformTypeIdentifier).joined(separator: ",")
                note("RAW detected \(resources.first?.originalFilename ?? "?") utis=[\(utis)]")
            }
            if items.count < limit {
                items.append(AssetItem(
                    asset: asset,
                    bytes: AssetSizer.fastSize(for: asset),
                    isRaw: isRaw
                ))
            }
        }
        note("raw assets in library=\(rawCount)")

        let clock = Date()
        let outcomes = await RawConverter.convert(items, to: .heic) { tick in
            note("CONVERT t=\(String(format: "%.2f", -clock.timeIntervalSinceNow))s "
                 + "\(tick.completed)/\(items.count) \(tick.currentLabel)")
        }
        note("conversion elapsed=\(String(format: "%.2f", -clock.timeIntervalSinceNow))s")

        for outcome in outcomes {
            note("\(outcome.succeeded ? "CONVERTED" : "FAILED   ") \(outcome.label) "
                 + "orig=\(outcome.originalBytes) new=\(outcome.newBytes) "
                 + "saved=\(outcome.saved) \(outcome.failure ?? "")")
        }

        let after = PHAsset.fetchAssets(with: options)
        note("library after=\(after.count) (expected +\(outcomes.filter { $0.succeeded }.count))")
        note("conversion end")
    }

    static func run(into destination: URL, limit: Int = 6) async {
        note("begin destination=\(destination.path) limit=\(limit)")

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        note("authorization=\(status.rawValue)")
        guard status == .authorized || status == .limited else {
            note("ABORT no photo access")
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(with: options)

        var items: [AssetItem] = []
        fetched.enumerateObjects { asset, index, stop in
            guard index < limit else {
                stop.pointee = true
                return
            }
            items.append(AssetItem(asset: asset, bytes: AssetSizer.fastSize(for: asset)))
        }
        note("library=\(fetched.count) selected=\(items.count)")

        for item in items {
            let resources = PHAssetResource.assetResources(for: item.asset)
            let detail = resources.map {
                "\($0.originalFilename) type=\($0.type.rawValue) "
                    + "reported=\(AssetSizer.reportedSize(of: $0).map(String.init) ?? "nil")"
            }
            note("asset \(item.id.prefix(12)) fastSize=\(item.bytes.map(String.init) ?? "nil") "
                 + "resources=[\(detail.joined(separator: " | "))]")
        }

        let clock = Date()
        var ticks: [String] = []

        let outcomes = await AssetExporter.export(items, into: destination) { tick in
            let elapsed = String(format: "%.2f", -clock.timeIntervalSinceNow)
            ticks.append("\(elapsed)s->\(tick.completedItems)/\(tick.bytesDone)B")
            note("PROGRESS t=\(elapsed)s items=\(tick.completedItems)/\(items.count) "
                 + "bytes=\(tick.bytesDone) frac=\(String(format: "%.3f", tick.currentFraction)) "
                 + "current=\(tick.currentLabel)")
        }

        note("elapsed=\(String(format: "%.2f", -clock.timeIntervalSinceNow))s")
        note("progress ticks: \(ticks.joined(separator: ", "))")

        for outcome in outcomes {
            note("\(outcome.succeeded ? "VERIFIED" : "FAILED  ") \(outcome.label) "
                 + "bytes=\(outcome.bytesWritten) \(outcome.failure ?? "")")
        }

        let verified = outcomes.filter { $0.succeeded }
        let verifiedBytes = verified.reduce(into: Int64(0)) { $0 += $1.bytesWritten }
        note("RESULT verified=\(verified.count)/\(outcomes.count) bytes=\(verifiedBytes)")

        let folder = destination.appendingPathComponent(AssetExporter.folderName)
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        note("on disk in \(AssetExporter.folderName): \(listing.sorted().joined(separator: ", "))")
        note("end")
    }

    /// Appends to a file rather than relying on stdout — `simctl launch --console` has to
    /// hold the process open to capture prints, which makes it useless for scripted runs.
    private static let logURL: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("smoke.log")
    }()

    private static func note(_ message: String) {
        let line = "SMOKE| \(message)\n"
        print(line, terminator: "")
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
#endif
