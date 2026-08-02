import Foundation

/// The cull decision for a photo. Independent of its star score.
public enum Verdict: String, Codable, Sendable, CaseIterable {
    case pass
    case fail
}

/// What is recorded about one photo.
///
/// `verdict` and `stars` are deliberately independent: a shot can be a keeper
/// that is only worth two stars, or a four-star frame that still gets cut.
public struct Rating: Codable, Hashable, Sendable {
    public var verdict: Verdict?
    public var stars: Int
    public var note: String?

    public init(verdict: Verdict? = nil, stars: Int = 0, note: String? = nil) {
        self.verdict = verdict
        self.stars = Rating.clamp(stars)
        self.note = note
    }

    /// True when nothing has been recorded, so the store can drop the entry
    /// instead of writing empty rows to the sidecar.
    public var isEmpty: Bool {
        verdict == nil && stars == 0 && (note?.isEmpty ?? true)
    }

    public static func clamp(_ stars: Int) -> Int { min(max(stars, 0), 5) }

    /// Lenient by design: a sidecar written by a future version (or hand-edited)
    /// should degrade to "unrated" for that field rather than failing the whole
    /// folder's ratings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = (try container.decodeIfPresent(String.self, forKey: .verdict))
            .flatMap(Verdict.init(rawValue:))
        stars = Rating.clamp(try container.decodeIfPresent(Int.self, forKey: .stars) ?? 0)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}
