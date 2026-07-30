import Foundation
import Observation
import ParkingKit

/// Everything the screens read from.
///
/// The dataset is bundled, so the free/paid answer never depends on the network.
/// Live occupancy is a strictly optional overlay: if it fails, is throttled, or
/// is stale, the app still answers the question it exists to answer.
@Observable
@MainActor
final class AppModel {
    let rules = ParkingRules()
    private(set) var dataset: Dataset?
    private(set) var loadError: String?

    /// The time the whole UI is answering for. Defaults to now; the time rail
    /// moves it so you can plan before leaving.
    var targetDate: Date = Date()
    /// True while `targetDate` is being kept in sync with the wall clock.
    private(set) var followingNow = true

    var permit: PermitClass = .none {
        didSet { UserDefaults.standard.set(permit.rawValue, forKey: Self.permitKey) }
    }

    /// All show/hide state, as one tested value from ParkingKit.
    var filter = FacilityFilter() {
        didSet { persistFilters() }
    }

    var systemFilter: Set<ParkingSystem> {
        get { filter.systems }
        set { filter.systems = newValue }
    }

    var campusFilter: Set<Campus> {
        get { filter.campuses }
        set { filter.campuses = newValue }
    }

    /// Hide facilities that are enforced 24/7 and so never open up. On by default:
    /// a lot that is never free is noise on a screen whose job is finding free
    /// parking.
    var hideNeverFree: Bool {
        get { filter.hidesNeverFree }
        set { filter.hidesNeverFree = newValue }
    }

    /// Which permit tiers to show. Empty means every tier.
    var tierFilter: Set<Tier> {
        get { filter.tiers }
        set { filter.tiers = newValue }
    }

    func toggleTier(_ tier: Tier) {
        filter.toggle(tier, available: availableTiers)
    }

    func includesTier(_ tier: Tier) -> Bool {
        filter.includes(tier)
    }

    /// The tiers that actually occur in the dataset, in a sensible display order.
    var availableTiers: [Tier] {
        guard let dataset else { return [] }
        let present = Set(dataset.parkable.map(\.tier))
        let order: [Tier] = [.blue, .yellow, .orange, .gold, .visitor, .parkAndRide, .public]
        return order.filter(present.contains)
    }

    // Live overlay
    private(set) var occupancy: [String: OccupancyReading] = [:]
    private(set) var occupancyUpdated: String?
    private(set) var occupancyNote: String?
    private(set) var isRefreshing = false

    let location = LocationProvider()
    private let client: AvailabilityFetching
    private var tick: Timer?

    static let permitKey = "mparking.permit"
    static let hideNeverFreeKey = "mparking.hideNeverFree"
    static let tierFilterKey = "mparking.tierFilter"
    static let systemFilterKey = "mparking.systemFilter"
    static let campusFilterKey = "mparking.campusFilter"

    init(client: AvailabilityFetching = LiveAvailabilityClient()) {
        self.client = client
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Self.permitKey),
           let p = PermitClass(rawValue: raw) {
            permit = p
        }
        var restored = FacilityFilter()
        if defaults.object(forKey: Self.hideNeverFreeKey) != nil {
            restored.hidesNeverFree = defaults.bool(forKey: Self.hideNeverFreeKey)
        }
        if let raw = defaults.stringArray(forKey: Self.tierFilterKey) {
            restored.tiers = Set(raw.compactMap(Tier.init(rawValue:)))
        }
        if let raw = defaults.stringArray(forKey: Self.systemFilterKey), !raw.isEmpty {
            restored.systems = Set(raw.compactMap(ParkingSystem.init(rawValue:)))
        }
        if let raw = defaults.stringArray(forKey: Self.campusFilterKey), !raw.isEmpty {
            restored.campuses = Set(raw.compactMap(Campus.init(rawValue:)))
        }
        filter = restored

        do {
            dataset = try Dataset.bundled()
        } catch {
            loadError = error.localizedDescription
        }
        startClock()
    }

    private func persistFilters() {
        let d = UserDefaults.standard
        d.set(filter.tiers.map(\.rawValue), forKey: Self.tierFilterKey)
        d.set(filter.systems.map(\.rawValue), forKey: Self.systemFilterKey)
        d.set(filter.campuses.map(\.rawValue), forKey: Self.campusFilterKey)
        d.set(filter.hidesNeverFree, forKey: Self.hideNeverFreeKey)
    }

    // MARK: - Time

    /// Advance `targetDate` with the wall clock, but only while the user has not
    /// scrubbed away from now.
    private func startClock() {
        tick = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.followingNow else { return }
                self.targetDate = Date()
            }
        }
    }

    func scrub(to date: Date) {
        targetDate = date
        followingNow = false
    }

    func returnToNow() {
        targetDate = Date()
        followingNow = true
    }

    var isViewingNow: Bool { followingNow }

    /// The window the date picker may scrub over. Two days forward covers "should
    /// I wait" and "where do I park tomorrow morning" without becoming a calendar.
    var scrubRange: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-3600)...now.addingTimeInterval(48 * 3600)
    }

    /// The moments people actually ask about.
    enum TimePreset: String, CaseIterable, Identifiable {
        case now, plusTwo, evening, tomorrow

        var id: String { rawValue }

        var label: String {
            switch self {
            case .now: "Now"
            case .plusTwo: "+2h"
            case .evening: "8pm"
            case .tomorrow: "Tomorrow"
            }
        }
    }

    /// Which preset the current target matches, if any. `now` is the fallback so
    /// the segmented control always has a selection.
    var preset: TimePreset {
        if followingNow { return .now }
        for candidate in TimePreset.allCases where candidate != .now {
            if let d = date(for: candidate),
               abs(d.timeIntervalSince(targetDate)) < 60 {
                return candidate
            }
        }
        return .now
    }

    func apply(preset: TimePreset) {
        if preset == .now {
            returnToNow()
        } else if let d = date(for: preset) {
            scrub(to: min(d, scrubRange.upperBound))
        }
    }

    private func date(for preset: TimePreset) -> Date? {
        let cal = Clock.calendar
        let now = Date()
        switch preset {
        case .now:
            return now
        case .plusTwo:
            return now.addingTimeInterval(2 * 3600)
        case .evening:
            // 8pm today, or 8pm tomorrow once that has passed.
            if let today = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now),
               today > now {
                return today
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
            return cal.date(bySettingHour: 20, minute: 0, second: 0, of: next)
        case .tomorrow:
            guard let next = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: next)
        }
    }

    // MARK: - Facilities

    var visibleFacilities: [Facility] {
        guard let dataset else { return [] }
        return filter.apply(to: dataset.parkable, rules: rules)
    }

    /// How many facilities the current filters are holding back, so the UI can
    /// say so rather than silently showing a short list.
    var hiddenCount: Int {
        guard let dataset else { return 0 }
        return dataset.parkable.count - visibleFacilities.count
    }

    var isFiltering: Bool {
        filter != FacilityFilter(systems: Set(ParkingSystem.allCases),
                                 campuses: Set(Campus.allCases),
                                 tiers: [], hidesNeverFree: true)
    }

    var filterSummary: String {
        var parts: [String] = []
        if filter.hidesNeverFree { parts.append("\(neverFreeCount) never-free hidden") }
        if !filter.tiers.isEmpty {
            parts.append(filter.tiers.map(\.label).sorted().joined(separator: ", "))
        }
        if filter.systems.count < ParkingSystem.allCases.count { parts.append("one system") }
        if filter.campuses.count < Campus.allCases.count {
            parts.append("\(filter.campuses.count) campuses")
        }
        return parts.isEmpty ? "No filters" : "Filtered — " + parts.joined(separator: " · ")
    }

    func resetFilters() {
        filter = FacilityFilter()
    }

    func count(of tier: Tier) -> Int {
        dataset?.parkable.filter { $0.tier == tier }.count ?? 0
    }

    var neverFreeCount: Int {
        guard let dataset else { return 0 }
        return dataset.parkable.filter { rules.neverBecomesFree($0) }.count
    }

    struct Row: Identifiable {
        let facility: Facility
        let status: ParkingStatus
        let metres: Double?
        var id: String { facility.id }
        var occupancy: OccupancyReading?
    }

    var rows: [Row] {
        let origin = location.localCoordinate
        return rules.ranked(visibleFacilities, at: targetDate, permit: permit, from: origin)
            .map { Row(facility: $0.0, status: $0.1, metres: $0.2,
                       occupancy: occupancy[$0.0.id]) }
    }

    var freeRows: [Row] { rows.filter { $0.status.isFreeToAll } }

    var permitRows: [Row] {
        rows.filter { if case .allowedWithPermit = $0.status { return true }; return false }
    }

    var blockedRows: [Row] {
        rows.filter {
            switch $0.status {
            case .restricted, .alwaysRestricted: true
            default: false
            }
        }
    }

    var unknownRows: [Row] {
        rows.filter { if case .unknown = $0.status { return true }; return false }
    }

    /// Lots that are not free yet but will be within the hour - the "wait it out"
    /// case, which is genuinely useful at 4:30pm.
    var soonRows: [Row] {
        blockedRows.filter { row in
            guard case .restricted(let freeAt) = row.status, let freeAt else { return false }
            return freeAt.timeIntervalSince(targetDate) <= 3600
        }
    }

    func status(of facility: Facility) -> ParkingStatus {
        rules.status(of: facility, at: targetDate, permit: permit)
    }

    // MARK: - Live overlay

    func refreshOccupancy() async {
        guard let dataset, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snap = try await client.fetchLTP()
            occupancy = AvailabilityMatcher.index(readings: snap.readings,
                                                 facilities: dataset.facilities,
                                                 aliases: dataset.availabilityAliases)
            occupancyUpdated = snap.lastUpdate
            occupancyNote = occupancy.isEmpty
                ? "U-M published no occupancy figures just now."
                : nil
        } catch {
            // Keep whatever figures we already have; say so rather than blanking out.
            occupancyNote = error.localizedDescription
        }
    }
}
