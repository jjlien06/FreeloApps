import SwiftUI
import ParkingKit

/// Presentation helpers only.
///
/// The app uses stock UIKit/SwiftUI materials throughout - `List`, `Form`,
/// semantic colours, Dynamic Type text styles - so there is deliberately no
/// custom palette or type scale here. The only colours defined are the ones that
/// carry meaning: U-M's real permit tiers, and the free/paid verdict.

extension Tier {
    /// U-M's own permit colours, mapped to system colours so they adapt to light
    /// and dark automatically.
    var colour: Color {
        switch self {
        case .blue: .blue
        case .yellow: .yellow
        case .orange: .orange
        case .gold: Color(red: 0.79, green: 0.64, blue: 0.15)
        case .visitor: .teal
        case .parkAndRide: .green
        case .public: .gray
        case .restricted, .contractor, .other: .secondary
        }
    }
}

extension ParkingStatus {
    var tint: Color {
        switch self {
        case .freeToAll: .green
        case .allowedWithPermit: .blue
        case .restricted, .alwaysRestricted: .red
        case .unknown: .purple
        }
    }

    var symbol: String {
        switch self {
        case .freeToAll: "checkmark.circle.fill"
        case .allowedWithPermit: "person.badge.key.fill"
        case .restricted: "clock.fill"
        case .alwaysRestricted: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    /// Short, plain, sentence case - the way iOS labels things.
    var headline: String {
        switch self {
        case .freeToAll: "Free"
        case .allowedWithPermit: "Your permit"
        case .restricted: "Permit or pay"
        case .alwaysRestricted: "Never free"
        case .unknown: "Check the sign"
        }
    }
}

/// Formatters shared across the UI. All Detroit-local, matching the dataset.
enum Clock {
    static let zone = ParkingRules.timeZone

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }()

    /// Formatters are pinned to Detroit, matching the dataset, so a device set to
    /// another time zone still shows Ann Arbor wall-clock times. Time style comes
    /// from the locale, so 12-hour and 24-hour users both get what they expect.
    private static func formatter(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = zone
        configure(f)
        return f
    }

    private static let timeStyle = formatter { $0.timeStyle = .short }

    private static let dayTimeStyle = formatter {
        $0.setLocalizedDateFormatFromTemplate("EEE j:mm")
    }

    private static let weekdayStyle = formatter {
        $0.setLocalizedDateFormatFromTemplate("EEE")
    }

    static func time(_ date: Date) -> String { timeStyle.string(from: date) }

    static func dayAndTime(_ date: Date) -> String { dayTimeStyle.string(from: date) }

    static func weekday(_ date: Date) -> String { weekdayStyle.string(from: date) }

    /// "6:00 AM" for today, "Mon 6:00 AM" when it is further out.
    static func boundary(_ date: Date, from reference: Date) -> String {
        calendar.isDate(date, inSameDayAs: reference) ? time(date) : dayAndTime(date)
    }

    /// Walking distance: whole feet up close, tenths of a mile beyond that.
    /// `.road` usage alone yields things like "1,426.6 ft", which is precision
    /// nobody can use on foot.
    static func distance(_ metres: Double) -> String {
        // `usage: .asProvided` matters: the default localises the unit and would
        // turn 0.3 miles back into 1,392 feet.
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
        let miles = measurement.converted(to: .miles)
        if miles.value < 0.1 {
            return measurement.converted(to: .feet)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                        numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        return miles.formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                            numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}
