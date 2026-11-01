import Foundation

// MARK: - Tolerant decoding

extension KeyedDecodingContainer {
    /// Decodes `key` when it is present and well-formed, otherwise returns `defaultValue`.
    ///
    /// Everything the app stores as JSON decodes through this, so records written by
    /// older builds keep loading after new fields are added.
    func decode<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        guard let value = try? decodeIfPresent(T.self, forKey: key) else { return defaultValue }
        return value
    }
}

// MARK: - Money

public enum Money {
    public static let currencyCode = "USD"
    static let locale = Locale(identifier: "en_US")

    /// Whole amounts drop the cents ("$300"); others keep them ("$12.50").
    public static func format(_ amount: Decimal) -> String {
        amount.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(amount.isWholeNumber ? 0 : 2))
                .locale(locale)
        )
    }
}

extension Decimal {
    public var isWholeNumber: Bool {
        var value = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == self
    }
}

extension Sequence {
    public func sum(_ value: (Element) -> Decimal) -> Decimal {
        reduce(Decimal.zero) { $0 + value($1) }
    }
}

// MARK: - Dates

extension Calendar {
    /// Calendar days from `start` to `end`; negative when `end` is earlier.
    public func dayCount(from start: Date, to end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }
}

public enum DateText {
    /// "Jan 29, 2027"
    public static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
