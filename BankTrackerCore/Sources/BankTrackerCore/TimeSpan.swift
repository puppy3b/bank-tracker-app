import Foundation

/// A calendar-aware length of time such as "90 days", "6 months" or "2 years",
/// matching how bank terms are usually written.
public struct TimeSpan: Hashable, Sendable {
    public enum Unit: String, Codable, CaseIterable, Identifiable, Sendable {
        case days
        case months
        case years

        public var id: String { rawValue }

        public var calendarComponent: Calendar.Component {
            switch self {
            case .days: .day
            case .months: .month
            case .years: .year
            }
        }

        public func label(for value: Int) -> String {
            let singular = switch self {
            case .days: "day"
            case .months: "month"
            case .years: "year"
            }
            return value == 1 ? singular : singular + "s"
        }
    }

    public var value: Int
    public var unit: Unit

    public init(_ value: Int, _ unit: Unit) {
        self.value = value
        self.unit = unit
    }

    public static func days(_ value: Int) -> TimeSpan { TimeSpan(value, .days) }
    public static func months(_ value: Int) -> TimeSpan { TimeSpan(value, .months) }
    public static func years(_ value: Int) -> TimeSpan { TimeSpan(value, .years) }

    /// Zero (or negative) spans mean "not specified".
    public var isZero: Bool { value <= 0 }

    public func added(to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: unit.calendarComponent, value: value, to: date) ?? date
    }

    public func subtracted(from date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: unit.calendarComponent, value: -value, to: date) ?? date
    }

    /// "90 days", "1 month"
    public var displayText: String { "\(value) \(unit.label(for: value))" }
}

extension TimeSpan: Codable {
    private enum CodingKeys: String, CodingKey {
        case value, unit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = container.decode(.value, default: 0)
        unit = container.decode(.unit, default: .days)
    }
}
