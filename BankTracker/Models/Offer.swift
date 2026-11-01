import Foundation
import SwiftData
import BankTrackerCore

enum OfferStatus: String, Codable, CaseIterable, Identifiable {
    case considering
    case opened
    case skipped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .considering: "Considering"
        case .opened: "Opened"
        case .skipped: "Skipped"
        }
    }
}

/// A bonus offer you found. Opening an account copies its terms into the account.
@Model
final class Offer {
    var uuid: UUID = UUID()
    var bank: Bank?
    var productName: String = ""
    var accountTypeRaw: String = AccountType.checking.rawValue
    var termsData: Data? = nil
    var rulesData: Data? = nil
    var url: String = ""
    var promoCode: String = ""
    var foundDate: Date = Date.now
    var expirationDate: Date? = nil
    var statusRaw: String = OfferStatus.considering.rawValue
    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \BankAccount.sourceOffer)
    var accounts: [BankAccount]? = []

    init() {}

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .other }
        set { accountTypeRaw = newValue.rawValue }
    }

    var terms: OfferTerms {
        get { StoredJSON.decode(OfferTerms.self, from: termsData) ?? OfferTerms() }
        set { termsData = StoredJSON.encode(newValue) }
    }

    var eligibilityRules: [EligibilityRule] {
        get { StoredJSON.decode([EligibilityRule].self, from: rulesData) ?? [] }
        set { rulesData = StoredJSON.encode(newValue) }
    }

    var status: OfferStatus {
        get { OfferStatus(rawValue: statusRaw) ?? .considering }
        set { statusRaw = newValue.rawValue }
    }

    var bankName: String { bank?.name ?? "No bank" }
    var productLabel: String { productName.isEmpty ? accountType.displayName : productName }
    var title: String { "\(bankName) \(productLabel)" }
    var bonusAmount: Decimal { terms.bonusAmount }
    var linkedAccounts: [BankAccount] { accounts ?? [] }

    var isExpired: Bool {
        guard status == .considering, let expirationDate else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: expirationDate) < calendar.startOfDay(for: .now)
    }

    var snapshot: OfferSnapshot {
        OfferSnapshot(
            id: uuid,
            title: "\(Money.format(bonusAmount)) \(title) offer",
            bonusAmount: bonusAmount,
            expirationDate: expirationDate,
            isConsidering: status == .considering
        )
    }

    /// Checks this offer against your accounts, ignoring accounts already opened with it.
    func eligibilityReport(history: [AccountSnapshot], residenceState: String, today: Date = .now) -> EligibilityReport {
        EligibilityEngine(today: today, residenceState: residenceState.isEmpty ? nil : residenceState).evaluate(
            rules: eligibilityRules,
            bankID: bank?.uuid,
            accountType: accountType,
            offerExpiration: expirationDate,
            history: history,
            excluding: Set(linkedAccounts.map(\.uuid))
        )
    }
}
