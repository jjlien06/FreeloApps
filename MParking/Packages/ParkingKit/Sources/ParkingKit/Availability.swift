import Foundation

/// One occupancy figure scraped from LTP's Parking Space Availability page.
public struct OccupancyReading: Sendable, Equatable {
    /// The row label exactly as LTP prints it, e.g. "E8 Church St. Structure".
    public let label: String
    /// Which permit tier the figure describes.
    public let tier: Tier
    /// 0...100. LTP calls this an *estimate* derived from permit activity.
    public let percent: Int

    public init(label: String, tier: Tier, percent: Int) {
        self.label = label
        self.tier = tier
        self.percent = percent
    }
}

/// A live space count from the Ann Arbor DDA feed.
public struct SpaceCount: Sendable, Equatable {
    /// The DDA's opaque facility key, e.g. "86" or "87 S".
    public let facilityKey: String
    public let spacesAvailable: Int
    public let timestamp: String

    public init(facilityKey: String, spacesAvailable: Int, timestamp: String) {
        self.facilityKey = facilityKey
        self.spacesAvailable = spacesAvailable
        self.timestamp = timestamp
    }
}

public struct AvailabilitySnapshot: Sendable {
    public let readings: [OccupancyReading]
    public let lastUpdate: String?
    public let fetchedAt: Date

    public init(readings: [OccupancyReading], lastUpdate: String?, fetchedAt: Date) {
        self.readings = readings
        self.lastUpdate = lastUpdate
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Parsing (pure, so it can be tested against saved fixtures)

public enum AvailabilityParser {

    /// Pull `(label, percent)` pairs and the tier heading out of LTP's HTML.
    ///
    /// The page is server-rendered and its row set changes through the day -
    /// facilities with no current data simply vanish - so this never assumes a
    /// fixed roster. It keys off the "<tier> Occupancy" column header that
    /// precedes each block of rows.
    public static func parseLTP(html: String) -> AvailabilitySnapshot {
        var readings: [OccupancyReading] = []
        var currentTier: Tier = .blue

        // Walk the row-ish chunks in document order so the tier header that
        // precedes a block of rows applies to that block.
        let rowPattern = #"<t[dh][^>]*>(.*?)</t[dh]>"#
        let cells = matches(rowPattern, in: html).map { stripTags($0) }

        var index = 0
        while index < cells.count {
            let cell = cells[index]

            if let tier = tierFromHeader(cell) {
                currentTier = tier
                index += 1
                continue
            }

            // A label cell followed by a percentage cell.
            if index + 1 < cells.count,
               let pct = percentValue(cells[index + 1]),
               !cell.isEmpty,
               percentValue(cell) == nil {
                readings.append(OccupancyReading(label: cell, tier: currentTier, percent: pct))
                index += 2
                continue
            }
            index += 1
        }

        var lastUpdate: String?
        if let m = firstMatch(#"Last Update:\s*([^<\n]+)"#, in: html, group: 1) {
            lastUpdate = m.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return AvailabilitySnapshot(readings: readings, lastUpdate: lastUpdate, fetchedAt: Date())
    }

    static func tierFromHeader(_ text: String) -> Tier? {
        let t = text.lowercased()
        guard t.contains("occupancy") else { return nil }
        if t.contains("blue") { return .blue }
        if t.contains("gold") { return .gold }
        if t.contains("yellow") { return .yellow }
        if t.contains("orange") { return .orange }
        return nil
    }

    static func percentValue(_ text: String) -> Int? {
        guard let s = firstMatch(#"^\s*(\d{1,3})\s*%\s*$"#, in: text, group: 1),
              let v = Int(s), v >= 0, v <= 100 else { return nil }
        return v
    }

    /// Parse the DDA live-count JSON.
    public static func parseDDA(json data: Data) throws -> [SpaceCount] {
        struct Payload: Decodable {
            struct Row: Decodable {
                let facility: String
                let spacesavail: String
                let timestamp: String
            }
            let countdata: [Row]
        }
        let p = try JSONDecoder().decode(Payload.self, from: data)
        return p.countdata.compactMap { row in
            // The live feed does occasionally emit negative counts (observed
            // "-7" on facility 84), which means the sensor tally has drifted.
            // A negative is not a number of spaces, and reporting it as 0 would
            // assert "full" without grounds - so drop the row and show no live
            // figure for that facility.
            guard let n = Int(row.spacesavail), n >= 0 else { return nil }
            return SpaceCount(facilityKey: row.facility,
                              spacesAvailable: n,
                              timestamp: row.timestamp)
        }
    }

    // MARK: regex helpers

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                                options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : ns.substring(with: $0.range)
        }
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                                options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    static func stripTags(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ",
                                          options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&#8211;", "-"),
                               ("&#8217;", "'"), ("&quot;", "\"")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Matching readings to facilities

public enum AvailabilityMatcher {
    /// Resolve an LTP row label to the lot ids it refers to.
    ///
    /// Alias table first: "P1 Parking Structure" must map to M15, and its leading
    /// token would otherwise be misread as a lot id.
    public static func lotIds(for label: String, aliases: [String: [String]]) -> [String] {
        if let mapped = aliases[label] { return mapped }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if let token = AvailabilityParser.firstMatch(#"^((?:NC|SC|NW|EC|[NEWSMC])\d{1,3})\b"#,
                                                     in: trimmed, group: 1) {
            return [token]
        }
        return []
    }

    /// Index readings by facility id for a given dataset.
    public static func index(readings: [OccupancyReading],
                            facilities: [Facility],
                            aliases: [String: [String]]) -> [String: OccupancyReading] {
        var byLot: [String: Facility] = [:]
        for f in facilities {
            if let lot = f.lotId { byLot[lot] = f }
        }
        var out: [String: OccupancyReading] = [:]
        for r in readings {
            for lot in lotIds(for: r.label, aliases: aliases) {
                if let f = byLot[lot] {
                    // Prefer the tier the facility actually is, if several tiers
                    // are published for it.
                    if let existing = out[f.id], existing.tier == f.tier { continue }
                    out[f.id] = r
                }
            }
        }
        return out
    }
}

// MARK: - Network

public protocol AvailabilityFetching: Sendable {
    func fetchLTP() async throws -> AvailabilitySnapshot
    func fetchDDACounts() async throws -> [SpaceCount]
}

public struct LiveAvailabilityClient: AvailabilityFetching {
    public static let ltpURL = URL(string: "https://ltp.umich.edu/parking/parking-space-availability/?tier=both")!
    public static let ddaURL = URL(string: "https://www.a2dda.org/map/AADDACount.json")!

    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// LTP sits behind Cloudflare, which scores clients partly on how ordinary
    /// they look and partly on request rate. A browser-shaped User-Agent gets
    /// through; hammering the endpoint earns intermittent 403s. Poll sparingly
    /// and treat a 403 as "try again later", not as an error worth surfacing.
    func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
                   + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                   forHTTPHeaderField: "User-Agent")
        r.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
                   forHTTPHeaderField: "Accept")
        r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        r.timeoutInterval = 20
        return r
    }

    public enum ClientError: Error, LocalizedError {
        case throttled
        case badStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .throttled: "U-M's availability page is rate-limiting requests. Showing the last known figures."
            case .badStatus(let c): "Availability request failed (HTTP \(c))."
            }
        }
    }

    public func fetchLTP() async throws -> AvailabilitySnapshot {
        let (data, response) = try await session.data(for: request(Self.ltpURL))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 403 ? ClientError.throttled : ClientError.badStatus(http.statusCode)
        }
        return AvailabilityParser.parseLTP(html: String(decoding: data, as: UTF8.self))
    }

    public func fetchDDACounts() async throws -> [SpaceCount] {
        let (data, response) = try await session.data(for: request(Self.ddaURL))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClientError.badStatus(http.statusCode)
        }
        return try AvailabilityParser.parseDDA(json: data)
    }
}
