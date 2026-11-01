import Foundation

/// One restriction from an offer's fine print, such as "no checking bonus in the past 2 years".
public struct EligibilityRule: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// "Not available to existing customers."
        case notCurrentCustomer
        /// "Not available if you've had an account in the past N." Open accounts count too.
        case noAccountWithin
        /// "Not available if you've received a bonus in the past N."
        case noBonusWithin
        /// "Limit one new account per N."
        case oneAccountPer
        /// "New customers only": any previous account disqualifies.
        case neverHadAccount
        /// "One bonus per lifetime."
        case oncePerLifetime
        /// "Only available to residents of …"
        case stateRestriction
        /// Anything the app can't check, which you confirm yourself.
        case manual

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .notCurrentCustomer: "Not a current customer"
            case .noAccountWithin: "No account in the past…"
            case .noBonusWithin: "No bonus in the past…"
            case .oneAccountPer: "One new account per…"
            case .neverHadAccount: "New customers only"
            case .oncePerLifetime: "One bonus per lifetime"
            case .stateRestriction: "Limited to certain states"
            case .manual: "Other (I'll check myself)"
            }
        }

        public var usesScope: Bool { self != .stateRestriction && self != .manual }
        public var usesSpan: Bool { self == .noAccountWithin || self == .noBonusWithin || self == .oneAccountPer }
        public var usesMeasuredFrom: Bool { self == .noBonusWithin }
    }

    /// Which of your accounts at the bank the rule looks at.
    public enum Scope: String, Codable, CaseIterable, Identifiable, Sendable {
        case sameAccountType
        case anyAccount

        public var id: String { rawValue }

        public func displayName(for accountType: AccountType) -> String {
            switch self {
            case .sameAccountType: "\(accountType.displayName) accounts only"
            case .anyAccount: "Any account at this bank"
            }
        }
    }

    /// Which date a "no bonus in the past…" lookback counts from.
    public enum BonusDateBasis: String, Codable, CaseIterable, Identifiable, Sendable {
        case bonusPaidDate
        case accountOpenDate

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .bonusPaidDate: "Bonus payout date"
            case .accountOpenDate: "Account opening date"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var scope: Scope
    public var span: TimeSpan
    public var measuredFrom: BonusDateBasis
    /// USPS codes, for `.stateRestriction`.
    public var states: [String]
    public var note: String
    /// For `.manual`: you've confirmed you meet it.
    public var isConfirmed: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind = .notCurrentCustomer,
        scope: Scope = .sameAccountType,
        span: TimeSpan = .months(12),
        measuredFrom: BonusDateBasis = .bonusPaidDate,
        states: [String] = [],
        note: String = "",
        isConfirmed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.span = span
        self.measuredFrom = measuredFrom
        self.states = states
        self.note = note
        self.isConfirmed = isConfirmed
    }

    public static func template(_ kind: Kind) -> EligibilityRule {
        switch kind {
        case .noAccountWithin: EligibilityRule(kind: kind, span: .months(12))
        case .noBonusWithin: EligibilityRule(kind: kind, span: .years(2))
        case .oneAccountPer: EligibilityRule(kind: kind, span: .months(12))
        default: EligibilityRule(kind: kind)
        }
    }

    public func summary(for accountType: AccountType) -> String {
        let sameType = scope == .sameAccountType
        let type = accountType.inlineName
        let basis = measuredFrom == .bonusPaidDate ? "counted from the payout date" : "counted from account opening"
        switch kind {
        case .notCurrentCustomer:
            return sameType ? "No open \(type) account at this bank" : "No open accounts of any type at this bank"
        case .noAccountWithin:
            return sameType
                ? "No \(type) account held in the past \(span.displayText)"
                : "No accounts of any type held in the past \(span.displayText)"
        case .noBonusWithin:
            return sameType
                ? "No \(type) bonus in the past \(span.displayText) (\(basis))"
                : "No bonus of any kind from this bank in the past \(span.displayText) (\(basis))"
        case .oneAccountPer:
            return sameType
                ? "Limit one new \(type) account per \(span.displayText)"
                : "Limit one new account of any type per \(span.displayText)"
        case .neverHadAccount:
            return sameType
                ? "New customers only: no previous \(type) accounts at this bank"
                : "New customers only: no previous accounts at this bank"
        case .oncePerLifetime:
            return sameType ? "One \(type) bonus per lifetime" : "One bonus per lifetime at this bank"
        case .stateRestriction:
            return states.isEmpty ? "Only for residents of certain states" : "Only for residents of " + states.joined(separator: ", ")
        case .manual:
            return note.isEmpty ? "Other restriction (check yourself)" : note
        }
    }
}

extension EligibilityRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, scope, span, measuredFrom, states, note, isConfirmed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EligibilityRule()
        id = container.decode(.id, default: UUID())
        kind = container.decode(.kind, default: .manual)
        scope = container.decode(.scope, default: defaults.scope)
        span = container.decode(.span, default: defaults.span)
        measuredFrom = container.decode(.measuredFrom, default: defaults.measuredFrom)
        states = container.decode(.states, default: defaults.states)
        note = container.decode(.note, default: defaults.note)
        isConfirmed = container.decode(.isConfirmed, default: defaults.isConfirmed)
    }
}
