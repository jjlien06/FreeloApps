import Foundation
import Testing
@testable import CullCore

@MainActor
@Suite struct CullSessionTests {
    /// FolderScanner filters on extension and never decodes, so stub files are
    /// enough to exercise the whole session.
    private func session(with names: [String]) throws -> (CullSession, TempFolder) {
        let folder = try TempFolder()
        for name in names { try folder.write(name) }
        let session = CullSession()
        session.open(folder: folder.url)
        return (session, folder)
    }

    @Test func opensAFolderInNaturalOrder() throws {
        let (session, _) = try session(with: ["b_2.jpg", "b_10.jpg", "a_1.jpg", "notes.txt"])

        #expect(session.allItems.map(\.filename) == ["a_1.jpg", "b_2.jpg", "b_10.jpg"])
        #expect(session.current?.filename == "a_1.jpg")
        #expect(session.unratedCount == 3)
    }

    @Test func aVerdictAdvancesToTheNextPhoto() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg", "3.jpg"])

        session.setVerdict(.pass)

        #expect(session.rating(for: "1.jpg").verdict == .pass)
        #expect(session.current?.filename == "2.jpg")
        #expect(session.passCount == 1)
    }

    @Test func starsDoNotAdvance() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])

        session.setStars(4)

        #expect(session.currentRating.stars == 4)
        #expect(session.current?.filename == "1.jpg")
    }

    @Test func autoAdvanceCanBeTurnedOff() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])
        session.autoAdvance = false

        session.setVerdict(.fail)

        #expect(session.current?.filename == "1.jpg")
        #expect(session.failCount == 1)
    }

    @Test func advancingStopsAtTheLastPhoto() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])

        session.setVerdict(.pass)
        session.setVerdict(.pass)
        session.next()

        #expect(session.cursor == 1)
        #expect(session.current?.filename == "2.jpg")
    }

    @Test func previousStopsAtTheFirstPhoto() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])

        session.previous()

        #expect(session.cursor == 0)
    }

    /// The subtle one: rating a photo while filtered to "Unrated" removes it
    /// from view, so the cursor must stay put rather than skipping a frame.
    @Test func ratingUnderAFilterLandsOnTheNextPhotoNotTheOneAfter() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg", "3.jpg"])
        session.filter = .unrated

        session.setVerdict(.pass)

        #expect(session.items.map(\.filename) == ["2.jpg", "3.jpg"])
        #expect(session.cursor == 0)
        #expect(session.current?.filename == "2.jpg")
    }

    @Test func filteringToPassesShowsOnlyKeepers() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg", "3.jpg"])
        session.setVerdict(.pass)   // 1.jpg
        session.setVerdict(.fail)   // 2.jpg

        session.filter = .passes

        #expect(session.items.map(\.filename) == ["1.jpg"])
        #expect(session.current?.filename == "1.jpg")
    }

    @Test func starFilterSelectsOnScoreNotVerdict() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])
        session.setStars(4)
        session.next()
        session.setStars(2)

        session.filter = .threeStarsPlus

        #expect(session.items.map(\.filename) == ["1.jpg"])
    }

    @Test func cursorIsClampedWhenAFilterEmptiesTheView() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])
        session.next()

        session.filter = .passes

        #expect(session.items.isEmpty)
        #expect(session.cursor == 0)
        #expect(session.current == nil)
    }

    @Test func clearingAVerdictReturnsThePhotoToUnrated() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])
        session.setVerdict(.pass)
        session.cursor = 0

        session.setVerdict(nil)

        #expect(session.rating(for: "1.jpg").verdict == nil)
        #expect(session.passCount == 0)
        #expect(session.unratedCount == 2)
    }

    @Test func ratingsSurviveReopeningTheFolder() throws {
        let (session, folder) = try session(with: ["1.jpg", "2.jpg"])
        session.setStars(5)
        session.setVerdict(.pass)
        session.flushSave()

        let reopened = CullSession()
        reopened.open(folder: folder.url)

        #expect(reopened.rating(for: "1.jpg") == Rating(verdict: .pass, stars: 5))
        #expect(reopened.passCount == 1)
    }

    @Test func exportCopiesOnlyThePassesIntoSelects() throws {
        let (session, folder) = try session(with: ["1.jpg", "2.jpg", "3.jpg"])
        session.setVerdict(.pass)   // 1.jpg
        session.setVerdict(.fail)   // 2.jpg

        let summary = try session.exportPasses()

        #expect(summary.copied == ["1.jpg"])
        #expect(folder.exists("Selects/1.jpg"))
        #expect(!folder.exists("Selects/2.jpg"))
    }

    @Test func aCorruptSidecarIsReportedRatherThanSwallowed() throws {
        let folder = try TempFolder()
        try folder.write("1.jpg")
        try folder.write(".cull.json", contents: "not json at all")

        let session = CullSession()
        session.open(folder: folder.url)

        #expect(session.recoveryNotice != nil)
        #expect(session.ratings.isEmpty)
        #expect(session.allItems.count == 1)
    }

    @Test func anEmptyFolderReportsItselfInsteadOfLookingBroken() throws {
        let folder = try TempFolder()

        let session = CullSession()
        session.open(folder: folder.url)

        #expect(session.allItems.isEmpty)
        #expect(session.loadError != nil)
        #expect(session.current == nil)
    }

    @Test func filterCyclingVisitsEveryFilterAndReturns() throws {
        var filter = CullSession.Filter.all
        var seen: [CullSession.Filter] = []
        for _ in CullSession.Filter.allCases {
            seen.append(filter)
            filter = filter.next
        }

        #expect(seen.count == Set(seen.map(\.label)).count)
        #expect(filter == .all)
    }

    @Test func zoomResetsWhenMovingToAnotherPhoto() throws {
        let (session, _) = try session(with: ["1.jpg", "2.jpg"])
        session.isZoomed = true

        session.next()

        #expect(!session.isZoomed)
    }
}
