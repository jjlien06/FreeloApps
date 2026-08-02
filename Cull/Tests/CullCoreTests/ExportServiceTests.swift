import Foundation
import Testing
@testable import CullCore

@Suite struct ExportServiceTests {
    private func items(in folder: TempFolder, _ names: [String]) throws -> [PhotoItem] {
        try names.map { name in
            let url = try folder.write(name, contents: name)
            return PhotoItem(url: url, filename: name, byteSize: Int64(name.utf8.count))
        }
    }

    @Test func copiesOnlyThePasses() throws {
        let folder = try TempFolder()
        let photos = try items(in: folder, ["keep.jpg", "cut.jpg", "unrated.jpg"])
        let ratings = [
            "keep.jpg": Rating(verdict: .pass, stars: 5),
            "cut.jpg": Rating(verdict: .fail),
            "unrated.jpg": Rating(stars: 3),
        ]
        let destination = folder.url.appendingPathComponent("Selects", isDirectory: true)

        let summary = try ExportService.exportPasses(items: photos, ratings: ratings, to: destination)

        #expect(summary.copied == ["keep.jpg"])
        #expect(folder.exists("Selects/keep.jpg"))
        #expect(!folder.exists("Selects/cut.jpg"))
        #expect(!folder.exists("Selects/unrated.jpg"))
    }

    @Test func leavesOriginalsInPlace() throws {
        let folder = try TempFolder()
        let photos = try items(in: folder, ["keep.jpg"])
        let ratings = ["keep.jpg": Rating(verdict: .pass)]

        _ = try ExportService.exportPasses(
            items: photos,
            ratings: ratings,
            to: folder.url.appendingPathComponent("Selects", isDirectory: true)
        )

        #expect(folder.exists("keep.jpg"))
    }

    @Test func skipsCollisionsInsteadOfOverwriting() throws {
        let folder = try TempFolder()
        let photos = try items(in: folder, ["keep.jpg"])
        let destination = try folder.makeSubfolder("Selects")
        let existing = destination.appendingPathComponent("keep.jpg")
        try Data("original".utf8).write(to: existing)

        let summary = try ExportService.exportPasses(
            items: photos,
            ratings: ["keep.jpg": Rating(verdict: .pass)],
            to: destination
        )

        #expect(summary.copied.isEmpty)
        #expect(summary.skippedExisting == ["keep.jpg"])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "original")
    }

    @Test func reportsSourcesThatVanishedAfterTheScan() throws {
        let folder = try TempFolder()
        let missing = PhotoItem(
            url: folder.url.appendingPathComponent("ghost.jpg"),
            filename: "ghost.jpg",
            byteSize: 100
        )

        let summary = try ExportService.exportPasses(
            items: [missing],
            ratings: ["ghost.jpg": Rating(verdict: .pass)],
            to: folder.url.appendingPathComponent("Selects", isDirectory: true)
        )

        #expect(summary.copied.isEmpty)
        #expect(summary.failed.map(\.filename) == ["ghost.jpg"])
    }

    @Test func doesNotCreateTheFolderWhenThereIsNothingToExport() throws {
        let folder = try TempFolder()
        let photos = try items(in: folder, ["cut.jpg"])

        let summary = try ExportService.exportPasses(
            items: photos,
            ratings: ["cut.jpg": Rating(verdict: .fail)],
            to: folder.url.appendingPathComponent("Selects", isDirectory: true)
        )

        #expect(summary.isEmpty)
        #expect(!folder.exists("Selects"))
    }
}
