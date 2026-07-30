import CoreGraphics
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

struct ConversionOutcome: Identifiable {
    let asset: PHAsset
    let label: String
    let originalBytes: Int64
    let newBytes: Int64
    /// nil means a replacement asset exists in the library and was confirmed.
    let failure: String?

    var id: String { asset.localIdentifier }
    var succeeded: Bool { failure == nil }
    var saved: Int64 { max(originalBytes - newBytes, 0) }
}

/// Turns camera RAW / Apple ProRAW assets into ordinary compressed images.
///
/// Rendering goes through `PHImageManager` rather than `CIRAWFilter` so the result
/// matches what Photos already shows you — including any edits you've made — instead of
/// a differently-demosaiced reinterpretation.
///
/// Originals are never touched here. The caller deletes them, and only for assets whose
/// replacement was confirmed to exist in the library afterwards.
enum RawConverter {
    enum Format: String, CaseIterable, Identifiable {
        case heic
        case jpeg

        var id: String { rawValue }

        var label: String {
            switch self {
            case .heic: "HEIC"
            case .jpeg: "JPEG"
            }
        }

        var utType: UTType {
            switch self {
            case .heic: .heic
            case .jpeg: .jpeg
            }
        }

        var fileExtension: String {
            switch self {
            case .heic: "heic"
            case .jpeg: "jpg"
            }
        }
    }

    struct Tick {
        var completed: Int
        var currentLabel: String
    }

    /// Converts each item and returns one outcome per item. Does NOT delete anything.
    static func convert(
        _ items: [AssetItem],
        to format: Format,
        quality: Double = 0.9,
        onTick: @MainActor @escaping (Tick) -> Void
    ) async -> [ConversionOutcome] {
        var outcomes: [ConversionOutcome] = []

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }

            let name = PHAssetResource.assetResources(for: item.asset).first?.originalFilename
                ?? "RAW image"
            await onTick(Tick(completed: index, currentLabel: name))

            outcomes.append(
                await convertOne(item, label: name, to: format, quality: quality)
            )

            await onTick(Tick(completed: index + 1, currentLabel: name))
        }

        return outcomes
    }

    private static func convertOne(
        _ item: AssetItem,
        label: String,
        to format: Format,
        quality: Double
    ) async -> ConversionOutcome {
        func fail(_ reason: String) -> ConversionOutcome {
            ConversionOutcome(
                asset: item.asset,
                label: label,
                originalBytes: item.bytes ?? 0,
                newBytes: 0,
                failure: reason
            )
        }

        guard let rendered = await fullSizeImage(for: item.asset) else {
            return fail("Couldn't render the RAW file.")
        }

        guard let encoded = encode(rendered, to: format, quality: quality) else {
            return fail("Couldn't encode to \(format.label).")
        }

        // Sanity-check our own output before it becomes the only copy that remains.
        guard case .intact = await verifyEncoded(encoded, format: format) else {
            return fail("The \(format.label) that came out wouldn't decode.")
        }

        let baseName = (label as NSString).deletingPathExtension
        let newIdentifier: String?
        do {
            newIdentifier = try await createAsset(
                data: encoded,
                filename: "\(baseName).\(format.fileExtension)",
                copying: item.asset
            )
        } catch {
            return fail("Couldn't add the converted image: \(error.localizedDescription)")
        }

        // Confirm the replacement is really in the library. Without this the caller could
        // delete a RAW whose replacement silently never landed.
        guard let newIdentifier,
              let created = PHAsset.fetchAssets(
                  withLocalIdentifiers: [newIdentifier],
                  options: nil
              ).firstObject
        else {
            return fail("The converted image didn't appear in the library.")
        }

        let newBytes = AssetSizer.fastSize(for: created) ?? Int64(encoded.count)

        return ConversionOutcome(
            asset: item.asset,
            label: label,
            originalBytes: item.bytes ?? 0,
            newBytes: newBytes,
            failure: nil
        )
    }

    // MARK: Rendering

    private static func fullSizeImage(for asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = PHImageRequestOptionsResizeMode.none
        options.isNetworkAccessAllowed = true
        options.version = .current   // include edits

        return await withCheckedContinuation { continuation in
            var finished = false
            let lock = NSLock()

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded else { return }   // wait for the full-quality pass
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    // MARK: Encoding

    private static func encode(_ image: CGImage, to format: Format, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            // HEIC encoding isn't available everywhere (notably some simulators).
            if format == .heic {
                return encode(image, to: .jpeg, quality: quality)
            }
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func verifyEncoded(
        _ data: Data,
        format: Format
    ) async -> FileIntegrity.Verdict {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128,
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary) != nil
        else {
            return .damaged("encoded \(format.label) wouldn't decode")
        }
        return .intact
    }

    // MARK: Library write

    /// Returns the new asset's local identifier.
    private static func createAsset(
        data: Data,
        filename: String,
        copying original: PHAsset
    ) async throws -> String? {
        var placeholderIdentifier: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = filename
            request.addResource(with: .photo, data: data, options: resourceOptions)

            // Carry across the metadata that makes it feel like the same photo.
            request.creationDate = original.creationDate
            request.location = original.location
            request.isFavorite = original.isFavorite

            placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
        }

        return placeholderIdentifier
    }
}
