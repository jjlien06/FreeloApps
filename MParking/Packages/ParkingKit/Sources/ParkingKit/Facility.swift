import Foundation

/// Which parking authority owns a facility. They have completely different rules.
public enum ParkingSystem: String, Codable, Sendable, CaseIterable {
    case umich
    case dda

    public var label: String {
        switch self {
        case .umich: "U-M"
        case .dda: "Downtown"
        }
    }
}

public enum Campus: String, Codable, Sendable, CaseIterable {
    case central, medical, north, athletic, downtown

    public var label: String {
        switch self {
        case .central: "Central Campus"
        case .medical: "Medical Campus"
        case .north: "North Campus"
        case .athletic: "Ross Athletic"
        case .downtown: "Downtown Ann Arbor"
        }
    }
}

/// U-M permit tiers, plus the pseudo-tier `public` for city facilities.
///
/// The tier controls *who* may park during enforcement hours. It has no bearing
/// on whether a facility is free outside those hours - once the gates go up,
/// tier stops mattering.
public enum Tier: String, Codable, Sendable, CaseIterable {
    case blue, gold, yellow, orange, visitor, restricted
    case parkAndRide, contractor, other
    case `public`

    public var label: String {
        switch self {
        case .blue: "Blue"
        case .gold: "Gold"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .visitor: "Visitor"
        case .restricted: "Restricted"
        case .parkAndRide: "Park & Ride"
        case .contractor: "Contractor"
        case .other: "Other"
        case .public: "Public / paid"
        }
    }
}

/// What the user holds. Drives whether a facility reads as usable *to them*
/// during enforcement hours.
public enum PermitClass: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, blue, gold, yellow, orange, afterHours

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: "No permit"
        case .blue: "Blue"
        case .gold: "Gold"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .afterHours: "After Hours"
        }
    }

    /// Tiers this permit is honoured in during enforcement hours.
    ///
    /// Gold is the most privileged tier and is honoured in the colour-coded
    /// areas as well. The After Hours permit is honoured in Blue/Yellow/Orange
    /// but never Gold - and only in its own time window, which is handled
    /// separately in `ParkingRules` because it is time-bounded, not tier-bounded.
    var honouredTiers: Set<Tier> {
        switch self {
        case .none: []
        case .blue: [.blue]
        case .gold: [.gold, .blue, .yellow, .orange]
        case .yellow: [.yellow]
        case .orange: [.orange]
        case .afterHours: [.blue, .yellow, .orange]
        }
    }
}

/// How much we trust this facility's hours. Anything below `verified` must never
/// be presented as free - a wrong "free" costs the user a ticket.
public enum Confidence: String, Codable, Sendable {
    case verified   // transcribed from LTP / DDA published hours
    case community  // credible field report, not yet confirmed by the publisher
    case assumed    // inferred; conservative window applied
    case unknown    // source published no usable hours
}

/// A single-day enforcement window. Multi-day and overnight spans are split
/// across days when the dataset is generated, so `start < end` always holds and
/// no wrap-around arithmetic is needed here.
public struct EnforcementWindow: Codable, Sendable, Hashable {
    /// ISO weekday: 1 = Monday ... 7 = Sunday.
    public let day: Int
    /// "HH:MM"
    public let start: String
    /// "HH:MM", or "24:00" for end-of-day.
    public let end: String

    public init(day: Int, start: String, end: String) {
        self.day = day
        self.start = start
        self.end = end
    }

    var startMinutes: Int { Self.minutes(start) }
    var endMinutes: Int { Self.minutes(end) }

    static func minutes(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
        return h * 60 + m
    }

    /// Half-open: a window ending at 17:00 does not cover 17:00 itself.
    func covers(minuteOfDay: Int) -> Bool {
        minuteOfDay >= startMinutes && minuteOfDay < endMinutes
    }
}

public struct Enforcement: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case windows
        case unknown
    }

    public let kind: Kind
    public let windows: [EnforcementWindow]
    /// The original LTP/DDA text, kept so the UI can always show the source wording.
    public let raw: String
}

public struct Facility: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    /// U-M lot number, e.g. "E8". Nil for city facilities.
    public let lotId: String?
    public let name: String
    public let system: ParkingSystem
    public let campus: Campus
    public let address: String?
    public let lat: Double?
    public let lon: Double?
    public let tier: Tier
    public let enforcement: Enforcement
    public let confidence: Confidence
    public let source: String
    public let verifiedOn: String
    public let capacity: Int?
    public let notes: [String]
    /// Labels used by LTP's availability page for this facility, when they differ
    /// from the lot id.
    public let availabilityAliases: [String]

    public static func == (a: Facility, b: Facility) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    /// "E8 · Church Street Parking Structure"
    public var displayTitle: String {
        if let lotId { "\(lotId) · \(name)" } else { name }
    }
}

/// The bundled dataset, plus its provenance.
public struct Dataset: Codable, Sendable {
    public let version: Int
    public let generated: String
    public let timeZone: String
    public let caveat: String
    public let sources: [String: String]
    public let availabilityAliases: [String: [String]]
    public let facilities: [Facility]
}
