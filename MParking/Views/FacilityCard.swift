import SwiftUI
import ParkingKit

/// A standard two-line list row: title, secondary detail, trailing status.
struct FacilityRow: View {
    let row: AppModel.Row
    let date: Date
    let rules: ParkingRules

    private var f: Facility { row.facility }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(f.name)
                    .font(.body)
                Spacer(minLength: 8)
                if let m = row.metres {
                    Text(Clock.distance(m))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: row.status.symbol)
                    .font(.caption)
                    .foregroundStyle(row.status.tint)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if let lotId = f.lotId {
                    Text(lotId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                TierDot(tier: f.tier)
                Text(f.tier.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let occ = row.occupancy {
                    Text("· \(occ.percent)% full")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            EnforcementRibbon(facility: f, date: date, rules: rules, height: 12)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch row.status {
        case .freeToAll(let until):
            guard let until else { return "Free" }
            return "Free until \(Clock.boundary(until, from: date))"
        case .allowedWithPermit(let p):
            return "\(p.label) permit honoured"
        case .restricted(let freeAt):
            guard let freeAt else { return "Permit or pay" }
            return "Free at \(Clock.boundary(freeAt, from: date))"
        case .alwaysRestricted:
            return "Enforced 24/7"
        case .unknown:
            return "Hours not published"
        }
    }
}

struct TierDot: View {
    let tier: Tier

    var body: some View {
        Circle()
            .fill(tier.colour)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
