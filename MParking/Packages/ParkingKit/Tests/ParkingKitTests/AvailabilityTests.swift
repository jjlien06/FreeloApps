import Foundation
import Testing
@testable import ParkingKit

@Suite("LTP availability page parsing")
struct LTPParsingTests {

    /// A minimal page shaped exactly like LTP's: a tier heading, then rows.
    let synthetic = """
    <h3>Blue Parking</h3>
    <h4>Medical Campus</h4>
    <table><tbody>
      <tr><th>Structure/Lot</th><th>Blue Occupancy</th></tr>
      <tr><td>P1 Parking Structure</td><td>\n68%\n</td></tr>
      <tr><td>M93 Wall St. East Structure</td><td>19%</td></tr>
    </tbody></table>
    <h4>Central Campus</h4>
    <table><tbody>
      <tr><th>Structure/Lot</th><th>Blue Occupancy</th></tr>
      <tr><td>E8 Church St. Structure</td><td>14%</td></tr>
      <tr><td>Forest St. Structure</td><td>3%</td></tr>
    </tbody></table>
    <p>Last Update: July 30, 2026 6:16:04 pm</p>
    """

    @Test("Reads label/percent pairs and the tier from the column header")
    func parsesSynthetic() {
        let snap = AvailabilityParser.parseLTP(html: synthetic)
        #expect(snap.readings.count == 4)
        #expect(snap.readings[0] == OccupancyReading(label: "P1 Parking Structure",
                                                     tier: .blue, percent: 68))
        #expect(snap.readings[3] == OccupancyReading(label: "Forest St. Structure",
                                                     tier: .blue, percent: 3))
        #expect(snap.lastUpdate == "July 30, 2026 6:16:04 pm")
    }

    @Test("Tracks a tier change partway down the page")
    func tierSwitch() {
        let html = """
        <table><tr><th>Structure/Lot</th><th>Gold Occupancy</th></tr>
        <tr><td>M101 Zina Parking Structure</td><td>21%</td></tr></table>
        <table><tr><th>Structure/Lot</th><th>Blue Occupancy</th></tr>
        <tr><td>NC60 Parking Lot</td><td>21%</td></tr></table>
        """
        let snap = AvailabilityParser.parseLTP(html: html)
        #expect(snap.readings.count == 2)
        #expect(snap.readings[0].tier == .gold)
        #expect(snap.readings[1].tier == .blue)
    }

    @Test("Parses the saved real page from ltp.umich.edu")
    func parsesRealFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "ltp-availability",
                                                withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let snap = AvailabilityParser.parseLTP(html: html)

        #expect(!snap.readings.isEmpty, "should find at least one occupancy row")
        #expect(snap.lastUpdate != nil)
        // Every reading must be a sane percentage.
        for r in snap.readings {
            #expect(r.percent >= 0 && r.percent <= 100)
            #expect(!r.label.isEmpty)
            #expect(!r.label.contains("%"), "label leaked a percentage: \(r.label)")
        }
        // The real page always carries at least one Blue figure.
        #expect(snap.readings.contains { $0.tier == .blue })
    }

    @Test("Percentage cell detection rejects non-percentages")
    func percentDetection() {
        #expect(AvailabilityParser.percentValue(" 68% ") == 68)
        #expect(AvailabilityParser.percentValue("0%") == 0)
        #expect(AvailabilityParser.percentValue("100%") == 100)
        #expect(AvailabilityParser.percentValue("120%") == nil)
        #expect(AvailabilityParser.percentValue("Structure/Lot") == nil)
        #expect(AvailabilityParser.percentValue("68") == nil)
    }
}

@Suite("Matching availability rows to facilities")
struct MatcherTests {
    let aliases = [
        "P1 Parking Structure": ["M15"],
        "P4 Parking Structure": ["M22"],
        "M5/M86 Catherine and Ann Structures": ["M5", "M86"],
        "Forest St. Structure": ["S28"]
    ]

    @Test("Leading lot id is used when present")
    func leadingLotId() {
        #expect(AvailabilityMatcher.lotIds(for: "E8 Church St. Structure", aliases: aliases) == ["E8"])
        #expect(AvailabilityMatcher.lotIds(for: "NC60 Parking Lot", aliases: aliases) == ["NC60"])
        #expect(AvailabilityMatcher.lotIds(for: "M99 Wall St. West Structure", aliases: aliases) == ["M99"])
        #expect(AvailabilityMatcher.lotIds(for: "S8 Hill Structure", aliases: aliases) == ["S8"])
        #expect(AvailabilityMatcher.lotIds(for: "W3 Thompson Structure", aliases: aliases) == ["W3"])
    }

    @Test("Alias table wins over the leading token")
    func aliasBeatsToken() {
        // "P1" looks like a lot id but is not one - it is M15.
        #expect(AvailabilityMatcher.lotIds(for: "P1 Parking Structure", aliases: aliases) == ["M15"])
        #expect(AvailabilityMatcher.lotIds(for: "P4 Parking Structure", aliases: aliases) == ["M22"])
    }

    @Test("One row can cover two lots")
    func multiLotRow() {
        #expect(AvailabilityMatcher.lotIds(for: "M5/M86 Catherine and Ann Structures",
                                           aliases: aliases) == ["M5", "M86"])
    }

    @Test("A row naming no known lot resolves to nothing rather than guessing")
    func unknownRow() {
        #expect(AvailabilityMatcher.lotIds(for: "Some New Structure", aliases: aliases).isEmpty)
    }

    @Test("Indexing against the real dataset links rows to facilities")
    func indexAgainstDataset() throws {
        let data = try Dataset.bundled()
        let readings = [
            OccupancyReading(label: "E8 Church St. Structure", tier: .blue, percent: 14),
            OccupancyReading(label: "P1 Parking Structure", tier: .blue, percent: 68),
            OccupancyReading(label: "Forest St. Structure", tier: .blue, percent: 3),
            OccupancyReading(label: "NC60 Parking Lot", tier: .blue, percent: 21)
        ]
        let index = AvailabilityMatcher.index(readings: readings,
                                              facilities: data.facilities,
                                              aliases: data.availabilityAliases)
        #expect(index["umich:E8"]?.percent == 14)
        #expect(index["umich:M15"]?.percent == 68, "P1 should resolve to M15")
        #expect(index["umich:S28"]?.percent == 3, "Forest St should resolve to S28")
        #expect(index["umich:NC60"]?.percent == 21)
    }
}

@Suite("DDA live counts")
struct DDATests {

    @Test("Parses the DDA count payload")
    func parsesCounts() throws {
        let json = """
        {"countdata":[
          {"facility":"80","spacesavail":"108","timestamp":"7/30/2026 6:05:13 PM"},
          {"facility":"87 S","spacesavail":"6","timestamp":"7/30/2026 6:05:13 PM"},
          {"facility":"88","spacesavail":"0","timestamp":"7/30/2026 6:05:13 PM"}
        ]}
        """
        let counts = try AvailabilityParser.parseDDA(json: Data(json.utf8))
        #expect(counts.count == 3)
        #expect(counts[0] == SpaceCount(facilityKey: "80", spacesAvailable: 108,
                                        timestamp: "7/30/2026 6:05:13 PM"))
        #expect(counts[1].facilityKey == "87 S")
        #expect(counts[2].spacesAvailable == 0)
    }

    @Test("Malformed rows are dropped, not fatal")
    func toleratesJunk() throws {
        let json = """
        {"countdata":[
          {"facility":"80","spacesavail":"n/a","timestamp":"t"},
          {"facility":"81","spacesavail":"67","timestamp":"t"}
        ]}
        """
        let counts = try AvailabilityParser.parseDDA(json: Data(json.utf8))
        #expect(counts.count == 1)
        #expect(counts[0].facilityKey == "81")
    }

    @Test("Negative counts are dropped rather than shown as full")
    func dropsNegativeCounts() throws {
        // Observed live on 2026-07-30: facility 84 reported "-7".
        let json = """
        {"countdata":[
          {"facility":"84","spacesavail":"-7","timestamp":"t"},
          {"facility":"86","spacesavail":"641","timestamp":"t"},
          {"facility":"89","spacesavail":"0","timestamp":"t"}
        ]}
        """
        let counts = try AvailabilityParser.parseDDA(json: Data(json.utf8))
        #expect(counts.map(\.facilityKey) == ["86", "89"],
                "a negative tally must not be reported as a space count")
        // A genuine zero is still meaningful - that one means full.
        #expect(counts.last?.spacesAvailable == 0)
    }
}

@Suite("Bundled dataset integrity")
struct DatasetTests {

    @Test("Loads and has both systems")
    func loads() throws {
        let d = try Dataset.bundled()
        #expect(d.version == 1)
        #expect(d.facilities.count > 100)
        #expect(!d.facilities(in: .umich).isEmpty)
        #expect(d.facilities(in: .dda).count == 20)
        #expect(d.timeZone == "America/Detroit")
    }

    @Test("Every facility carries provenance")
    func provenance() throws {
        for f in try Dataset.bundled().facilities {
            #expect(!f.source.isEmpty, "\(f.id) has no source")
            #expect(!f.verifiedOn.isEmpty, "\(f.id) has no verifiedOn date")
            #expect(!f.enforcement.raw.isEmpty, "\(f.id) lost its original hours text")
        }
    }

    @Test("Facility ids are unique")
    func uniqueIds() throws {
        let ids = try Dataset.bundled().facilities.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Windows are well formed and confined to one day")
    func windowsWellFormed() throws {
        for f in try Dataset.bundled().facilities {
            for w in f.enforcement.windows {
                #expect((1...7).contains(w.day), "\(f.id) has weekday \(w.day)")
                #expect(w.startMinutes < w.endMinutes,
                        "\(f.id) window \(w.start)-\(w.end) is not forward-going")
                #expect(w.endMinutes <= 24 * 60, "\(f.id) window ends past 24:00")
            }
        }
    }

    @Test("Known facilities carry the hours LTP publishes")
    func spotCheckKnownLots() throws {
        let d = try Dataset.bundled()
        let rules = ParkingRules()

        // S8 Hill Street: 6am-5pm Mon-Sat -> free Sunday, free weekday evenings.
        let hill = try #require(d.facility(lotId: "S8"))
        #expect(hill.enforcement.raw.contains("6am"))
        #expect(hill.enforcement.windows.count == 6)

        // E8 Church Street: 24 hrs Mon-Sat -> only Sunday is free.
        let church = try #require(d.facility(lotId: "E8"))
        #expect(church.enforcement.windows.count == 6)
        #expect(church.enforcement.windows.allSatisfy { $0.start == "00:00" && $0.end == "24:00" })

        // N8 Rackham is Gold, 24/7.
        let rackham = try #require(d.facility(lotId: "N8"))
        #expect(rackham.tier == .gold)
        #expect(rackham.enforcement.windows.count == 7)
        #expect(rules.nextTransition(rackham, after: Date()) == nil)

        // M93 Wall Street East: the continuous Mon 6am -> Sat 1am span.
        let wall = try #require(d.facility(lotId: "M93"))
        #expect(wall.enforcement.windows.count == 6)
        #expect(wall.enforcement.windows.first { $0.day == 6 }?.end == "01:00")
    }

    @Test("Downtown structures follow the Sunday rule; metered lots follow meter hours")
    func ddaRules() throws {
        let d = try Dataset.bundled()
        let rules = ParkingRules()

        // Gated structure: free Sunday 4am - Monday 4am.
        let library = try #require(d.facilities.first { $0.id == "dda:library-lane" })
        #expect(library.confidence == .verified)
        #expect(library.capacity == 665)
        #expect(library.enforcement.windows.count == 7)

        // South Ashley is grouped with the structures by DDA, so it gets the
        // structure hours rather than meter hours.
        let ashley = try #require(d.facilities.first { $0.id == "dda:south-ashley" })
        #expect(ashley.enforcement.windows.count == 7)
        #expect(ashley.enforcement.raw.contains("Sunday"))

        // A metered lot: Mon-Sat 8am-6pm only, so free on a weekday evening.
        let market = try #require(d.facilities.first { $0.id == "dda:farmers-market" })
        #expect(market.confidence == .verified)
        #expect(market.enforcement.windows.count == 6)
        #expect(market.enforcement.windows.allSatisfy { $0.start == "08:00" && $0.end == "18:00" })

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ParkingRules.timeZone
        // Wednesday 2026-07-29 19:00 - after meters stop.
        let evening = cal.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 19))!
        #expect(rules.status(of: market, at: evening).isFreeToAll)
        #expect(!rules.status(of: ashley, at: evening).isFreeToAll,
                "a gated lot is still paid on a weekday evening")
    }

    @Test("Nothing in the shipped dataset is unverified")
    func everythingVerified() throws {
        let unverified = try Dataset.bundled().facilities.filter { $0.confidence != .verified }
        #expect(unverified.isEmpty,
                "unverified: \(unverified.map(\.name).joined(separator: ", "))")
    }

    @Test("Parkable excludes service and contractor tiers")
    func parkableFilter() throws {
        let d = try Dataset.bundled()
        #expect(d.parkable.count < d.facilities.count)
        #expect(!d.parkable.contains { $0.tier == .restricted })
        #expect(!d.parkable.contains { $0.tier == .contractor })
    }
}
