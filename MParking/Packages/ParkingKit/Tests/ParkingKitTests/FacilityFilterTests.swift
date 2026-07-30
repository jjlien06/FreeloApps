import Foundation
import Testing
@testable import ParkingKit

@Suite("Facility filtering")
struct FacilityFilterTests {
    let rules = ParkingRules()
    let data: Dataset

    init() throws {
        data = try Dataset.bundled()
    }

    var all: [Facility] { data.parkable }

    @Test("Default filter hides the never-free lots and nothing else")
    func defaults() {
        let f = FacilityFilter()
        let kept = f.apply(to: all, rules: rules)
        let neverFree = all.filter { rules.neverBecomesFree($0) }

        #expect(!neverFree.isEmpty, "the dataset should contain some 24/7 lots")
        #expect(kept.count == all.count - neverFree.count)
        #expect(!kept.contains { rules.neverBecomesFree($0) })
    }

    @Test("Turning the never-free filter off restores those lots")
    func showNeverFree() {
        var f = FacilityFilter()
        f.hidesNeverFree = false
        #expect(f.apply(to: all, rules: rules).count == all.count)
    }

    @Test("Every kept facility becomes free at some point in the week")
    func keptFacilitiesAreReachable() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ParkingRules.timeZone
        let monday = cal.date(from: DateComponents(year: 2026, month: 8, day: 3))!

        for f in FacilityFilter().apply(to: all, rules: rules) {
            let everFree = (0..<(7 * 24)).contains { hour in
                let t = cal.date(byAdding: .hour, value: hour, to: monday)!
                return rules.status(of: f, at: t).isFreeToAll
            }
            #expect(everFree, "\(f.id) survived the never-free filter but is never free")
        }
    }

    @Test("Tier filter keeps only the chosen colours")
    func tierFilter() {
        var f = FacilityFilter()
        f.tiers = [.blue]
        let kept = f.apply(to: all, rules: rules)
        #expect(!kept.isEmpty)
        #expect(kept.allSatisfy { $0.tier == .blue })

        f.tiers = [.blue, .yellow]
        let both = f.apply(to: all, rules: rules)
        #expect(both.count > kept.count)
        #expect(both.allSatisfy { $0.tier == .blue || $0.tier == .yellow })
    }

    @Test("Empty tier set means every tier")
    func emptyTierMeansAll() {
        var f = FacilityFilter()
        f.tiers = []
        let kept = f.apply(to: all, rules: rules)
        #expect(Set(kept.map(\.tier)).count > 1)
        #expect(f.includes(.blue) && f.includes(.gold) && f.includes(.orange))
    }

    @Test("Toggling from 'all' removes exactly one tier")
    func toggleFromAll() {
        let available: [Tier] = [.blue, .yellow, .orange, .gold]
        var f = FacilityFilter()
        f.toggle(.blue, available: available)
        #expect(f.tiers == Set([.yellow, .orange, .gold]))
        #expect(!f.includes(.blue))
        #expect(f.includes(.yellow))
    }

    @Test("Re-adding the last tier collapses back to 'all'")
    func toggleBackToAll() {
        let available: [Tier] = [.blue, .yellow, .orange, .gold]
        var f = FacilityFilter()
        f.toggle(.blue, available: available)      // -> yellow, orange, gold
        f.toggle(.blue, available: available)      // -> all four == all
        #expect(f.tiers.isEmpty, "a full selection should normalise to 'all'")
        #expect(f.includes(.blue))
    }

    @Test("Removing the final selected tier means 'all', never 'nothing'")
    func neverEmptySelection() {
        let available: [Tier] = [.blue, .yellow]
        var f = FacilityFilter()
        f.tiers = [.blue]
        f.toggle(.blue, available: available)
        #expect(f.tiers.isEmpty)
        #expect(!f.apply(to: all, rules: rules).isEmpty,
                "the list must never end up empty because of a tier toggle")
    }

    @Test("System and campus filters compose with the others")
    func compose() {
        var f = FacilityFilter()
        f.systems = [.dda]
        let downtown = f.apply(to: all, rules: rules)
        #expect(!downtown.isEmpty)
        #expect(downtown.allSatisfy { $0.system == .dda })

        f.systems = [.umich]
        f.campuses = [.central]
        f.tiers = [.blue]
        let centralBlue = f.apply(to: all, rules: rules)
        #expect(!centralBlue.isEmpty)
        #expect(centralBlue.allSatisfy {
            $0.system == .umich && $0.campus == .central && $0.tier == .blue
        })
        // E8 Church Street is Central Blue but enforced 24h Mon-Sat, which still
        // frees up on Sunday, so it must survive the never-free filter.
        #expect(centralBlue.contains { $0.lotId == "E8" })
        // N8 Rackham is Gold and 24/7 - excluded by both tier and never-free.
        #expect(!centralBlue.contains { $0.lotId == "N8" })
    }
}
