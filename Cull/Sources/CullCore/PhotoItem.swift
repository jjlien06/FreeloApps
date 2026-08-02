import Foundation

/// A single image file in a culled folder.
///
/// Identity is the filename rather than the full URL so that ratings survive the
/// folder being moved or renamed.
public struct PhotoItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let filename: String
    public let byteSize: Int64

    public var id: String { filename }

    public init(url: URL, filename: String, byteSize: Int64) {
        self.url = url
        self.filename = filename
        self.byteSize = byteSize
    }
}
