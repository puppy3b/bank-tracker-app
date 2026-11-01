import Foundation
import BankTrackerCore

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension Money {
    /// Compact form for large stat values: "$12.9K", "$1.2M". Smaller amounts stay in full.
    static func compact(_ amount: Decimal) -> String {
        let value = amount.doubleValue
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        let number: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
        if magnitude >= 1_000_000 { return "\(sign)$\(number(magnitude / 1_000_000))M" }
        if magnitude >= 10_000 { return "\(sign)$\(number(magnitude / 1_000))K" }
        return format(amount)
    }

    /// Axis tick labels: in full below $10,000, compact on axes that reach it.
    static func axisLabel(_ value: Double, compact: Bool) -> String {
        if compact {
            return "$" + (value / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "K"
        }
        return format(Decimal(value))
    }
}

enum RelativeDay {
    /// "today", "tomorrow", "in 5 days", "3 days ago"
    static func text(for date: Date, today: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dayCount(from: today, to: date)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...: return "in \(days) days"
        default: return "\(-days) days ago"
        }
    }
}
