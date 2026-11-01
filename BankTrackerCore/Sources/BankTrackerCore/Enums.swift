import Foundation

public enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case checking
    case savings
    case moneyMarket
    case cd
    case brokerage
    case businessChecking
    case businessSavings
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .moneyMarket: "Money Market"
        case .cd: "CD"
        case .brokerage: "Brokerage / Investment"
        case .businessChecking: "Business Checking"
        case .businessSavings: "Business Savings"
        case .other: "Other"
        }
    }

    /// Form used inside sentences: "no open checking account".
    public var inlineName: String {
        switch self {
        case .cd: "CD"
        case .brokerage: "brokerage"
        default: displayName.lowercased()
        }
    }

    public var systemImage: String {
        switch self {
        case .checking: "creditcard"
        case .savings: "banknote"
        case .moneyMarket: "chart.bar"
        case .cd: "lock"
        case .brokerage: "chart.line.uptrend.xyaxis"
        case .businessChecking: "briefcase"
        case .businessSavings: "briefcase.fill"
        case .other: "building.columns"
        }
    }

    /// Bank bonuses usually arrive on a 1099-INT; brokerage bonuses usually on a 1099-MISC.
    public var defaultTaxForm: TaxFormType {
        self == .brokerage ? .form1099MISC : .form1099INT
    }
}

/// How opening the account touched your credit or banking reports.
public enum InquiryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown
    case noInquiry
    case softPull
    case hardPull
    case chexSystems
    case earlyWarning

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .noInquiry: "None"
        case .softPull: "Soft credit pull"
        case .hardPull: "Hard credit pull"
        case .chexSystems: "ChexSystems"
        case .earlyWarning: "Early Warning Services"
        }
    }
}

public enum TaxFormType: String, Codable, CaseIterable, Identifiable, Sendable {
    case form1099INT
    case form1099MISC
    case consolidated1099
    case noForm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .form1099INT: "1099-INT"
        case .form1099MISC: "1099-MISC"
        case .consolidated1099: "Consolidated 1099"
        case .noForm: "No form expected"
        }
    }

    public var explanation: String {
        switch self {
        case .form1099INT: "Bank bonuses are usually reported as interest (Box 1)."
        case .form1099MISC: "Reported as other income (Box 3); common for brokerage bonuses."
        case .consolidated1099: "Brokerages often include the bonus in their combined 1099 package."
        case .noForm: "No form is issued, but the bonus is still taxable income."
        }
    }

    /// Amount at or above which the payer generally must send the form.
    /// Many banks send forms for smaller amounts too, and the income is taxable either way.
    public func reportingThreshold(taxYear: Int) -> Decimal? {
        switch self {
        case .form1099INT: 10
        // The One Big Beautiful Bill Act raised this from $600 for payments made after 2025.
        case .form1099MISC: taxYear >= 2026 ? 2_000 : 600
        case .consolidated1099, .noForm: nil
        }
    }
}

public enum BonusStatus: String, Codable, CaseIterable, Sendable {
    case noBonus
    case inProgress
    case awaitingPayout
    case received
    case forfeited

    public var displayName: String {
        switch self {
        case .noBonus: "No bonus"
        case .inProgress: "In progress"
        case .awaitingPayout: "Waiting for bonus"
        case .received: "Bonus received"
        case .forfeited: "Forfeited"
        }
    }

    /// Bonus not yet paid but still expected.
    public var isPending: Bool { self == .inProgress || self == .awaitingPayout }

    /// Counts as "having received a bonus" for eligibility lookbacks.
    public var countsAsBonus: Bool { isPending || self == .received }
}
