import CullCore
import SwiftUI

/// A dark, low-chroma shell so nothing competes with the photograph.
enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let chrome = Color(red: 0.098, green: 0.098, blue: 0.110)
    static let elevated = Color(red: 0.145, green: 0.145, blue: 0.161)
    static let hairline = Color.white.opacity(0.08)

    static let pass = Color(red: 0.30, green: 0.82, blue: 0.49)
    static let fail = Color(red: 0.94, green: 0.36, blue: 0.36)
    static let star = Color(red: 0.98, green: 0.75, blue: 0.29)

    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.52)
}

extension Verdict {
    var tint: Color {
        switch self {
        case .pass: Theme.pass
        case .fail: Theme.fail
        }
    }

    var symbol: String {
        switch self {
        case .pass: "checkmark"
        case .fail: "xmark"
        }
    }

    var label: String {
        switch self {
        case .pass: "Pass"
        case .fail: "Fail"
        }
    }
}
