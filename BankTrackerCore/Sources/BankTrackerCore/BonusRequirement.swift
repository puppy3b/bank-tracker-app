import Foundation

/// One thing you must do to earn a bonus, e.g. "direct deposits totaling $500 within 90 days".
public struct BonusRequirement: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case directDeposit
        case deposit
        case maintainBalance
        case debitPurchases
        case billPay
        case other

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .directDeposit: "Direct deposit"
            case .deposit: "Deposit new money"
            case .maintainBalance: "Maintain a balance"
            case .debitPurchases: "Debit card purchases"
            case .billPay: "Bill payments"
            case .other: "Other"
            }
        }

        public var systemImage: String {
            switch self {
            case .directDeposit: "arrow.down.circle"
            case .deposit: "tray.and.arrow.down"
            case .maintainBalance: "hourglass"
            case .debitPurchases: "creditcard"
            case .billPay: "doc.text"
            case .other: "checklist"
            }
        }

        public var usesAmount: Bool { self != .other }
        public var usesCount: Bool { self == .directDeposit || self == .debitPurchases || self == .billPay }
    }

    /// When the clock starts for a hold: a balance to keep, or a deposit that has to stay put.
    public enum HoldStart: String, Codable, CaseIterable, Identifiable, Sendable {
        case afterFunding
        case afterDepositWindow
        case fromOpening

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .afterFunding: "After you fund it"
            case .afterDepositWindow: "After the deposit window ends"
            case .fromOpening: "From account opening"
            }
        }

        var phrase: String {
            switch self {
            case .afterFunding: "after funding"
            case .afterDepositWindow: "after the deposit window"
            case .fromOpening: "from opening"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Dollars required: deposit total, balance to keep, or spend total. Zero when not applicable.
    public var amount: Decimal
    /// Transactions required: deposits, purchases or payments. Zero when not applicable.
    public var count: Int
    /// Deadline measured from account opening. Zero means no deadline.
    public var window: TimeSpan
    /// How long the money must stay in the account, for a requirement with a hold.
    public var holdPeriod: TimeSpan
    public var holdStart: HoldStart
    /// Deposit only: the new money has to stay in the account for `holdPeriod`. Off by default,
    /// so deposits stored before this existed (which carry an unused 90-day period) have no hold.
    public var keepsDeposit: Bool
    public var details: String
    public var progress: RequirementProgress

    public init(
        id: UUID = UUID(),
        kind: Kind = .directDeposit,
        amount: Decimal = 0,
        count: Int = 0,
        window: TimeSpan = .days(90),
        holdPeriod: TimeSpan = .days(90),
        holdStart: HoldStart = .afterFunding,
        keepsDeposit: Bool = false,
        details: String = "",
        progress: RequirementProgress = RequirementProgress()
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.count = count
        self.window = window
        self.holdPeriod = holdPeriod
        self.holdStart = holdStart
        self.keepsDeposit = keepsDeposit
        self.details = details
        self.progress = progress
    }

    /// A new requirement prefilled with typical values for its kind.
    public static func template(_ kind: Kind) -> BonusRequirement {
        switch kind {
        case .directDeposit: BonusRequirement(kind: kind, amount: 500, window: .days(90))
        case .deposit: BonusRequirement(kind: kind, amount: 15_000, window: .days(30))
        case .maintainBalance: BonusRequirement(kind: kind, amount: 15_000, window: .days(30), holdPeriod: .days(90))
        case .debitPurchases: BonusRequirement(kind: kind, count: 10, window: .days(60))
        case .billPay: BonusRequirement(kind: kind, count: 2, window: .days(60))
        case .other: BonusRequirement(kind: kind, window: .days(90))
        }
    }

    /// The money has to stay in the account until a date: a balance to keep, or a deposit to leave in.
    public var hasHold: Bool {
        kind == .maintainBalance || (kind == .deposit && keepsDeposit)
    }

    /// The task without its deadline, e.g. "Receive direct deposits totaling $500".
    public var actionTitle: String {
        let money = Money.format(amount)
        switch kind {
        case .directDeposit:
            var text = amount > 0 ? "Receive direct deposits totaling \(money)" : "Receive a direct deposit"
            if count > 1 { text += " (at least \(count) deposits)" }
            return text
        case .deposit:
            return hasHold ? depositTitle + " and \(depositHold)" : depositTitle
        case .maintainBalance:
            return "Keep at least \(money) for \(holdPeriod.displayText) \(holdStart.phrase)"
        case .debitPurchases:
            var text = count > 0 ? "Make \(count) debit card \(count == 1 ? "purchase" : "purchases")" : "Make debit card purchases"
            if amount > 0 { text += " totaling \(money)" }
            return text
        case .billPay:
            var text = count > 0 ? "Make \(count) bill \(count == 1 ? "payment" : "payments")" : "Make bill payments"
            if amount > 0 { text += " totaling \(money)" }
            return text
        case .other:
            return details.isEmpty ? "Other requirement" : details
        }
    }

    /// Full sentence including the deadline.
    public var summary: String {
        guard !window.isZero else { return actionTitle }
        if kind == .maintainBalance {
            return actionTitle + " (fund within \(window.displayText) of opening)"
        }
        if kind == .deposit, hasHold {
            return depositTitle + " within \(window.displayText) of opening, and \(depositHold)"
        }
        return actionTitle + " within \(window.displayText) of opening"
    }

    private var depositTitle: String {
        amount > 0 ? "Deposit \(Money.format(amount)) in new money" : "Deposit new money"
    }

    /// "keep it for 90 days after depositing"
    private var depositHold: String {
        "keep it for \(holdPeriod.displayText) \(holdStart == .afterFunding ? "after depositing" : holdStart.phrase)"
    }

    /// "$200 of $500 · 6 of 10", or nil when no progress has been logged.
    public var progressSummary: String? {
        var parts: [String] = []
        if kind.usesAmount, kind != .maintainBalance, amount > 0, progress.amountSoFar > 0 {
            parts.append("\(Money.format(progress.amountSoFar)) of \(Money.format(amount))")
        }
        if kind.usesCount, count > 0, progress.countSoFar > 0 {
            parts.append("\(progress.countSoFar) of \(count)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What you've done so far toward one requirement. Only accounts use this; offers leave it empty.
public struct RequirementProgress: Hashable, Sendable {
    /// When you finished the requirement.
    public var completedOn: Date?
    /// When the money went in, for a requirement with a hold. The hold usually counts from here.
    public var fundedOn: Date?
    public var amountSoFar: Decimal
    public var countSoFar: Int

    public init(completedOn: Date? = nil, fundedOn: Date? = nil, amountSoFar: Decimal = 0, countSoFar: Int = 0) {
        self.completedOn = completedOn
        self.fundedOn = fundedOn
        self.amountSoFar = amountSoFar
        self.countSoFar = countSoFar
    }
}

extension BonusRequirement: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, amount, count, window, holdPeriod, holdStart, keepsDeposit, details, progress
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BonusRequirement()
        id = container.decode(.id, default: UUID())
        kind = container.decode(.kind, default: .other)
        amount = container.decode(.amount, default: defaults.amount)
        count = container.decode(.count, default: defaults.count)
        window = container.decode(.window, default: defaults.window)
        holdPeriod = container.decode(.holdPeriod, default: defaults.holdPeriod)
        holdStart = container.decode(.holdStart, default: defaults.holdStart)
        keepsDeposit = container.decode(.keepsDeposit, default: defaults.keepsDeposit)
        details = container.decode(.details, default: defaults.details)
        progress = container.decode(.progress, default: defaults.progress)
    }
}

extension RequirementProgress: Codable {
    private enum CodingKeys: String, CodingKey {
        case completedOn, fundedOn, amountSoFar, countSoFar
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedOn = container.decode(.completedOn, default: nil)
        fundedOn = container.decode(.fundedOn, default: nil)
        amountSoFar = container.decode(.amountSoFar, default: 0)
        countSoFar = container.decode(.countSoFar, default: 0)
    }
}
