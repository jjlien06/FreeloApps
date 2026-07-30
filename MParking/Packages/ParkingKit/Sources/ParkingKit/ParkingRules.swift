import Foundation

/// What a facility means for the user at a given moment.
public enum ParkingStatus: Sendable, Equatable {
    /// Gates are up / no payment due. Anyone may park. `until` is when that ends.
    case freeToAll(until: Date?)
    /// Enforced right now, but the user's permit is honoured here.
    case allowedWithPermit(PermitClass)
    /// Enforced and the user's permit does not cover it. `freeAt` is when it opens up.
    case restricted(freeAt: Date?)
    /// Enforced every hour of every day - it never becomes free.
    case alwaysRestricted
    /// Source data is missing or untrustworthy. Never claim this is free.
    case unknown(reason: String)

    /// True only when the user can park without a permit and without paying.
    public var isFreeToAll: Bool {
        if case .freeToAll = self { return true }
        return false
    }

    /// True when the user can park here now, by any means.
    public var isUsableNow: Bool {
        switch self {
        case .freeToAll, .allowedWithPermit: true
        case .restricted, .alwaysRestricted, .unknown: false
        }
    }

    public var sortRank: Int {
        switch self {
        case .freeToAll: 0
        case .allowedWithPermit: 1
        case .restricted: 2
        case .alwaysRestricted: 3
        case .unknown: 4
        }
    }
}

public struct ParkingRules: Sendable {
    /// U-M and the DDA both operate on Detroit local time, including DST.
    public static let timeZone = TimeZone(identifier: "America/Detroit")!

    public var calendar: Calendar

    public init(timeZone: TimeZone = ParkingRules.timeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
    }

    // MARK: - Core

    /// ISO weekday: 1 = Monday ... 7 = Sunday.
    public func isoWeekday(_ date: Date) -> Int {
        // Calendar's .weekday is 1 = Sunday ... 7 = Saturday.
        let w = calendar.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Is payment or a permit required at this instant?
    public func isEnforced(_ facility: Facility, at date: Date) -> Bool {
        guard facility.enforcement.kind == .windows else { return false }
        let day = isoWeekday(date)
        let minute = minuteOfDay(date)
        return facility.enforcement.windows.contains {
            $0.day == day && $0.covers(minuteOfDay: minute)
        }
    }

    /// The next instant at which `isEnforced` flips. Nil if it never does
    /// (always enforced, never enforced, or no data).
    ///
    /// Coverage can only change at a window boundary, so we evaluate the
    /// boundaries themselves rather than stepping through time.
    public func nextTransition(_ facility: Facility, after date: Date) -> Date? {
        let windows = facility.enforcement.windows
        guard facility.enforcement.kind == .windows, !windows.isEmpty else { return nil }

        let current = isEnforced(facility, at: date)
        guard let dayStart = calendar.dateInterval(of: .day, for: date)?.start else { return nil }

        var candidates: [Date] = []
        // 8 days covers any weekly pattern from any starting point.
        for offset in 0...8 {
            guard let base = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let day = isoWeekday(base)
            for w in windows where w.day == day {
                for minutes in [w.startMinutes, w.endMinutes] {
                    // Build the boundary from calendar components so DST shifts
                    // resolve the way the calendar says they do.
                    guard let t = calendar.date(byAdding: .minute, value: minutes, to: base) else { continue }
                    if t > date { candidates.append(t) }
                }
            }
        }

        for t in candidates.sorted() where isEnforced(facility, at: t) != current {
            return t
        }
        return nil
    }

    /// True when a facility is enforced every hour of every day, so it never opens
    /// up to people without a permit.
    ///
    /// This is a property of the facility, not of the user: a Gold lot is still
    /// "never free" even to someone holding a Gold permit, because a permit makes
    /// it *usable*, not free. Filtering on this is what lets someone hide the
    /// lots that will never be an option for them.
    public func neverBecomesFree(_ facility: Facility) -> Bool {
        guard facility.enforcement.kind == .windows else { return false }
        let windows = facility.enforcement.windows
        guard !windows.isEmpty else { return false }

        // Every day must be covered from 00:00 to 24:00 by the union of its
        // windows. Merge each day's intervals and check for a single full span.
        for day in 1...7 {
            let spans = windows.filter { $0.day == day }
                .map { ($0.startMinutes, $0.endMinutes) }
                .sorted { $0.0 < $1.0 }
            guard !spans.isEmpty else { return false }

            var reached = 0
            for (start, end) in spans {
                if start > reached { return false }   // a gap - it is free then
                reached = max(reached, end)
            }
            if reached < 24 * 60 { return false }
        }
        return true
    }

    // MARK: - After Hours permit

    /// The After Hours permit is honoured in Blue/Yellow/Orange areas (never
    /// Gold) from 3pm to 5am Mon-Fri, and 24 hours Sat-Sun. Equivalently: active
    /// at all times *except* Mon-Fri 05:00-15:00.
    public func afterHoursPermitActive(at date: Date) -> Bool {
        let day = isoWeekday(date)
        guard (1...5).contains(day) else { return true }
        let m = minuteOfDay(date)
        return !(m >= 5 * 60 && m < 15 * 60)
    }

    // MARK: - Status

    public func status(of facility: Facility,
                      at date: Date,
                      permit: PermitClass = .none) -> ParkingStatus {
        // Trust gate: anything we are not sure about must not read as free.
        if facility.enforcement.kind == .unknown {
            return .unknown(reason: facility.enforcement.raw.isEmpty
                            ? "LTP publishes no enforcement hours for this lot."
                            : "Unparsed hours: \(facility.enforcement.raw)")
        }
        if facility.confidence != .verified {
            return .unknown(reason: facility.notes.first
                            ?? "Hours for this facility are not verified.")
        }

        if !isEnforced(facility, at: date) {
            return .freeToAll(until: nextTransition(facility, after: date))
        }

        // Enforced. Does the user's permit get them in?
        if permit != .none {
            let honoured = permit == .afterHours
                ? (afterHoursPermitActive(at: date) && permit.honouredTiers.contains(facility.tier))
                : permit.honouredTiers.contains(facility.tier)
            if honoured {
                return .allowedWithPermit(permit)
            }
        }

        if let freeAt = nextTransition(facility, after: date) {
            return .restricted(freeAt: freeAt)
        }
        return .alwaysRestricted
    }

    /// Status for every facility, ranked: free first, then by distance when known.
    public func ranked(_ facilities: [Facility],
                       at date: Date,
                       permit: PermitClass = .none,
                       from origin: (lat: Double, lon: Double)? = nil) -> [(Facility, ParkingStatus, Double?)] {
        facilities
            .map { f -> (Facility, ParkingStatus, Double?) in
                var distance: Double?
                if let origin, let lat = f.lat, let lon = f.lon {
                    distance = Self.metres(from: origin, to: (lat, lon))
                }
                return (f, status(of: f, at: date, permit: permit), distance)
            }
            .sorted { a, b in
                if a.1.sortRank != b.1.sortRank { return a.1.sortRank < b.1.sortRank }
                switch (a.2, b.2) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.0.name < b.0.name
                }
            }
    }

    /// Great-circle distance in metres. Plain haversine - CoreLocation is not
    /// available on every platform this package builds for.
    public static func metres(from a: (lat: Double, lon: Double),
                              to b: (lat: Double, lon: Double)) -> Double {
        let r = 6_371_000.0
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180
        let dp = p2 - p1
        let dl = (b.lon - a.lon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
