import CoreGraphics
import Foundation
import ImageIO

/// An immutable decoded image. `CGImage` is not formally `Sendable`, but it is
/// immutable once created, so boxing it is safe and keeps the loader off the
/// main actor.
nonisolated final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    let cost: Int

    init(_ cgImage: CGImage) {
        self.cgImage = cgImage
        self.cost = cgImage.bytesPerRow * cgImage.height
    }
}

/// Decodes and caches images off the main actor.
///
/// Two sizes are used: small thumbnails for the filmstrip and grid, and a
/// downsampled full frame for the loupe. Decodes run detached so a slow RAW
/// frame never blocks a cheap thumbnail, and identical requests are coalesced.
actor ImageLoader {
    static let shared = ImageLoader()

    enum Size: Int {
        case filmstrip = 240
        case grid = 480
        case loupe = 2400
        /// Only decoded on demand, when the loupe is zoomed in.
        case zoom = 6000

        /// Whether to force a full RAW render rather than accept the preview a
        /// RAW file already carries.
        ///
        /// This is the difference between a usable and an unusable filmstrip.
        /// Measured on a Canon CR3 off an external drive: forcing the render for
        /// a 240px thumbnail took 4755ms, against 85ms when the embedded preview
        /// is allowed to satisfy it. At loupe size the full render is worth its
        /// ~145ms, because judging focus is the entire point of the big view.
        var demandsFullRender: Bool {
            switch self {
            case .filmstrip, .grid: false
            case .loupe, .zoom: true
            }
        }
    }

    private let cache: NSCache<NSString, DecodedImage> = {
        let cache = NSCache<NSString, DecodedImage>()
        cache.totalCostLimit = 768 * 1024 * 1024
        return cache
    }()

    private var inFlight: [String: Task<DecodedImage?, Never>] = [:]

    func image(for url: URL, size: Size) async -> DecodedImage? {
        let key = "\(url.path)|\(size.rawValue)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task.detached(priority: .userInitiated) {
            ImageLoader.decode(
                url: url,
                maxPixelSize: size.rawValue,
                fullRender: size.demandsFullRender
            )
        }
        inFlight[key] = task
        let decoded = await task.value
        inFlight[key] = nil

        if let decoded {
            cache.setObject(decoded, forKey: key as NSString, cost: decoded.cost)
        }
        return decoded
    }

    /// Warms the cache for frames the cursor is about to reach, which is what
    /// keeps RAW navigation from stalling.
    func prefetch(_ urls: [URL], size: Size) {
        for url in urls {
            let key = "\(url.path)|\(size.rawValue)"
            guard cache.object(forKey: key as NSString) == nil, inFlight[key] == nil else { continue }
            Task { _ = await image(for: url, size: size) }
        }
    }

    /// Reads pixel dimensions without decoding, for the zoom control.
    nonisolated static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    nonisolated private static func decode(
        url: URL,
        maxPixelSize: Int,
        fullRender: Bool
    ) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,  // honours EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        // See Size.demandsFullRender: forcing the render for small thumbnails
        // costs ~56× on RAW for detail nobody can see at 240px.
        let key = fullRender
            ? kCGImageSourceCreateThumbnailFromImageAlways
            : kCGImageSourceCreateThumbnailFromImageIfAbsent
        options[key] = true

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return DecodedImage(image)
    }
}
