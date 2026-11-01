import Foundation
import SwiftData
import BankTrackerCore

/// One account you opened. Opening the same product again later is a separate record,
/// which is what lets eligibility rules look back over your full history.
@Model
final class BankAccount {
    var uuid: UUID = UUID()
    var bank: Bank?
    var sourceOffer: Offer?
    var productName: String = ""
    var accountTypeRaw: String = AccountType.checking.rawValue
    var last4: String = ""
    var openedDate: Date = Date.now
    var closedDate: Date? = nil
    var hasBonus: Bool = false
    /// Terms copied from the offer, plus progress on each requirement.
    var termsData: Data? = nil
    var bonusReceivedDate: Date? = nil
    var bonusReceivedAmount: Decimal? = nil
    var bonusForfeited: Bool = false
    var isKeeper: Bool = false
    var currentBalance: Decimal = 0
    var feesPaid: Decimal = 0
    var inquiryRaw: String = InquiryType.unknown.rawValue
    var notes: String = ""
    var createdAt: Date = Date.now

    init() {}

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .other }
        set { accountTypeRaw = newValue.rawValue }
    }

    var terms: OfferTerms {
        get { StoredJSON.decode(OfferTerms.self, from: termsData) ?? OfferTerms() }
        set { termsData = StoredJSON.encode(newValue) }
    }

    var inquiry: InquiryType {
        get { InquiryType(rawValue: inquiryRaw) ?? .unknown }
        set { inquiryRaw = newValue.rawValue }
    }

    var isOpen: Bool { closedDate == nil }
    var bankName: String { bank?.name ?? "No bank" }
    var productLabel: String { productName.isEmpty ? accountType.displayName : productName }
    var displayName: String { "\(bankName) \(productLabel)" }

    var snapshot: AccountSnapshot {
        AccountSnapshot(
            id: uuid,
            bankID: bank?.uuid,
            bankName: bank?.name ?? "",
            productName: productName,
            accountType: accountType,
            openedDate: openedDate,
            closedDate: closedDate,
            hasBonus: hasBonus,
            terms: terms,
            bonusReceivedDate: bonusReceivedDate,
            bonusReceivedAmount: bonusReceivedAmount,
            bonusForfeited: bonusForfeited,
            isKeeper: isKeeper,
            currentBalance: currentBalance,
            feesPaid: feesPaid,
            inquiry: inquiry
        )
    }
}
