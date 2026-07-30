import SwiftUI
import ParkingKit

/// Twenty-four bars, one per hour of the day: filled where a permit or payment is
/// required, tinted where the gates are up.
///
/// This is the same shape iOS itself uses for Settings › Battery - a day's worth
/// of hourly bars with a marker for now - which is why it belongs here: it reads
/// as a native chart, and it shows the *shape* of the day rather than just the
/// next boundary. Every bar comes from the facility's enforcement windows.
struct EnforcementRibbon: View {
    let facility: Facility
    let date: Date
    let rules: ParkingRules

    var height: CGFloat = 18

    private var hours: [Bool] {
        let start = Clock.calendar.startOfDay(for: date)
        return (0..<24).map { hour in
            guard let t = Clock.calendar.date(byAdding: .hour, value: hour, to: start)
            else { return false }
            return rules.isEnforced(facility, at: t)
        }
    }

    private var currentHour: Int? {
        Clock.calendar.isDate(date, inSameDayAs: date)
            ? Clock.calendar.component(.hour, from: date)
            : nil
    }

    private var isUnknown: Bool {
        facility.enforcement.kind == .unknown || facility.confidence != .verified
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<24, id: \.self) { hour in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colour(enforced: hours[hour]))
                    // Without this each bar takes its intrinsic width and the strip
                    // collapses into a row of dots.
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        if hour == currentHour {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(.primary, lineWidth: 1.5)
                        }
                    }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func colour(enforced: Bool) -> Color {
        if isUnknown { return .purple.opacity(0.3) }
        return enforced ? Color.red.opacity(0.55) : Color.green.opacity(0.75)
    }

    private var summary: String {
        if isUnknown { return "Enforcement hours unknown." }
        let free = hours.filter { !$0 }.count
        switch free {
        case 0: return "Permit or payment required all day."
        case 24: return "Free to all, all day."
        default: return "Free to all for \(free) of 24 hours."
        }
    }
}
