import Foundation

/// Everything an offer's fine print specifies. Offers keep a template copy; each account
/// keeps its own copy (including progress on each requirement), so editing an offer later
/// never changes the terms of an account you already opened.
public struct OfferTerms: Hashable, Sendable {
    public var bonusAmount: Decimal
    public var requirements: [BonusRequirement]
    public var payout: PayoutTiming
    public var earlyClosure: EarlyClosurePolicy
    public var maintenanceFee: MaintenanceFee
    public var taxForm: TaxFormType
    public var minimumOpeningDeposit: Decimal

    public init(
        bonusAmount: Decimal = 0,
        requirements: [BonusRequirement] = [],
        payout: PayoutTiming = PayoutTiming(),
        earlyClosure: EarlyClosurePolicy = EarlyClosurePolicy(),
        maintenanceFee: MaintenanceFee = MaintenanceFee(),
        taxForm: TaxFormType = .form1099INT,
        minimumOpeningDeposit: Decimal = 0
    ) {
        self.bonusAmount = bonusAmount
        self.requirements = requirements
        self.payout = payout
        self.earlyClosure = earlyClosure
        self.maintenanceFee = maintenanceFee
        self.taxForm = taxForm
        self.minimumOpeningDeposit = minimumOpeningDeposit
    }

    /// A copy with requirement progress cleared, for starting a new account from an offer.
    public func resettingProgress() -> OfferTerms {
        var copy = self
        for index in copy.requirements.indices {
            copy.requirements[index].progress = RequirementProgress()
        }
        return copy
    }
}

/// When the bank says it pays the bonus.
public struct PayoutTiming: Hashable, Sendable {
    public enum Basis: String, Codable, CaseIterable, Identifiable, Sendable {
        case afterRequirementsMet
        case afterQualificationPeriod
        case afterOpening

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .afterRequirementsMet: "After requirements are met"
            case .afterQualificationPeriod: "After the qualification period ends"
            case .afterOpening: "After account opening"
            }
        }
    }

    public var basis: Basis
    public var span: TimeSpan

    public init(basis: Basis = .afterRequirementsMet, span: TimeSpan = .days(30)) {
        self.basis = basis
        self.span = span
    }

    public var summary: String {
        switch basis {
        case .afterRequirementsMet: "Paid within \(span.displayText) after all requirements are met"
        case .afterQualificationPeriod: "Paid within \(span.displayText) after the qualification period ends"
        case .afterOpening: "Paid within \(span.displayText) of account opening"
        }
    }
}

/// What happens if you close the account too soon.
public struct EarlyClosurePolicy: Hashable, Sendable {
    public enum Basis: String, Codable, CaseIterable, Identifiable, Sendable {
        case fromOpening
        case fromBonusPayout

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .fromOpening: "From account opening"
            case .fromBonusPayout: "From bonus payout"
            }
        }
    }

    /// Minimum time the account must stay open. Zero means no minimum.
    public var minimumOpen: TimeSpan
    public var basis: Basis
    /// Early account closure fee.
    public var fee: Decimal
    /// The bank takes the bonus back if you close before `minimumOpen` has passed.
    public var bonusClawback: Bool

    public init(minimumOpen: TimeSpan = .days(0), basis: Basis = .fromOpening, fee: Decimal = 0, bonusClawback: Bool = false) {
        self.minimumOpen = minimumOpen
        self.basis = basis
        self.fee = fee
        self.bonusClawback = bonusClawback
    }

    public var summary: String {
        guard !minimumOpen.isZero else { return "No minimum time open" }
        var text = "Keep open at least \(minimumOpen.displayText)"
        if basis == .fromBonusPayout { text += " after the bonus posts" }
        var penalties: [String] = []
        if fee > 0 { penalties.append("\(Money.format(fee)) fee") }
        if bonusClawback { penalties.append("bonus clawback") }
        if !penalties.isEmpty { text += "; closing earlier costs " + penalties.joined(separator: " + ") }
        return text
    }
}

/// A way to avoid the monthly maintenance fee.
public struct FeeWaiver: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case minimumDailyBalance
        case averageBalance
        case directDeposit
        case combinedBalance
        case debitPurchases
        case ageOrStudent
        case linkedAccount
        case other

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .minimumDailyBalance: "Minimum daily balance"
            case .averageBalance: "Average monthly balance"
            case .directDeposit: "Monthly direct deposit"
            case .combinedBalance: "Combined balances"
            case .debitPurchases: "Debit card purchases"
            case .ageOrStudent: "Age or student status"
            case .linkedAccount: "Linked account"
            case .other: "Other"
            }
        }

        public var usesAmount: Bool {
            switch self {
            case .minimumDailyBalance, .averageBalance, .directDeposit, .combinedBalance: true
            default: false
            }
        }

        public var usesCount: Bool { self == .debitPurchases }
    }

    public var id: UUID
    public var kind: Kind
    public var amount: Decimal
    public var count: Int
    public var details: String
    /// The waiver you intend to use.
    public var isMyPlan: Bool

    public init(id: UUID = UUID(), kind: Kind = .minimumDailyBalance, amount: Decimal = 0, count: Int = 0, details: String = "", isMyPlan: Bool = false) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.count = count
        self.details = details
        self.isMyPlan = isMyPlan
    }

    public static func template(_ kind: Kind) -> FeeWaiver {
        switch kind {
        case .minimumDailyBalance: FeeWaiver(kind: kind, amount: 1_500)
        case .averageBalance: FeeWaiver(kind: kind, amount: 5_000)
        case .directDeposit: FeeWaiver(kind: kind, amount: 500)
        case .combinedBalance: FeeWaiver(kind: kind, amount: 5_000)
        case .debitPurchases: FeeWaiver(kind: kind, count: 10)
        case .ageOrStudent, .linkedAccount, .other: FeeWaiver(kind: kind)
        }
    }

    public var summary: String {
        let money = Money.format(amount)
        let base = switch kind {
        case .minimumDailyBalance: "Keep at least \(money) in the account every day"
        case .averageBalance: "Keep an average balance of \(money)"
        case .directDeposit: "Receive \(money)+ in direct deposits each statement period"
        case .combinedBalance: "Keep \(money) across linked accounts"
        case .debitPurchases: "Make \(count) debit card purchases each statement period"
        case .ageOrStudent: "Age or student exemption"
        case .linkedAccount: "Link a qualifying account"
        case .other: details.isEmpty ? "Other waiver" : details
        }
        if kind != .other, !details.isEmpty { return "\(base) (\(details))" }
        return base
    }
}

/// The monthly service fee and the ways to avoid it.
public struct MaintenanceFee: Hashable, Sendable {
    public var monthlyFee: Decimal
    public var waivers: [FeeWaiver]
    public var notes: String

    public init(monthlyFee: Decimal = 0, waivers: [FeeWaiver] = [], notes: String = "") {
        self.monthlyFee = monthlyFee
        self.waivers = waivers
        self.notes = notes
    }

    public var hasFee: Bool { monthlyFee > 0 }

    /// The waiver marked as your plan, falling back to the first one listed.
    public var plannedWaiver: FeeWaiver? { waivers.first(where: \.isMyPlan) ?? waivers.first }

    public var summary: String {
        guard hasFee else { return "No monthly fee" }
        let fee = "\(Money.format(monthlyFee))/month"
        guard !waivers.isEmpty else { return "\(fee), no waiver recorded" }
        return "\(fee). Avoid it: " + waivers.map(\.summary).joined(separator: ", or ")
    }
}

// MARK: - Codable

extension OfferTerms: Codable {
    private enum CodingKeys: String, CodingKey {
        case bonusAmount, requirements, payout, earlyClosure, maintenanceFee, taxForm, minimumOpeningDeposit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OfferTerms()
        bonusAmount = container.decode(.bonusAmount, default: defaults.bonusAmount)
        requirements = container.decode(.requirements, default: defaults.requirements)
        payout = container.decode(.payout, default: defaults.payout)
        earlyClosure = container.decode(.earlyClosure, default: defaults.earlyClosure)
        maintenanceFee = container.decode(.maintenanceFee, default: defaults.maintenanceFee)
        taxForm = container.decode(.taxForm, default: defaults.taxForm)
        minimumOpeningDeposit = container.decode(.minimumOpeningDeposit, default: defaults.minimumOpeningDeposit)
    }
}

extension PayoutTiming: Codable {
    private enum CodingKeys: String, CodingKey {
        case basis, span
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PayoutTiming()
        basis = container.decode(.basis, default: defaults.basis)
        span = container.decode(.span, default: defaults.span)
    }
}

extension EarlyClosurePolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case minimumOpen, basis, fee, bonusClawback
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EarlyClosurePolicy()
        minimumOpen = container.decode(.minimumOpen, default: defaults.minimumOpen)
        basis = container.decode(.basis, default: defaults.basis)
        fee = container.decode(.fee, default: defaults.fee)
        bonusClawback = container.decode(.bonusClawback, default: defaults.bonusClawback)
    }
}

extension FeeWaiver: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, amount, count, details, isMyPlan
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decode(.id, default: UUID())
        kind = container.decode(.kind, default: .other)
        amount = container.decode(.amount, default: 0)
        count = container.decode(.count, default: 0)
        details = container.decode(.details, default: "")
        isMyPlan = container.decode(.isMyPlan, default: false)
    }
}

extension MaintenanceFee: Codable {
    private enum CodingKeys: String, CodingKey {
        case monthlyFee, waivers, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthlyFee = container.decode(.monthlyFee, default: 0)
        waivers = container.decode(.waivers, default: [])
        notes = container.decode(.notes, default: "")
    }
}
