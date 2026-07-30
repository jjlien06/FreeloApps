import Foundation
import Photos

/// One row in the grid: a library asset plus its resolved size, if known.
struct AssetItem: Identifiable {
    let asset: PHAsset
    var bytes: Int64?
    /// Discovered during the size pass, which already enumerates resources.
    var isRaw = false

    var id: String { asset.localIdentifier }
    var creationDate: Date? { asset.creationDate }
    var isVideo: Bool { asset.mediaType == .video }
    var duration: TimeInterval { asset.duration }

    var pixelDescription: String {
        "\(asset.pixelWidth) × \(asset.pixelHeight)"
    }
}

extension AssetItem: Hashable {
    static func == (lhs: AssetItem, rhs: AssetItem) -> Bool {
        lhs.id == rhs.id && lhs.bytes == rhs.bytes && lhs.isRaw == rhs.isRaw
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(bytes)
        hasher.combine(isRaw)
    }
}
