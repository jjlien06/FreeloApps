import AVFoundation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Content-level verification for exported files.
///
/// Exists because a byte count is not always available: `PHAssetResource`'s `fileSize`
/// is frequently withheld for iCloud-optimized originals — exactly the assets that get
/// downloaded mid-export and are therefore most exposed to a truncated write. Rather
/// than let "no expected size" silently mean "verified", those files are checked by
/// actually parsing them.
enum FileIntegrity {
    enum Verdict {
        case intact
        case damaged(String)
    }

    static func verify(_ url: URL, isVideo: Bool) async -> Verdict {
        isVideo ? await verifyVideo(url) : verifyImage(url)
    }

    /// True for any resource that should be validated as a movie rather than an image.
    static func isVideoResource(_ resource: PHAssetResource) -> Bool {
        switch resource.type {
        case .video, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo:
            return true
        default:
            break
        }
        guard let type = UTType(resource.uniformTypeIdentifier) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    // MARK: Images

    private static func verifyImage(_ url: URL) -> Verdict {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .damaged("file isn't a readable image")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            return .damaged("image container holds no frames")
        }

        let status = CGImageSourceGetStatus(source)
        guard status == .statusComplete else {
            return .damaged("image data incomplete (status \(status.rawValue))")
        }

        // Forcing a thumbnail FROM THE IMAGE (never the embedded preview) decodes the
        // actual pixel data, so a file truncated after its header still fails here.
        // Costlier than a byte comparison, but this gates deleting the original.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceShouldCache: false,
        ]
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else {
            return .damaged("image pixel data wouldn't decode")
        }
        return .intact
    }

    // MARK: Video

    private static func verifyVideo(_ url: URL) async -> Verdict {
        let asset = AVURLAsset(url: url)
        do {
            let (duration, isPlayable) = try await asset.load(.duration, .isPlayable)
            guard isPlayable else { return .damaged("video isn't playable") }
            guard duration.isNumeric, duration.seconds > 0 else {
                return .damaged("video reports no duration")
            }
            let tracks = try await asset.load(.tracks)
            guard !tracks.isEmpty else { return .damaged("video has no tracks") }
            return .intact
        } catch {
            return .damaged("video wouldn't parse: \(error.localizedDescription)")
        }
    }
}
