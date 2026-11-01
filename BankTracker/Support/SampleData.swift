import Foundation
import SwiftData
import BankTrackerCore

/// Fictional banks, offers and accounts that exercise every state the app handles.
/// Dates are relative to today so the sample always looks current.
enum SampleData {
    static func load(into context: ModelContext, today: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: start) ?? start
        }
        func makeBank(_ name: String, notes: String) -> Bank {
            let bank = Bank(name: name, notes: notes)
            context.insert(bank)
            return bank
        }

        let maple = makeBank("Maple Bank", notes: "Sample data. Uses ChexSystems.")
        let summit = makeBank("Summit Savings", notes: "Sample data.")
        let harbor = makeBank("Harbor Credit Union", notes: "Sample data. Membership needs a $5 share savings account.")
        let northwind = makeBank("Northwind Brokerage", notes: "Sample data.")

        let checkingFee = MaintenanceFee(monthlyFee: 12, waivers: [
            FeeWaiver(kind: .directDeposit, amount: 500, isMyPlan: true),
            FeeWaiver(kind: .minimumDailyBalance, amount: 1_500),
        ])
        let sixMonthClawback = EarlyClosurePolicy(minimumOpen: .months(6), basis: .fromOpening, bonusClawback: true)

        // Maple Bank: a checking bonus earned last year, then the same account opened again.
        var oldDeposit = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90))
        oldDeposit.progress.completedOn = day(-395)
        makeAccount(
            in: context, bank: maple, product: "Everyday Checking", type: .checking,
            opened: day(-420), closed: day(-230),
            terms: OfferTerms(bonusAmount: 300, requirements: [oldDeposit], payout: PayoutTiming(span: .days(30)), earlyClosure: sixMonthClawback, maintenanceFee: checkingFee),
            received: day(-380), inquiry: .chexSystems
        )

        let mapleOffer = makeOffer(
            in: context, bank: maple, product: "Everyday Checking", type: .checking,
            found: day(-48), status: .opened,
            terms: OfferTerms(
                bonusAmount: 400,
                requirements: [
                    BonusRequirement(kind: .directDeposit, amount: 1_000, window: .days(90)),
                    BonusRequirement(kind: .debitPurchases, count: 10, window: .days(60)),
                ],
                payout: PayoutTiming(span: .days(30)),
                earlyClosure: sixMonthClawback,
                maintenanceFee: checkingFee
            ),
            rules: [.template(.notCurrentCustomer), EligibilityRule(kind: .noBonusWithin, span: .months(12))]
        )

        var newDeposit = BonusRequirement(kind: .directDeposit, amount: 1_000, window: .days(90))
        newDeposit.progress = RequirementProgress(completedOn: day(-12), amountSoFar: 1_000)
        var purchases = BonusRequirement(kind: .debitPurchases, count: 10, window: .days(60))
        purchases.progress.countSoFar = 6
        let current = makeAccount(
            in: context, bank: maple, product: "Everyday Checking", type: .checking,
            opened: day(-40),
            terms: OfferTerms(bonusAmount: 400, requirements: [newDeposit, purchases], payout: PayoutTiming(span: .days(30)), earlyClosure: sixMonthClawback, maintenanceFee: checkingFee),
            balance: 1_200, inquiry: .chexSystems
        )
        current.sourceOffer = mapleOffer

        // Summit Savings: the balance hold is done; waiting for the bonus to post.
        var hold = BonusRequirement(kind: .maintainBalance, amount: 20_000, window: .days(30), holdPeriod: .days(90), holdStart: .afterFunding)
        hold.progress.fundedOn = day(-118)
        makeAccount(
            in: context, bank: summit, product: "High-Yield Savings", type: .savings,
            opened: day(-125),
            terms: OfferTerms(bonusAmount: 1_000, requirements: [hold], payout: PayoutTiming(span: .days(45))),
            balance: 20_400, inquiry: .softPull
        )

        // Harbor Credit Union: bonus paid and the minimum-open period is over.
        var harborDeposit = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(60))
        harborDeposit.progress.completedOn = day(-240)
        makeAccount(
            in: context, bank: harbor, product: "Premier Checking", type: .checking,
            opened: day(-260),
            terms: OfferTerms(
                bonusAmount: 250,
                requirements: [harborDeposit],
                payout: PayoutTiming(span: .days(60)),
                earlyClosure: EarlyClosurePolicy(minimumOpen: .days(180), fee: 25),
                maintenanceFee: MaintenanceFee(monthlyFee: 10, waivers: [FeeWaiver(kind: .averageBalance, amount: 2_500, isMyPlan: true)])
            ),
            received: day(-205), balance: 600, inquiry: .hardPull
        )
        makeAccount(
            in: context, bank: harbor, product: "Share Savings", type: .savings,
            opened: day(-260), balance: 5, keeper: true, inquiry: .noInquiry
        )

        // Northwind Brokerage: a brokerage bonus reported on a 1099-MISC, kept long term.
        var transfer = BonusRequirement(kind: .deposit, amount: 25_000, window: .days(60), details: "Transfer assets from another brokerage")
        transfer.progress.completedOn = day(-290)
        makeAccount(
            in: context, bank: northwind, product: "Individual Brokerage", type: .brokerage,
            opened: day(-300),
            terms: OfferTerms(
                bonusAmount: 500,
                requirements: [transfer],
                payout: PayoutTiming(span: .days(90)),
                earlyClosure: EarlyClosurePolicy(minimumOpen: .months(12), basis: .fromBonusPayout, bonusClawback: true),
                taxForm: .form1099MISC
            ),
            received: day(-150), balance: 26_000, keeper: true, inquiry: .softPull
        )

        // Offers still being considered: one eligible, one blocked, one needing review.
        makeOffer(
            in: context, bank: maple, product: "Premium Savings", type: .savings,
            found: day(-3), expires: day(10),
            terms: OfferTerms(
                bonusAmount: 300,
                requirements: [
                    BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30)),
                    BonusRequirement(kind: .maintainBalance, amount: 15_000, window: .days(30), holdPeriod: .days(90), holdStart: .afterDepositWindow),
                ],
                payout: PayoutTiming(span: .days(15)),
                maintenanceFee: MaintenanceFee(monthlyFee: 5, waivers: [FeeWaiver(kind: .minimumDailyBalance, amount: 300, isMyPlan: true)])
            ),
            rules: [.template(.notCurrentCustomer), EligibilityRule(kind: .noBonusWithin, span: .years(2), measuredFrom: .accountOpenDate)],
            url: "https://example.com/maple-savings"
        )
        makeOffer(
            in: context, bank: harbor, product: "Premier Checking", type: .checking,
            found: day(-1),
            terms: OfferTerms(
                bonusAmount: 300,
                requirements: [BonusRequirement(kind: .directDeposit, amount: 500, window: .days(60))],
                payout: PayoutTiming(span: .days(60)),
                earlyClosure: EarlyClosurePolicy(minimumOpen: .days(180), fee: 25)
            ),
            rules: [.template(.notCurrentCustomer), EligibilityRule(kind: .noBonusWithin, scope: .anyAccount, span: .months(24))]
        )
        makeOffer(
            in: context, bank: summit, product: "Everyday Checking", type: .checking,
            found: day(-6), expires: day(45),
            terms: OfferTerms(
                bonusAmount: 200,
                requirements: [BonusRequirement(kind: .directDeposit, amount: 1_000, count: 2, window: .days(90))],
                payout: PayoutTiming(span: .days(30))
            ),
            rules: [
                .template(.notCurrentCustomer),
                EligibilityRule(kind: .stateRestriction, states: ["NY", "NJ", "CT", "PA"]),
                EligibilityRule(kind: .manual, note: "No Summit account closed with a negative balance"),
            ]
        )

        try? context.save()
    }

    @discardableResult
    private static func makeAccount(
        in context: ModelContext,
        bank: Bank,
        product: String,
        type: AccountType,
        opened: Date,
        closed: Date? = nil,
        terms: OfferTerms = OfferTerms(),
        received: Date? = nil,
        balance: Decimal = 0,
        keeper: Bool = false,
        inquiry: InquiryType = .unknown
    ) -> BankAccount {
        let account = BankAccount()
        context.insert(account)
        account.bank = bank
        account.productName = product
        account.accountType = type
        account.openedDate = opened
        account.closedDate = closed
        account.hasBonus = terms.bonusAmount > 0
        account.terms = terms
        account.bonusReceivedDate = received
        account.bonusReceivedAmount = received == nil ? nil : terms.bonusAmount
        account.isKeeper = keeper
        account.currentBalance = balance
        account.inquiry = inquiry
        return account
    }

    @discardableResult
    private static func makeOffer(
        in context: ModelContext,
        bank: Bank,
        product: String,
        type: AccountType,
        found: Date,
        expires: Date? = nil,
        status: OfferStatus = .considering,
        terms: OfferTerms,
        rules: [EligibilityRule],
        url: String = ""
    ) -> Offer {
        let offer = Offer()
        context.insert(offer)
        offer.bank = bank
        offer.productName = product
        offer.accountType = type
        offer.foundDate = found
        offer.expirationDate = expires
        offer.status = status
        offer.terms = terms
        offer.eligibilityRules = rules
        offer.url = url
        return offer
    }
}
