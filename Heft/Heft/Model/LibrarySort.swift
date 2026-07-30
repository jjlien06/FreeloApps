import Foundation
import Photos

enum SortOrder: String, CaseIterable, Identifiable {
    case largestFirst
    case smallestFirst
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .largestFirst: "Largest first"
        case .smallestFirst: "Smallest first"
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        }
    }

    var symbol: String {
        switch self {
        case .largestFirst: "arrow.down.to.line"
        case .smallestFirst: "arrow.up.to.line"
        case .newestFirst: "clock"
        case .oldestFirst: "clock.arrow.circlepath"
        }
    }

    /// Size orders are only meaningful once the index has run.
    var needsSizes: Bool {
        self == .largestFirst || self == .smallestFirst
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case videos
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .photos: "Photos"
        case .videos: "Videos"
        case .raw: "RAW"
        }
    }

    /// RAW-ness isn't expressible as a `PHFetchOptions` predicate — it comes from
    /// inspecting each asset's resources — so filtering happens in memory, which is how
    /// the other cases work anyway.
    func matches(_ item: AssetItem) -> Bool {
        switch self {
        case .all: true
        case .photos: !item.isVideo
        case .videos: item.isVideo
        case .raw: item.isRaw
        }
    }
}

enum AssetSorting {
    /// Assets whose size never resolved sort to the tail in size orders rather than
    /// being treated as zero bytes — an unknown is not a small file.
    static func sort(_ items: [AssetItem], by order: SortOrder) -> [AssetItem] {
        switch order {
        case .newestFirst:
            return items.sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        case .oldestFirst:
            return items.sorted {
                ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture)
            }
        case .largestFirst, .smallestFirst:
            var sized: [AssetItem] = []
            var unsized: [AssetItem] = []
            for item in items {
                if item.bytes == nil { unsized.append(item) } else { sized.append(item) }
            }
            sized.sort { lhs, rhs in
                let left = lhs.bytes ?? 0
                let right = rhs.bytes ?? 0
                return order == .largestFirst ? left > right : left < right
            }
            return sized + unsized
        }
    }
}
