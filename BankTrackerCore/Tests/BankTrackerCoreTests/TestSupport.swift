import Foundation
@testable import BankTrackerCore

let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
}

let bankA = UUID()
let bankB = UUID()

func account(
    bank: UUID = bankA,
    type: AccountType = .checking,
    opened: Date,
    closed: Date? = nil,
    bonus: Decimal? = nil,
    requirements: [BonusRequirement] = [],
    payout: PayoutTiming = PayoutTiming(),
    earlyClosure: EarlyClosurePolicy = EarlyClosurePolicy(),
    received: Date? = nil,
    receivedAmount: Decimal? = nil,
    forfeited: Bool = false,
    taxForm: TaxFormType = .form1099INT,
    fee: MaintenanceFee = MaintenanceFee(),
    keeper: Bool = false
) -> AccountSnapshot {
    AccountSnapshot(
        bankID: bank,
        bankName: bank == bankA ? "Maple Bank" : "Harbor CU",
        productName: "\(type.displayName) Account",
        accountType: type,
        openedDate: opened,
        closedDate: closed,
        hasBonus: bonus != nil,
        terms: OfferTerms(
            bonusAmount: bonus ?? 0,
            requirements: requirements,
            payout: payout,
            earlyClosure: earlyClosure,
            maintenanceFee: fee,
            taxForm: taxForm
        ),
        bonusReceivedDate: received,
        bonusReceivedAmount: receivedAmount,
        bonusForfeited: forfeited,
        isKeeper: keeper
    )
}
