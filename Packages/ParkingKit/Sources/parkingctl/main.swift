import Foundation
import ParkingKit

// A terminal view of the rules engine, so its answers can be checked against
// the LTP pages (and against an entrance sign) without launching a simulator.
//
//   swift run parkingctl                       what is free right now
//   swift run parkingctl --at "2026-08-03 20:00"
//   swift run parkingctl --permit blue
//   swift run parkingctl --lot S8              one facility's whole week
//   swift run parkingctl --live                fetch live occupancy

let args = CommandLine.arguments

func flag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let rules = ParkingRules()
var cal = Calendar(identifier: .gregorian)
cal.timeZone = ParkingRules.timeZone

let data: Dataset
do {
    data = try Dataset.bundled()
} catch {
    print("could not load dataset: \(error)")
    exit(1)
}

// ---- when
var when = Date()
if let s = flag("--at") {
    let fmt = DateFormatter()
    fmt.timeZone = ParkingRules.timeZone
    fmt.dateFormat = s.contains(":") && s.contains("-") ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
    guard let d = fmt.date(from: s) else {
        print("could not parse --at \(s); expected \"yyyy-MM-dd HH:mm\"")
        exit(1)
    }
    when = d
}

let permit = PermitClass(rawValue: flag("--permit") ?? "none") ?? .none

let stamp = DateFormatter()
stamp.timeZone = ParkingRules.timeZone
stamp.dateFormat = "EEE yyyy-MM-dd HH:mm"

let clock = DateFormatter()
clock.timeZone = ParkingRules.timeZone
clock.dateFormat = "EEE HH:mm"

func describe(_ s: ParkingStatus) -> String {
    switch s {
    case .freeToAll(let until):
        return until.map { "FREE      until \(clock.string(from: $0))" } ?? "FREE      (no end)"
    case .allowedWithPermit(let p):
        return "PERMIT OK (\(p.label))"
    case .restricted(let freeAt):
        return freeAt.map { "paid/permit → free \(clock.string(from: $0))" } ?? "paid/permit"
    case .alwaysRestricted:
        return "never free (24/7)"
    case .unknown(let reason):
        return "unknown   (\(reason.prefix(48)))"
    }
}

// ---- single lot: print its whole week
if let lot = flag("--lot") {
    guard let f = data.facility(lotId: lot) else {
        print("no facility with lot id \(lot)")
        exit(1)
    }
    print("\(f.displayTitle)")
    print("  tier \(f.tier.label) · \(f.campus.label) · confidence \(f.confidence.rawValue)")
    print("  LTP hours: \(f.enforcement.raw)")
    print("  source:    \(f.source)")
    for n in f.notes { print("  note:      \(n)") }
    print("\n  hour-by-hour, Monday 00:00 onward:")
    // Walk from the Monday of the current week.
    let weekday = rules.isoWeekday(when)
    let monday = cal.date(byAdding: .day, value: -(weekday - 1),
                          to: cal.startOfDay(for: when))!
    for day in 0..<7 {
        let dayStart = cal.date(byAdding: .day, value: day, to: monday)!
        var line = ""
        for hour in 0..<24 {
            let t = cal.date(byAdding: .hour, value: hour, to: dayStart)!
            line += rules.isEnforced(f, at: t) ? "#" : "."
        }
        let name = clock.string(from: dayStart).prefix(3)
        print("    \(name) \(line)")
    }
    print("    key: # = permit/payment required, . = free to all")
    print("         columns are hours 00..23")
    exit(0)
}

func column(_ s: String, _ width: Int) -> String {
    let clipped = s.count > width ? String(s.prefix(width - 1)) + "…" : s
    return clipped + String(repeating: " ", count: max(0, width - clipped.count))
}

// ---- live occupancy
func showLive(_ data: Dataset) async {
    let client = LiveAvailabilityClient()
    do {
        let snap = try await client.fetchLTP()
        print("U-M occupancy  (LTP last update: \(snap.lastUpdate ?? "unknown"))")
        let index = AvailabilityMatcher.index(readings: snap.readings,
                                             facilities: data.facilities,
                                             aliases: data.availabilityAliases)
        for r in snap.readings {
            let ids = AvailabilityMatcher.lotIds(for: r.label, aliases: data.availabilityAliases)
            let linked = ids.compactMap { data.facility(lotId: $0)?.id }
            print("  " + column(r.label, 44) + column(r.tier.label, 8)
                  + column("\(r.percent)%", 6)
                  + "→ " + (linked.isEmpty ? "unmatched" : linked.joined(separator: ", ")))
        }
        print("  matched \(index.count) of \(snap.readings.count) rows to facilities")
    } catch {
        print("LTP fetch failed: \(error.localizedDescription)")
    }
    do {
        let counts = try await client.fetchDDACounts()
        print("\nDowntown DDA live counts")
        for c in counts.sorted(by: { $0.facilityKey < $1.facilityKey }) {
            print("  facility " + column(c.facilityKey, 6)
                  + column("\(c.spacesAvailable) spaces", 14) + "(\(c.timestamp))")
        }
        print("  note: DDA publishes no key→name mapping; see tools/verify_dda_mapping.py")
    } catch {
        print("DDA fetch failed: \(error.localizedDescription)")
    }
}

if args.contains("--live") {
    // Top-level `await`, not Task + semaphore: top-level code is @MainActor, so a
    // Task would inherit the main actor and a blocking wait would deadlock it.
    await showLive(data)
    exit(0)
}

// ---- the main list
print("MParking — \(stamp.string(from: when))  (permit: \(permit.label))")
print(String(repeating: "─", count: 78))

let ranked = rules.ranked(data.parkable, at: when, permit: permit)
let free = ranked.filter { $0.1.isFreeToAll }
let permitOK = ranked.filter { if case .allowedWithPermit = $0.1 { return true }; return false }
let rest = ranked.filter { !$0.1.isFreeToAll && !$0.1.isUsableNow }

func section(_ title: String, _ rows: [(Facility, ParkingStatus, Double?)], limit: Int) {
    guard !rows.isEmpty else { return }
    print("\n\(title)  (\(rows.count))")
    for (f, s, _) in rows.prefix(limit) {
        print("  " + column(f.displayTitle, 46) + column(f.tier.label, 13) + describe(s))
    }
    if rows.count > limit { print("  … and \(rows.count - limit) more") }
}

section("FREE TO ALL RIGHT NOW", free, limit: 20)
section("OPEN WITH YOUR PERMIT", permitOK, limit: 10)
section("PERMIT OR PAYMENT REQUIRED", rest, limit: 10)

let unknown = ranked.filter { if case .unknown = $0.1 { return true }; return false }
if !unknown.isEmpty {
    print("\nUNVERIFIED — check the sign  (\(unknown.count))")
}

print("\n\(data.caveat)")
print("dataset generated \(data.generated), \(data.facilities.count) facilities")
