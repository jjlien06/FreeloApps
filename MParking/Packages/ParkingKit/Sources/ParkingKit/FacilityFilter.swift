import Foundation

/// Which facilities to show.
///
/// This lives in ParkingKit rather than in the view model because deciding what
/// counts as worth showing is domain logic - "never free" in particular depends
/// on the enforcement windows - and it needs to be testable without a UI.
public struct FacilityFilter: Sendable, Equatable {
    public var systems: Set<ParkingSystem>
    public var campuses: Set<Campus>
    /// Empty means every tier. Keeping "all" as the empty set means a fresh
    /// install hides nothing, and the UI has one obvious reset state.
    public var tiers: Set<Tier>
    /// Drop facilities that are enforced 24/7 and so never open up.
    public var hidesNeverFree: Bool

    public init(systems: Set<ParkingSystem> = Set(ParkingSystem.allCases),
                campuses: Set<Campus> = Set(Campus.allCases),
                tiers: Set<Tier> = [],
                hidesNeverFree: Bool = true) {
        self.systems = systems
        self.campuses = campuses
        self.tiers = tiers
        self.hidesNeverFree = hidesNeverFree
    }

    public func matches(_ facility: Facility, rules: ParkingRules) -> Bool {
        guard systems.contains(facility.system) else { return false }
        guard campuses.contains(facility.campus) else { return false }
        guard tiers.isEmpty || tiers.contains(facility.tier) else { return false }
        if hidesNeverFree, rules.neverBecomesFree(facility) { return false }
        return true
    }

    public func apply(to facilities: [Facility], rules: ParkingRules) -> [Facility] {
        facilities.filter { matches($0, rules: rules) }
    }

    /// Toggling a tier when "all" is represented by the empty set needs care:
    /// the first tap has to expand to the full set minus one, or unticking a box
    /// would appear to do nothing.
    public mutating func toggle(_ tier: Tier, available: [Tier]) {
        let all = Set(available)
        if tiers.isEmpty {
            tiers = all.subtracting([tier])
        } else if tiers.contains(tier) {
            let next = tiers.subtracting([tier])
            // Never leave an empty selection that would read as "show nothing";
            // emptying the last one means "show all" again.
            tiers = next.isEmpty ? [] : next
        } else {
            var next = tiers
            next.insert(tier)
            tiers = next == all ? [] : next
        }
    }

    public func includes(_ tier: Tier) -> Bool {
        tiers.isEmpty || tiers.contains(tier)
    }
}
