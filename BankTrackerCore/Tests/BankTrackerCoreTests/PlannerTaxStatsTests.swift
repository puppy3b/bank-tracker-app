import Foundation
import Testing
@testable import BankTrackerCore

@Suite("Action planner")
struct ActionPlannerTests {
    let today = day(2026, 3, 1)

    func items(_ accounts: [AccountSnapshot], offers: [OfferSnapshot] = []) -> [ActionItem] {
        ActionPlanner(today: today, calendar: utc).items(accounts: accounts, offers: offers)
    }

    @Test func requirementUrgency() {
        let overdue = account(opened: day(2026, 1, 1), bonus: 300, requirements: [BonusRequirement(kind: .directDeposit, amount: 500, window: .days(30))])
        let soon = account(opened: day(2026, 1, 1), bonus: 300, requirements: [BonusRequirement(kind: .debitPurchases, count: 10, window: .days(62))])
        let later = account(opened: day(2026, 2, 1), bonus: 300, requirements: [BonusRequirement(kind: .billPay, count: 2, window: .days(90))])

        let result = items([later, soon, overdue])

        #expect(result.map(\.urgency) == [.overdue, .dueSoon, .upcoming])
        #expect(result.allSatisfy { $0.kind == .requirement })
    }

    @Test func fundedHoldBecomesKeepBalance() {
        var hold = BonusRequirement(kind: .maintainBalance, amount: 15_000, window: .days(30), holdPeriod: .days(90))
        hold.progress.fundedOn = day(2026, 2, 1)
        let result = items([account(opened: day(2026, 1, 20), bonus: 1_000, requirements: [hold])])
        #expect(result.map(\.kind) == [.keepBalance])
        #expect(result.first?.date == day(2026, 5, 2))
    }

    @Test func fundedDepositHoldBecomesKeepBalance() {
        var deposit = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90), keepsDeposit: true)
        let unfunded = items([account(opened: day(2026, 2, 15), bonus: 600, requirements: [deposit])])
        #expect(unfunded.map(\.kind) == [.requirement])

        deposit.progress.fundedOn = day(2026, 2, 20)
        let funded = items([account(opened: day(2026, 2, 15), bonus: 600, requirements: [deposit])])
        #expect(funded.map(\.kind) == [.keepBalance])
        #expect(funded.first?.date == day(2026, 5, 21))
    }

    @Test("Money stays on hold after the bonus posts")
    func holdOutlastsThePayout() {
        var deposit = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90), keepsDeposit: true)
        deposit.progress.fundedOn = day(2026, 1, 10)
        deposit.progress.completedOn = day(2026, 1, 10)
        let paid = account(opened: day(2026, 1, 1), bonus: 600, requirements: [deposit], received: day(2026, 2, 15))

        let result = items([paid])

        #expect(result.map(\.kind) == [.keepBalance, .closeLater])
        #expect(result.first?.date == day(2026, 4, 10))
        #expect(result.last?.date == day(2026, 4, 10))
    }

    @Test func bonusWaitingAndLate() {
        var done = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90))
        done.progress.completedOn = day(2026, 1, 10)
        let late = account(opened: day(2026, 1, 1), bonus: 300, requirements: [done], payout: PayoutTiming(span: .days(30)))
        let waiting = account(opened: day(2026, 1, 1), bonus: 200, requirements: [done], payout: PayoutTiming(span: .days(60)))

        let result = items([waiting, late])

        #expect(result.map(\.kind) == [.bonusOverdue, .awaitingBonus])
    }

    @Test func closeReminders() {
        let policy = EarlyClosurePolicy(minimumOpen: .months(6))
        let ready = account(opened: day(2025, 6, 1), bonus: 300, earlyClosure: policy, received: day(2025, 8, 1))
        let later = account(opened: day(2026, 1, 1), bonus: 300, earlyClosure: policy, received: day(2026, 2, 15))
        let keeper = account(opened: day(2025, 6, 1), bonus: 300, received: day(2025, 8, 1), keeper: true)

        let kinds = Set(items([ready, later, keeper]).map(\.kind))

        #expect(kinds == [.readyToClose, .closeLater])
    }

    @Test func feeAndOfferReminders() {
        let fee = MaintenanceFee(monthlyFee: 12, waivers: [FeeWaiver.template(.directDeposit), FeeWaiver(kind: .minimumDailyBalance, amount: 1_500, isMyPlan: true)])
        let withFee = account(opened: day(2026, 1, 1), fee: fee)
        let expiring = OfferSnapshot(title: "Maple $300", bonusAmount: 300, expirationDate: day(2026, 3, 5))
        let farOff = OfferSnapshot(title: "Harbor $200", expirationDate: day(2026, 6, 1))

        let result = items([withFee], offers: [expiring, farOff])

        #expect(result.contains { $0.kind == .avoidFee && $0.detail.contains("$1,500") })
        #expect(result.filter { $0.kind == .offerExpiring }.map(\.offerID) == [expiring.id])
    }

    @Test func closedAccountsProduceNothing() {
        let closed = account(opened: day(2025, 1, 1), closed: day(2025, 9, 1), bonus: 300, requirements: [.template(.directDeposit)])
        #expect(items([closed]).isEmpty)
    }
}

@Suite("Taxes")
struct TaxTests {
    @Test("Groups bonuses by bank and form for the year they post")
    func groupsByBankAndForm() {
        let accounts = [
            account(opened: day(2025, 11, 1), bonus: 300, received: day(2026, 1, 20)),
            account(type: .savings, opened: day(2026, 2, 1), bonus: 400, received: day(2026, 5, 1)),
            account(bank: bankB, opened: day(2026, 6, 1), bonus: 250, received: day(2027, 1, 5)),
            account(bank: bankB, type: .brokerage, opened: day(2026, 1, 1), bonus: 500, received: day(2026, 3, 1), taxForm: .form1099MISC),
            account(opened: day(2026, 1, 1), bonus: 150, forfeited: true),
        ]

        let summary = TaxCalculator.summary(taxYear: 2026, accounts: accounts, today: day(2026, 12, 31), calendar: utc)

        #expect(summary.forms.count == 2)
        let maple = summary.forms.first { $0.bankID == bankA }
        #expect(maple?.total == 700)
        #expect(maple?.formType == .form1099INT)
        #expect(maple?.isLikelyIssued == true)
        let misc = summary.forms.first { $0.bankID == bankB }
        #expect(misc?.formType == .form1099MISC)
        #expect(misc?.isLikelyIssued == false, "$500 is under the $2,000 threshold for 2026")
        #expect(summary.paidIncome == 1_200)
    }

    @Test("Pending bonuses count toward the year they're expected")
    func pendingBonuses() {
        let pending = account(opened: day(2026, 10, 1), bonus: 300, requirements: [BonusRequirement(kind: .directDeposit, amount: 500, window: .days(60))])
        let summary = TaxCalculator.summary(taxYear: 2026, accounts: [pending], today: day(2026, 10, 15), calendar: utc)
        #expect(summary.pendingIncome == 300)
        #expect(summary.forms.first?.bonuses.first?.isPaid == false)
        #expect(TaxCalculator.taxYears(accounts: [pending], today: day(2026, 10, 15), calendar: utc) == [2026])
    }

    @Test func thresholds() {
        #expect(TaxFormType.form1099INT.reportingThreshold(taxYear: 2026) == 10)
        #expect(TaxFormType.form1099MISC.reportingThreshold(taxYear: 2025) == 600)
        #expect(TaxFormType.form1099MISC.reportingThreshold(taxYear: 2026) == 2_000)
        #expect(TaxFormType.noForm.reportingThreshold(taxYear: 2026) == nil)
    }

    @Test func filingYear() {
        #expect(TaxCalculator.filingYear(today: day(2027, 2, 1), calendar: utc) == 2026)
        #expect(TaxCalculator.filingYear(today: day(2026, 10, 31), calendar: utc) == 2026)
    }
}

@Suite("Statistics")
struct StatsTests {
    @Test func totals() {
        var deposit = account(opened: day(2026, 2, 1), bonus: 400, requirements: [.template(.directDeposit)])
        deposit.currentBalance = 2_000
        var paid = account(opened: day(2025, 1, 1), closed: day(2025, 8, 1), bonus: 300, received: day(2025, 3, 1))
        paid.feesPaid = 12
        let accounts = [
            paid,
            account(bank: bankB, opened: day(2025, 6, 1), bonus: 500, received: day(2026, 1, 15), receivedAmount: 450),
            deposit,
            account(opened: day(2025, 3, 1), closed: day(2025, 5, 1), bonus: 200, forfeited: true),
        ]

        let stats = PortfolioStats(accounts: accounts, today: day(2026, 3, 1), calendar: utc)

        #expect(stats.accountsOpened == 4)
        #expect(stats.openAccounts == 2)
        #expect(stats.banksUsed == 2)
        #expect(stats.bonusesReceived == 2)
        #expect(stats.totalEarned == 750)
        #expect(stats.earnedThisYear == 450)
        #expect(stats.pendingTotal == 400)
        #expect(stats.forfeitedCount == 1)
        #expect(stats.fundsParked == 2_000)
        #expect(stats.netEarnings == 738)
        #expect(stats.largestBonus?.amount == 450)
        #expect(stats.earnedByYear.map(\.year) == [2025, 2026])
        #expect(stats.earnedByBank.first?.bankName == "Harbor CU")
    }
}

@Suite("Stored JSON")
struct CodableTests {
    @Test("Missing fields fall back to defaults")
    func decodesPartialJSON() throws {
        let json = #"{"bonusAmount": 300, "requirements": [{"kind": "deposit", "amount": 1000}]}"#
        let terms = try JSONDecoder().decode(OfferTerms.self, from: Data(json.utf8))
        #expect(terms.bonusAmount == 300)
        #expect(terms.requirements.first?.kind == .deposit)
        #expect(terms.requirements.first?.window == .days(90))
        #expect(terms.payout == PayoutTiming())
    }

    @Test("Deposits saved before holds existed have no hold")
    func oldDepositsHaveNoHold() throws {
        let json = #"{"kind": "deposit", "amount": 1000, "holdPeriod": {"value": 90, "unit": "days"}, "holdStart": "afterFunding"}"#
        let requirement = try JSONDecoder().decode(BonusRequirement.self, from: Data(json.utf8))
        #expect(requirement.keepsDeposit == false)
        #expect(requirement.hasHold == false)
        #expect(BonusRequirement(kind: .maintainBalance).hasHold)
    }

    @Test("Unknown enum values don't break decoding")
    func unknownValues() throws {
        let json = #"{"kind": "somethingNew", "scope": "anyAccount"}"#
        let rule = try JSONDecoder().decode(EligibilityRule.self, from: Data(json.utf8))
        #expect(rule.kind == .manual)
        #expect(rule.scope == .anyAccount)
    }

    @Test("Round-trips terms, including cents")
    func roundTrip() throws {
        var requirement = BonusRequirement.template(.maintainBalance)
        requirement.progress = RequirementProgress(fundedOn: day(2026, 1, 3), amountSoFar: Decimal(string: "12.99")!)
        var deposit = BonusRequirement.template(.deposit)
        deposit.keepsDeposit = true
        let terms = OfferTerms(
            bonusAmount: Decimal(string: "250.50")!,
            requirements: [requirement, deposit],
            earlyClosure: EarlyClosurePolicy(minimumOpen: .months(6), fee: 25, bonusClawback: true),
            maintenanceFee: MaintenanceFee(monthlyFee: Decimal(string: "4.95")!, waivers: [.template(.directDeposit)])
        )
        let decoded = try JSONDecoder().decode(OfferTerms.self, from: JSONEncoder().encode(terms))
        #expect(decoded == terms)
    }

    @Test func summaries() {
        #expect(BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90)).summary == "Receive direct deposits totaling $500 within 90 days of opening")
        #expect(BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30)).summary == "Deposit $15,000 in new money within 30 days of opening")
        let held = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90), keepsDeposit: true)
        #expect(held.actionTitle == "Deposit $15,000 in new money and keep it for 90 days after depositing")
        #expect(held.summary == "Deposit $15,000 in new money within 30 days of opening, and keep it for 90 days after depositing")
        #expect(FeeWaiver(kind: .minimumDailyBalance, amount: 1_500).summary == "Keep at least $1,500 in the account every day")
        #expect(Money.format(Decimal(string: "12.5")!) == "$12.50")
        #expect(USState.parseCodes("ny, nj zz").valid == ["NY", "NJ"])
    }
}
