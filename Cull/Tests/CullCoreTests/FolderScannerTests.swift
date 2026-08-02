import Foundation
import Testing
@testable import CullCore

@Suite struct FolderScannerTests {
    @Test func keepsImagesAndDropsEverythingElse() throws {
        let folder = try TempFolder()
        try folder.write("shot.jpg")
        try folder.write("shot.heic")
        try folder.write("shot.png")
        try folder.write("notes.txt")
        try folder.write("archive.zip")
        _ = try folder.makeSubfolder("Selects")

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.filename).sorted() == ["shot.heic", "shot.jpg", "shot.png"])
    }

    @Test func recognisesCameraRawExtensions() throws {
        // ImageIO advertises RAW support on macOS; this guards the derivation of
        // the extension set rather than the decode itself.
        let raw = ["cr2", "cr3", "nef", "arw", "dng"]
        let supported = FolderScanner.decodableExtensions
        #expect(raw.allSatisfy(supported.contains))
    }

    @Test func sortsNaturallyRatherThanLexically() throws {
        let folder = try TempFolder()
        for name in ["IMG_10.jpg", "IMG_2.jpg", "IMG_1.jpg"] { try folder.write(name) }

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.filename) == ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
    }

    @Test func skipsHiddenFiles() throws {
        let folder = try TempFolder()
        try folder.write("visible.jpg")
        try folder.write(".hidden.jpg")

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.filename) == ["visible.jpg"])
    }

    @Test func reportsByteSize() throws {
        let folder = try TempFolder()
        try folder.write("shot.jpg", contents: String(repeating: "a", count: 1234))

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.first?.byteSize == 1234)
    }

    @Test func throwsForMissingFolder() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            try FolderScanner.scan(folder: missing)
        }
    }

    @Test func matchesExtensionsCaseInsensitively() throws {
        let folder = try TempFolder()
        try folder.write("SHOT.JPG")
        try folder.write("raw.CR3")

        let items = try FolderScanner.scan(folder: folder.url)

        #expect(items.map(\.filename).sorted() == ["SHOT.JPG", "raw.CR3"])
    }
}
