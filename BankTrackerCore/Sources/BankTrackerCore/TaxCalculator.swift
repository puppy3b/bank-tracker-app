import Foundation

/// One bonus counted toward a tax year.
public struct TaxableBonus: Identifiable, Hashable, Sendable {
    /// The account the bonus belongs to.
    public var id: UUID
    public var accountName: String
    public var amount: Decimal
    public var date: Date
    /// False for bonuses that are expected but haven't posted yet.
    public var isPaid: Bool
}

/// A tax form you should expect from one bank for one year.
public struct ExpectedTaxForm: Identifiable, Hashable, Sendable {
    public var taxYear: Int
    public var bankID: UUID?
    public var bankName: String
    public var formType: TaxFormType
    public var bonuses: [TaxableBonus]

    public var id: String { "\(taxYear)|\(bankID?.uuidString ?? bankName)|\(formType.rawValue)" }
    public var total: Decimal { bonuses.sum(\.amount) }
    public var paidTotal: Decimal { bonuses.filter(\.isPaid).sum(\.amount) }
    public var pendingTotal: Decimal { total - paidTotal }
    public var threshold: Decimal? { formType.reportingThreshold(taxYear: taxYear) }

    /// Whether the payer generally has to send this form, based on the usual threshold.
    public var isLikelyIssued: Bool {
        guard formType != .noForm else { return false }
        guard let threshold else { return true }
        return total >= threshold
    }
}

public struct TaxYearSummary: Hashable, Sendable {
    public var taxYear: Int
    public var forms: [ExpectedTaxForm]

    /// Bonus income already received in the year.
    public var paidIncome: Decimal { forms.sum(\.paidTotal) }
    /// Bonuses expected to post later in the year.
    public var pendingIncome: Decimal { forms.sum(\.pendingTotal) }
    public var expectedForms: [ExpectedTaxForm] { forms.filter(\.isLikelyIssued) }
    /// Forms the bank may skip because the total is under the threshold. The income still counts.
    public var belowThresholdForms: [ExpectedTaxForm] { forms.filter { $0.formType != .noForm && !$0.isLikelyIssued } }
    public var noFormGroups: [ExpectedTaxForm] { forms.filter { $0.formType == .noForm } }
}

/// Groups bonuses into the tax forms you should receive. A bonus belongs to the year it
/// posts, not the year the account was opened.
public enum TaxCalculator {
    public static func summary(taxYear: Int, accounts: [AccountSnapshot], today: Date = .now, calendar: Calendar = .current) -> TaxYearSummary {
        var groups: [String: ExpectedTaxForm] = [:]
        for account in accounts {
            guard let bonus = taxableBonus(for: account, today: today, calendar: calendar),
                  calendar.component(.year, from: bonus.date) == taxYear
            else { continue }
            let form = account.terms.taxForm
            let key = "\(account.bankID?.uuidString ?? account.bankName)|\(form.rawValue)"
            groups[key, default: ExpectedTaxForm(
                taxYear: taxYear,
                bankID: account.bankID,
                bankName: account.bankName,
                formType: form,
                bonuses: []
            )].bonuses.append(bonus)
        }
        let forms = groups.values
            .map { group in
                var group = group
                group.bonuses.sort { $0.date < $1.date }
                return group
            }
            .sorted { ($0.bankName.lowercased(), $0.formType.rawValue) < ($1.bankName.lowercased(), $1.formType.rawValue) }
        return TaxYearSummary(taxYear: taxYear, forms: forms)
    }

    /// Years with any paid or expected bonus, plus the current year, newest first.
    public static func taxYears(accounts: [AccountSnapshot], today: Date = .now, calendar: Calendar = .current) -> [Int] {
        var years: Set<Int> = [calendar.component(.year, from: today)]
        for account in accounts {
            if let bonus = taxableBonus(for: account, today: today, calendar: calendar) {
                years.insert(calendar.component(.year, from: bonus.date))
            }
        }
        return years.sorted(by: >)
    }

    /// The year whose forms are arriving: last year from January through April, otherwise this year.
    public static func filingYear(today: Date = .now, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: today)
        return calendar.component(.month, from: today) <= 4 ? year - 1 : year
    }

    static func taxableBonus(for account: AccountSnapshot, today: Date, calendar: Calendar) -> TaxableBonus? {
        guard account.hasBonus, !account.bonusForfeited else { return nil }
        if let received = account.bonusReceivedDate {
            return TaxableBonus(id: account.id, accountName: account.displayName, amount: account.receivedBonusAmount, date: received, isPaid: true)
        }
        guard let expected = account.timeline(today: today, calendar: calendar).expectedPayout else { return nil }
        return TaxableBonus(id: account.id, accountName: account.displayName, amount: account.terms.bonusAmount, date: expected, isPaid: false)
    }
}
