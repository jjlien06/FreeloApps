import Foundation
import Testing
@testable import CullCore

@Suite struct RatingStoreTests {
    @Test func roundTripsThroughTheSidecar() throws {
        let folder = try TempFolder()
        let store = RatingStore(folder: folder.url)
        store.setRating(Rating(verdict: .pass, stars: 4, note: "sharp"), for: "IMG_1.jpg")
        store.setRating(Rating(verdict: .fail), for: "IMG_2.jpg")
        try store.save()

        let reopened = RatingStore(folder: folder.url)

        #expect(reopened.rating(for: "IMG_1.jpg") == Rating(verdict: .pass, stars: 4, note: "sharp"))
        #expect(reopened.rating(for: "IMG_2.jpg").verdict == .fail)
        #expect(reopened.rating(for: "never-rated.jpg") == Rating())
    }

    @Test func writesTheSidecarNextToThePhotos() throws {
        let folder = try TempFolder()
        let store = RatingStore(folder: folder.url)
        store.setRating(Rating(stars: 3), for: "IMG_1.jpg")
        try store.save()

        #expect(folder.exists(".cull.json"))
    }

    @Test func clampsStarsToTheSupportedRange() throws {
        #expect(Rating(stars: 9).stars == 5)
        #expect(Rating(stars: -3).stars == 0)
    }

    @Test func dropsEntriesThatCarryNoDecision() throws {
        let folder = try TempFolder()
        let store = RatingStore(folder: folder.url)
        store.setRating(Rating(verdict: .pass, stars: 5), for: "IMG_1.jpg")
        store.setRating(Rating(), for: "IMG_1.jpg")

        #expect(store.ratings.isEmpty)
    }

    @Test func removesTheSidecarWhenNothingIsRated() throws {
        let folder = try TempFolder()
        let store = RatingStore(folder: folder.url)
        store.setRating(Rating(verdict: .pass), for: "IMG_1.jpg")
        try store.save()
        #expect(folder.exists(".cull.json"))

        store.setRating(Rating(), for: "IMG_1.jpg")
        try store.save()

        #expect(!folder.exists(".cull.json"))
    }

    @Test func recoversFromACorruptSidecarWithoutLosingTheFile() throws {
        let folder = try TempFolder()
        try folder.write(".cull.json", contents: "{ this is not json")

        let store = RatingStore(folder: folder.url)

        #expect(store.ratings.isEmpty)
        #expect(store.recoveredFromCorruptFile != nil)
        #expect(folder.exists(".cull.json.bak"))
        #expect(!folder.exists(".cull.json"))
    }

    @Test func toleratesAnUnknownVerdictRatherThanFailingTheFolder() throws {
        let folder = try TempFolder()
        try folder.write(
            ".cull.json",
            contents: #"{"version":1,"ratings":{"a.jpg":{"verdict":"maybe","stars":3}}}"#
        )

        let store = RatingStore(folder: folder.url)

        #expect(store.rating(for: "a.jpg").verdict == nil)
        #expect(store.rating(for: "a.jpg").stars == 3)
        #expect(store.recoveredFromCorruptFile == nil)
    }

    @Test func countsVerdicts() throws {
        let folder = try TempFolder()
        let store = RatingStore(folder: folder.url)
        store.setRating(Rating(verdict: .pass), for: "a.jpg")
        store.setRating(Rating(verdict: .pass), for: "b.jpg")
        store.setRating(Rating(verdict: .fail), for: "c.jpg")
        store.setRating(Rating(stars: 2), for: "d.jpg")

        #expect(store.count(of: .pass) == 2)
        #expect(store.count(of: .fail) == 1)
    }
}
