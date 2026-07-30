import Foundation
import Photos
import UniformTypeIdentifiers

/// Resolves the on-disk footprint of a `PHAsset`.
///
/// PhotoKit exposes no public file-size API, so this works in two tiers:
///
///  1. `fastSize` reads the undocumented `fileSize` key off each `PHAssetResource`
///     via KVC. It costs nothing and covers the large majority of a library.
///  2. `streamedSize` falls back to counting bytes as `PHAssetResourceManager`
///     streams the resource. Accurate and fully public, but it has to touch the
///     file, so it is reserved for assets tier one could not answer.
///
/// Both tiers sum *every* resource attached to the asset — for a Live Photo that
/// is the still plus the paired video; for an edited photo it is the original plus
/// the rendered version. That sum is what deleting the asset actually reclaims.
///
/// Tier one relies on a private key and would be a rejection risk on the App Store.
/// It is safe for personal / sideloaded builds.
enum AssetSizer {
    private static let fileSizeKey = "fileSize"

    /// A single resource's own reported byte count, when PhotoKit surfaces it.
    /// Also used by the exporter to verify what it wrote.
    static func reportedSize(of resource: PHAssetResource) -> Int64? {
        (resource.value(forKey: fileSizeKey) as? NSNumber)?.int64Value
    }

    /// Whether any resource is camera RAW. Apple ProRAW (DNG) conforms to
    /// `public.camera-raw-image` too, so one check covers both.
    ///
    /// Detected from a resource list the caller already has — the size passes walk every
    /// asset's resources anyway, so flagging RAW there costs nothing extra.
    static func isRaw(_ resources: [PHAssetResource]) -> Bool {
        resources.contains { resource in
            guard let type = UTType(resource.uniformTypeIdentifier) else { return false }
            return type.conforms(to: .rawImage)
        }
    }

    static func isRaw(for asset: PHAsset) -> Bool {
        isRaw(PHAssetResource.assetResources(for: asset))
    }

    /// Instant, but `nil` when PhotoKit withholds the value (common for
    /// iCloud-optimized originals that aren't resident on device).
    static func fastSize(for asset: PHAsset) -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return nil }

        var total: Int64 = 0
        var resolvedAny = false
        for resource in resources {
            guard let bytes = reportedSize(of: resource) else { continue }
            total += bytes
            resolvedAny = true
        }
        return resolvedAny ? total : nil
    }

    /// Streams each resource to count its bytes. Network access stays off so this
    /// never silently pulls originals down from iCloud — assets that live only in
    /// the cloud simply stay unresolved.
    static func streamedSize(for asset: PHAsset) async -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return nil }

        var total: Int64 = 0
        var resolvedAny = false
        for resource in resources {
            guard let bytes = await byteCount(of: resource) else { continue }
            total += bytes
            resolvedAny = true
        }
        return resolvedAny ? total : nil
    }

    private static func byteCount(of resource: PHAssetResource) async -> Int64? {
        await withCheckedContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false

            var count: Int64 = 0
            var finished = false
            let lock = NSLock()

            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                lock.lock()
                count += Int64(chunk.count)
                lock.unlock()
            } completionHandler: { error in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: error == nil ? count : nil)
            }
        }
    }
}
