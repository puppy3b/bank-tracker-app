import Foundation

/// A plain-value copy of one account, which is what all the calculators work with.
public struct AccountSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var bankID: UUID?
    public var bankName: String
    public var productName: String
    public var accountType: AccountType
    public var openedDate: Date
    public var closedDate: Date?
    public var hasBonus: Bool
    public var terms: OfferTerms
    public var bonusReceivedDate: Date?
    public var bonusReceivedAmount: Decimal?
    public var bonusForfeited: Bool
    /// A long-term account you don't plan to close; suppresses close reminders.
    public var isKeeper: Bool
    public var currentBalance: Decimal
    public var feesPaid: Decimal
    public var inquiry: InquiryType

    public init(
        id: UUID = UUID(),
        bankID: UUID? = nil,
        bankName: String = "",
        productName: String = "",
        accountType: AccountType = .checking,
        openedDate: Date,
        closedDate: Date? = nil,
        hasBonus: Bool = false,
        terms: OfferTerms = OfferTerms(),
        bonusReceivedDate: Date? = nil,
        bonusReceivedAmount: Decimal? = nil,
        bonusForfeited: Bool = false,
        isKeeper: Bool = false,
        currentBalance: Decimal = 0,
        feesPaid: Decimal = 0,
        inquiry: InquiryType = .unknown
    ) {
        self.id = id
        self.bankID = bankID
        self.bankName = bankName
        self.productName = productName
        self.accountType = accountType
        self.openedDate = openedDate
        self.closedDate = closedDate
        self.hasBonus = hasBonus
        self.terms = terms
        self.bonusReceivedDate = bonusReceivedDate
        self.bonusReceivedAmount = bonusReceivedAmount
        self.bonusForfeited = bonusForfeited
        self.isKeeper = isKeeper
        self.currentBalance = currentBalance
        self.feesPaid = feesPaid
        self.inquiry = inquiry
    }

    public var isOpen: Bool { closedDate == nil }

    /// "Chase Total Checking", or "Chase Checking" when no product name was entered.
    public var displayName: String {
        let product = productName.isEmpty ? accountType.displayName : productName
        return bankName.isEmpty ? product : "\(bankName) \(product)"
    }

    /// Product name on its own, for places where the bank is already shown.
    public var productLabel: String { productName.isEmpty ? accountType.displayName : productName }

    /// The bonus actually received: the recorded amount, or the promised amount if none was entered.
    /// Zero until the bonus posts.
    public var receivedBonusAmount: Decimal {
        guard hasBonus, !bonusForfeited, bonusReceivedDate != nil else { return 0 }
        return bonusReceivedAmount ?? terms.bonusAmount
    }

    public func timeline(today: Date = .now, calendar: Calendar = .current) -> BonusTimeline {
        BonusTimeline(account: self, today: today, calendar: calendar)
    }

    public func bonusStatus(in timeline: BonusTimeline) -> BonusStatus {
        if !hasBonus { return .noBonus }
        if bonusForfeited { return .forfeited }
        if bonusReceivedDate != nil { return .received }
        if timeline.requirementsMetOn != nil { return .awaitingPayout }
        return .inProgress
    }

    public func bonusStatus(today: Date = .now, calendar: Calendar = .current) -> BonusStatus {
        bonusStatus(in: timeline(today: today, calendar: calendar))
    }

    /// Money that has to stay in the account, one per requirement with a hold, with the date it
    /// can be withdrawn. This still matters after the bonus posts, since taking the money out
    /// early can cost the bonus; once it's forfeited or the account is closed, nothing is at stake.
    public func holds(in timeline: BonusTimeline) -> [MoneyHold] {
        let status = bonusStatus(in: timeline)
        guard isOpen, status.isPending || status == .received else { return [] }
        return terms.requirements.compactMap { requirement in
            guard requirement.hasHold, let until = timeline.schedule(for: requirement.id)?.holdUntil else { return nil }
            return MoneyHold(requirement: requirement, until: until)
        }
    }
}

/// Money that has to stay in an account until a date: a balance to keep, or a deposit to leave in.
public struct MoneyHold: Identifiable, Hashable, Sendable {
    public var requirement: BonusRequirement
    /// When the money can be withdrawn.
    public var until: Date

    public var id: UUID { requirement.id }
    public var amount: Decimal { requirement.amount }
    public var fundedOn: Date? { requirement.progress.fundedOn }
    /// The hold counts from funding, which hasn't happened yet, so `until` is only a guess.
    public var isEstimate: Bool { fundedOn == nil && requirement.holdStart == .afterFunding }
}
