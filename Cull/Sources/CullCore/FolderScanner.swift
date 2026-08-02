import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Enumerates the decodable images at the top level of a folder.
public enum FolderScanner {
    /// Every file extension ImageIO can decode on this machine, which is where
    /// RAW support comes from — the list covers CR2/CR3/NEF/ARW/DNG and friends
    /// without hardcoding a camera vendor list that would rot.
    public static let decodableExtensions: Set<String> = {
        var extensions: Set<String> = []
        for identifier in CGImageSourceCopyTypeIdentifiers() as? [String] ?? [] {
            guard let type = UTType(identifier) else { continue }
            for suffix in type.tags[.filenameExtension] ?? [] {
                extensions.insert(suffix.lowercased())
            }
        }
        return extensions
    }()

    /// Scans `folder`, returning its images in natural filename order.
    ///
    /// Hidden files, subdirectories, and anything ImageIO cannot decode are
    /// skipped. Throws only if the folder itself cannot be read.
    public static func scan(
        folder: URL,
        allowedExtensions: Set<String> = decodableExtensions,
        fileManager: FileManager = .default
    ) throws -> [PhotoItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isHiddenKey]
        let contents = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )

        let items: [PhotoItem] = contents.compactMap { url in
            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? false else { return nil }
            return PhotoItem(
                url: url,
                filename: url.lastPathComponent,
                byteSize: Int64(values?.fileSize ?? 0)
            )
        }

        // Natural ordering, so IMG_2 sorts before IMG_10 the way a shoot reads.
        return items.sorted {
            $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }
    }
}
