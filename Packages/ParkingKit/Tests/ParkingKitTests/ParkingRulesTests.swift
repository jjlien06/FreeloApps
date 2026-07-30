import Foundation
import Testing
@testable import ParkingKit

/// Detroit-local date builder. Every expectation in this file is written in the
/// wall-clock time a driver would read off their phone in Ann Arbor.
private func detroit(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = ParkingRules.timeZone
    return cal.date(from: c)!
}

private func facility(
    id: String = "test",
    lotId: String? = "T1",
    tier: Tier = .blue,
    kind: Enforcement.Kind = .windows,
    windows: [EnforcementWindow],
    confidence: Confidence = .verified,
    raw: String = "test"
) -> Facility {
    Facility(id: id, lotId: lotId, name: "Test Lot", system: .umich, campus: .central,
             address: nil, lat: nil, lon: nil, tier: tier,
             enforcement: Enforcement(kind: kind, windows: windows, raw: raw),
             confidence: confidence, source: "test", verifiedOn: "2026-07-30",
             capacity: nil, notes: [], availabilityAliases: [])
}

/// Mon-Sat 06:00-17:00, i.e. the real S8 Hill Street Structure pattern.
private let hillStreet = facility(
    id: "umich:S8", lotId: "S8",
    windows: (1...6).map { EnforcementWindow(day: $0, start: "06:00", end: "17:00") },
    raw: "6am – 5pm, Mon – Sat"
)

/// 24 hrs Mon-Sat, the real E8 Church Street Structure pattern. Free only Sunday.
private let churchStreet = facility(
    id: "umich:E8", lotId: "E8",
    windows: (1...6).map { EnforcementWindow(day: $0, start: "00:00", end: "24:00") },
    raw: "24 hrs, Mon – Sat"
)

/// 24/7 - never free. The real N8 Rackham (Gold) pattern.
private let rackham = facility(
    id: "umich:N8", lotId: "N8", tier: .gold,
    windows: (1...7).map { EnforcementWindow(day: $0, start: "00:00", end: "24:00") },
    raw: "24 hrs, 7 days"
)

// MARK: - The basic question: is it free right now?

@Suite("Free / not free")
struct FreeStatusTests {
    let rules = ParkingRules()

    @Test("Enforced during posted hours on a weekday")
    func enforcedMidday() {
        // Wednesday 2026-07-29 at 14:00.
        let status = rules.status(of: hillStreet, at: detroit(2026, 7, 29, 14))
        guard case .restricted(let freeAt) = status else {
            Issue.record("expected restricted, got \(status)")
            return
        }
        #expect(freeAt == detroit(2026, 7, 29, 17))
    }

    @Test("Free the minute enforcement ends")
    func freeAtFive() {
        let status = rules.status(of: hillStreet, at: detroit(2026, 7, 29, 17))
        #expect(status.isFreeToAll)
        // Free until 6am Thursday.
        guard case .freeToAll(let until) = status else { return }
        #expect(until == detroit(2026, 7, 30, 6))
    }

    @Test("Still enforced one minute before the end")
    func enforcedAtFourFiftyNine() {
        #expect(rules.isEnforced(hillStreet, at: detroit(2026, 7, 29, 16, 59)))
        #expect(!rules.isEnforced(hillStreet, at: detroit(2026, 7, 29, 17, 0)))
    }

    @Test("Enforced from the first minute of the window")
    func enforcedAtSix() {
        #expect(!rules.isEnforced(hillStreet, at: detroit(2026, 7, 29, 5, 59)))
        #expect(rules.isEnforced(hillStreet, at: detroit(2026, 7, 29, 6, 0)))
    }

    @Test("Free all day Sunday when the pattern is Mon-Sat")
    func freeAllSunday() {
        // 2026-08-02 is a Sunday.
        let noon = rules.status(of: hillStreet, at: detroit(2026, 8, 2, 12))
        #expect(noon.isFreeToAll)
        let churchNoon = rules.status(of: churchStreet, at: detroit(2026, 8, 2, 12))
        #expect(churchNoon.isFreeToAll)
        // Church is enforced 24h Mon-Sat, so Sunday's free run ends at Monday 00:00.
        guard case .freeToAll(let until) = churchNoon else { return }
        #expect(until == detroit(2026, 8, 3, 0))
    }

    @Test("A 24/7 facility never becomes free")
    func alwaysEnforced() {
        #expect(rules.status(of: rackham, at: detroit(2026, 7, 29, 3)) == .alwaysRestricted)
        #expect(rules.status(of: rackham, at: detroit(2026, 8, 2, 12)) == .alwaysRestricted)
        #expect(rules.nextTransition(rackham, after: detroit(2026, 7, 29, 3)) == nil)
    }

    @Test("neverBecomesFree identifies only the 24/7 facilities")
    func neverFree() {
        #expect(rules.neverBecomesFree(rackham))          // 24 hrs, 7 days
        #expect(!rules.neverBecomesFree(churchStreet))    // free Sundays
        #expect(!rules.neverBecomesFree(hillStreet))      // free every evening

        // Windows that tile a full day in two pieces still count as never free.
        let tiled = facility(windows: (1...7).flatMap {
            [EnforcementWindow(day: $0, start: "00:00", end: "12:00"),
             EnforcementWindow(day: $0, start: "12:00", end: "24:00")]
        })
        #expect(rules.neverBecomesFree(tiled))

        // A one-minute gap means it is not never-free.
        let gap = facility(windows: (1...7).flatMap {
            [EnforcementWindow(day: $0, start: "00:00", end: "11:59"),
             EnforcementWindow(day: $0, start: "12:00", end: "24:00")]
        })
        #expect(!rules.neverBecomesFree(gap))

        // Missing a whole day is not never-free.
        let sixDays = facility(windows: (1...6).map {
            EnforcementWindow(day: $0, start: "00:00", end: "24:00")
        })
        #expect(!rules.neverBecomesFree(sixDays))
    }

    @Test("neverBecomesFree agrees with alwaysRestricted across the real dataset")
    func neverFreeMatchesStatus() throws {
        let data = try Dataset.bundled()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ParkingRules.timeZone
        let base = detroit(2026, 8, 3, 0)  // Monday
        for f in data.facilities where f.confidence == .verified {
            let never = rules.neverBecomesFree(f)
            // Sample the week; a never-free lot must never report free.
            var everFree = false
            for step in 0..<(7 * 24) {
                let t = cal.date(byAdding: .hour, value: step, to: base)!
                if rules.status(of: f, at: t).isFreeToAll { everFree = true; break }
            }
            #expect(never == !everFree,
                    "\(f.id): neverBecomesFree=\(never) but everFree=\(everFree)")
        }
    }

    @Test("Saturday is enforced under Mon-Sat but Sunday is not")
    func saturdayVsSunday() {
        // 2026-08-01 Saturday, 2026-08-02 Sunday.
        #expect(rules.isEnforced(hillStreet, at: detroit(2026, 8, 1, 10)))
        #expect(!rules.isEnforced(hillStreet, at: detroit(2026, 8, 2, 10)))
    }
}

// MARK: - Overnight and multi-day spans

@Suite("Overnight and multi-day windows")
struct SpanTests {
    let rules = ParkingRules()

    /// M93 Wall Street East: "6 am Mon – 1 am Sat" - one continuous span.
    let wallStreetEast = facility(
        id: "umich:M93", lotId: "M93",
        windows: [
            EnforcementWindow(day: 1, start: "06:00", end: "24:00"),
            EnforcementWindow(day: 2, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 3, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 4, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 5, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 6, start: "00:00", end: "01:00")
        ],
        raw: "6 am Mon – 1 am Sat"
    )

    @Test("Free before Monday 6am, enforced after")
    func mondayMorningBoundary() {
        // 2026-08-03 is a Monday.
        #expect(!rules.isEnforced(wallStreetEast, at: detroit(2026, 8, 3, 5, 59)))
        #expect(rules.isEnforced(wallStreetEast, at: detroit(2026, 8, 3, 6, 0)))
    }

    @Test("Enforced continuously through midweek nights")
    func midweekNight() {
        // Wednesday 03:00 - inside the continuous span, not a gap.
        #expect(rules.isEnforced(wallStreetEast, at: detroit(2026, 8, 5, 3)))
    }

    @Test("Becomes free at 1am Saturday and stays free until Monday 6am")
    func saturdayRelease() {
        #expect(rules.isEnforced(wallStreetEast, at: detroit(2026, 8, 8, 0, 59)))
        let status = rules.status(of: wallStreetEast, at: detroit(2026, 8, 8, 1, 0))
        #expect(status.isFreeToAll)
        guard case .freeToAll(let until) = status else {
            Issue.record("expected free, got \(status)")
            return
        }
        #expect(until == detroit(2026, 8, 10, 6))  // Monday 6am
    }

    /// DDA structures: rates Mon-Sat, free Sunday 4am - Monday 4am.
    let ddaStructure = facility(
        id: "dda:library-lane", lotId: nil, tier: .public,
        windows: [
            EnforcementWindow(day: 1, start: "04:00", end: "24:00"),
            EnforcementWindow(day: 2, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 3, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 4, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 5, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 6, start: "00:00", end: "24:00"),
            EnforcementWindow(day: 7, start: "00:00", end: "04:00")
        ],
        raw: "Rates Mon-Sat; free Sunday 4am-Monday 4am"
    )

    @Test("Downtown structure: the Sunday 4am boundary, from both sides")
    func sundayFourAM() {
        // 2026-08-02 Sunday.
        #expect(rules.isEnforced(ddaStructure, at: detroit(2026, 8, 2, 3, 59)))
        #expect(!rules.isEnforced(ddaStructure, at: detroit(2026, 8, 2, 4, 0)))
        // And the far end: free until Monday 04:00.
        let status = rules.status(of: ddaStructure, at: detroit(2026, 8, 2, 12))
        guard case .freeToAll(let until) = status else {
            Issue.record("expected free, got \(status)")
            return
        }
        #expect(until == detroit(2026, 8, 3, 4))
    }

    @Test("Downtown structure is enforced on a Saturday evening")
    func saturdayEvening() {
        #expect(rules.isEnforced(ddaStructure, at: detroit(2026, 8, 1, 20)))
    }
}

// MARK: - Daylight saving

@Suite("Daylight saving transitions")
struct DSTTests {
    let rules = ParkingRules()

    // US DST 2027: forward Sun Mar 14, back Sun Nov 7.
    // Both are Sundays, so pair them with a Mon-Sat facility (free that day) and
    // with a 7-day facility to check the arithmetic either way.

    @Test("Spring forward: the following Monday still starts enforcement at 6am")
    func springForward() {
        // Sunday 2027-03-14 is the transition; Monday 2027-03-15 is normal.
        #expect(!rules.isEnforced(hillStreet, at: detroit(2027, 3, 15, 5, 59)))
        #expect(rules.isEnforced(hillStreet, at: detroit(2027, 3, 15, 6, 0)))
        // Sunday itself is free under a Mon-Sat pattern.
        #expect(rules.status(of: hillStreet, at: detroit(2027, 3, 14, 12)).isFreeToAll)
    }

    @Test("Fall back: Monday boundary is still 6am wall-clock")
    func fallBack() {
        #expect(!rules.isEnforced(hillStreet, at: detroit(2027, 11, 8, 5, 59)))
        #expect(rules.isEnforced(hillStreet, at: detroit(2027, 11, 8, 6, 0)))
    }

    @Test("nextTransition lands on wall-clock 6am across a spring-forward weekend")
    func transitionAcrossSpringForward() {
        // Saturday 2027-03-13 17:00 -> free until Monday 06:00 local.
        let status = rules.status(of: hillStreet, at: detroit(2027, 3, 13, 17))
        guard case .freeToAll(let until) = status, let until else {
            Issue.record("expected free with an end time, got \(status)")
            return
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ParkingRules.timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: until)
        #expect(c.year == 2027 && c.month == 3 && c.day == 15)
        #expect(c.hour == 6 && c.minute == 0)
    }
}

// MARK: - Permits

@Suite("Permit handling")
struct PermitTests {
    let rules = ParkingRules()

    @Test("Blue permit gets into a Blue lot during enforcement")
    func bluePermitBlueLot() {
        let status = rules.status(of: hillStreet, at: detroit(2026, 7, 29, 14), permit: .blue)
        #expect(status == .allowedWithPermit(.blue))
        #expect(status.isUsableNow)
        #expect(!status.isFreeToAll)  // usable is not the same as free
    }

    @Test("Blue permit does not get into a Gold lot")
    func bluePermitGoldLot() {
        let status = rules.status(of: rackham, at: detroit(2026, 7, 29, 14), permit: .blue)
        #expect(status == .alwaysRestricted)
    }

    @Test("Gold permit is honoured in Gold and in the colour tiers")
    func goldPermit() {
        #expect(rules.status(of: rackham, at: detroit(2026, 7, 29, 14), permit: .gold)
                == .allowedWithPermit(.gold))
        #expect(rules.status(of: hillStreet, at: detroit(2026, 7, 29, 14), permit: .gold)
                == .allowedWithPermit(.gold))
    }

    @Test("Yellow permit does not open a Blue lot")
    func yellowInBlue() {
        guard case .restricted = rules.status(of: hillStreet,
                                              at: detroit(2026, 7, 29, 14),
                                              permit: .yellow) else {
            Issue.record("yellow should not be honoured in a Blue lot")
            return
        }
    }

    @Test("After Hours permit is inactive midday, active in the evening")
    func afterHoursWindow() {
        // Wednesday 10:00 - outside the After Hours window.
        #expect(!rules.afterHoursPermitActive(at: detroit(2026, 7, 29, 10)))
        // Wednesday 15:00 - the window opens.
        #expect(rules.afterHoursPermitActive(at: detroit(2026, 7, 29, 15)))
        // Saturday and Sunday are 24 hours.
        #expect(rules.afterHoursPermitActive(at: detroit(2026, 8, 1, 10)))
        #expect(rules.afterHoursPermitActive(at: detroit(2026, 8, 2, 10)))
        // 04:59 Wednesday is still inside the overnight run.
        #expect(rules.afterHoursPermitActive(at: detroit(2026, 7, 29, 4, 59)))
    }

    @Test("After Hours permit opens a Blue structure that is enforced 24h Mon-Sat")
    func afterHoursOnChurch() {
        // Church St is enforced 24h Mon-Sat. At 20:00 Wednesday an After Hours
        // permit is honoured; at 10:00 it is not.
        #expect(rules.status(of: churchStreet, at: detroit(2026, 7, 29, 20), permit: .afterHours)
                == .allowedWithPermit(.afterHours))
        guard case .restricted = rules.status(of: churchStreet,
                                              at: detroit(2026, 7, 29, 10),
                                              permit: .afterHours) else {
            Issue.record("After Hours should not apply at 10am on a weekday")
            return
        }
    }

    @Test("After Hours permit is never honoured in Gold")
    func afterHoursNotGold() {
        #expect(rules.status(of: rackham, at: detroit(2026, 7, 29, 22), permit: .afterHours)
                == .alwaysRestricted)
    }
}

// MARK: - The trust gate

@Suite("Unverified data is never reported as free")
struct TrustTests {
    let rules = ParkingRules()

    @Test("Unparseable hours yield unknown, not free")
    func unknownKind() {
        let f = facility(kind: .unknown, windows: [], raw: "NA")
        let status = rules.status(of: f, at: detroit(2026, 8, 2, 12))
        guard case .unknown = status else {
            Issue.record("expected unknown, got \(status)")
            return
        }
        #expect(!status.isFreeToAll)
    }

    @Test("Assumed confidence yields unknown even when no window covers the time")
    func assumedConfidence() {
        // A window set that would otherwise read as free on Sunday.
        let f = facility(
            windows: (1...6).map { EnforcementWindow(day: $0, start: "06:00", end: "17:00") },
            confidence: .assumed
        )
        let status = rules.status(of: f, at: detroit(2026, 8, 2, 12))
        guard case .unknown = status else {
            Issue.record("assumed data must not read as free; got \(status)")
            return
        }
    }

    @Test("No facility with non-verified confidence can ever report free")
    func exhaustiveTrustGate() throws {
        let data = try Dataset.bundled()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ParkingRules.timeZone
        let base = detroit(2026, 8, 3, 0)  // a Monday
        // Sample every 30 minutes across a full week.
        for step in stride(from: 0, to: 7 * 24 * 2, by: 1) {
            let t = cal.date(byAdding: .minute, value: step * 30, to: base)!
            for f in data.facilities where f.confidence != .verified {
                #expect(!rules.status(of: f, at: t).isFreeToAll,
                        "\(f.id) reported free at \(t) despite confidence \(f.confidence)")
            }
        }
    }
}

// MARK: - Ranking

@Suite("Ranking and distance")
struct RankingTests {
    let rules = ParkingRules()

    @Test("Free facilities rank above restricted ones")
    func freeFirst() {
        let ranked = rules.ranked([rackham, hillStreet], at: detroit(2026, 7, 29, 18))
        #expect(ranked.first?.0.id == "umich:S8")
        #expect(ranked.first?.1.isFreeToAll == true)
        #expect(ranked.last?.0.id == "umich:N8")
    }

    @Test("Within the same status, nearer sorts first")
    func nearerFirst() {
        let near = Facility(id: "near", lotId: "A1", name: "Near", system: .umich,
                            campus: .central, address: nil, lat: 42.2780, lon: -83.7382,
                            tier: .blue,
                            enforcement: Enforcement(kind: .windows, windows: [], raw: "none"),
                            confidence: .verified, source: "t", verifiedOn: "2026-07-30",
                            capacity: nil, notes: [], availabilityAliases: [])
        let far = Facility(id: "far", lotId: "A2", name: "Far", system: .umich,
                           campus: .north, address: nil, lat: 42.2960, lon: -83.7180,
                           tier: .blue,
                           enforcement: Enforcement(kind: .windows, windows: [], raw: "none"),
                           confidence: .verified, source: "t", verifiedOn: "2026-07-30",
                           capacity: nil, notes: [], availabilityAliases: [])
        let ranked = rules.ranked([far, near], at: detroit(2026, 7, 29, 12),
                                  from: (lat: 42.2780, lon: -83.7382))
        #expect(ranked.first?.0.id == "near")
    }

    @Test("Haversine distance is sane for a known campus pair")
    func distanceSanity() {
        // Church St Structure to Thompson St Structure is roughly 800m.
        let d = ParkingRules.metres(from: (42.2757, -83.7371), to: (42.2765, -83.7440))
        #expect(d > 400 && d < 900)
    }
}
