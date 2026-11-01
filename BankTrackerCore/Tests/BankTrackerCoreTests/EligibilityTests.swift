import Foundation
import Testing
@testable import BankTrackerCore

@Suite("Eligibility")
struct EligibilityTests {
    let today = day(2026, 3, 1)

    func engine(state: String? = nil) -> EligibilityEngine {
        EligibilityEngine(today: today, calendar: utc, residenceState: state)
    }

    func evaluate(_ rules: [EligibilityRule], type: AccountType = .checking, expiration: Date? = nil, history: [AccountSnapshot], state: String? = nil, excluding: Set<UUID> = []) -> EligibilityReport {
        engine(state: state).evaluate(rules: rules, bankID: bankA, accountType: type, offerExpiration: expiration, history: history, excluding: excluding)
    }

    @Test func noRulesEntered() {
        #expect(evaluate([], history: []).verdict == .noRulesEntered)
    }

    @Test func eligibleWithNoHistory() {
        let report = evaluate([.template(.notCurrentCustomer), .template(.noBonusWithin)], history: [])
        #expect(report.verdict == .eligible)
        #expect(report.evaluations.allSatisfy { $0.outcome == .pass })
    }

    @Test("An open account must be closed first; estimate uses its earliest penalty-free close")
    func currentCustomerMustClose() {
        let open = account(opened: day(2026, 1, 1), earlyClosure: EarlyClosurePolicy(minimumOpen: .months(6)))
        let report = evaluate([.template(.notCurrentCustomer)], history: [open])
        #expect(report.verdict == .closeAccountFirst(estimate: day(2026, 7, 1)))
        #expect(report.evaluations.first?.relatedAccountIDs == [open.id])
    }

    @Test("Closing within the lookback blocks until the lookback passes")
    func closedWithinLookback() {
        let closed = account(opened: day(2025, 6, 1), closed: day(2026, 2, 1))
        let report = evaluate([EligibilityRule(kind: .noAccountWithin, span: .days(90))], history: [closed])
        #expect(report.verdict == .eligibleOn(day(2026, 5, 2)))
    }

    @Test("An open account counts toward 'no account in the past N'")
    func openAccountCountsTowardLookback() {
        let open = account(opened: day(2025, 1, 1))
        let report = evaluate([EligibilityRule(kind: .noAccountWithin, span: .days(90))], history: [open])
        // Close today (already past any minimum), then wait 90 days.
        #expect(report.verdict == .closeAccountFirst(estimate: day(2026, 5, 30)))
    }

    @Test("Bonus lookback measured from the opening date")
    func bonusLookbackFromOpening() {
        let earlier = account(opened: day(2025, 1, 15), closed: day(2025, 9, 1), bonus: 300, received: day(2025, 4, 1))
        let rule = EligibilityRule(kind: .noBonusWithin, span: .years(2), measuredFrom: .accountOpenDate)
        #expect(evaluate([rule], history: [earlier]).verdict == .eligibleOn(day(2027, 1, 15)))
    }

    @Test("Bonus lookback from payout uses the expected date for a pending bonus")
    func bonusLookbackPending() {
        let pending = account(
            type: .savings,
            opened: day(2026, 2, 1),
            bonus: 200,
            requirements: [BonusRequirement(kind: .deposit, amount: 10_000, window: .days(30))]
        )
        // Deadline Mar 3 → payout by Apr 2 → 12 months later.
        let rule = EligibilityRule(kind: .noBonusWithin, scope: .anyAccount, span: .months(12), measuredFrom: .bonusPaidDate)
        #expect(evaluate([rule], history: [pending]).verdict == .eligibleOn(day(2027, 4, 2)))
    }

    @Test("Forfeited bonuses don't count as received")
    func forfeitedBonusIgnored() {
        let forfeited = account(opened: day(2025, 12, 1), closed: day(2026, 2, 1), bonus: 300, forfeited: true)
        let rule = EligibilityRule(kind: .noBonusWithin, span: .years(2))
        #expect(evaluate([rule], history: [forfeited]).verdict == .eligible)
    }

    @Test("Same-type scope ignores other account types; any-account scope doesn't")
    func scope() {
        let savings = account(type: .savings, opened: day(2025, 12, 1))
        let sameType = EligibilityRule(kind: .notCurrentCustomer, scope: .sameAccountType)
        let anyType = EligibilityRule(kind: .notCurrentCustomer, scope: .anyAccount)
        #expect(evaluate([sameType], history: [savings]).verdict == .eligible)
        #expect(evaluate([anyType], history: [savings]).verdict == .closeAccountFirst(estimate: today))
    }

    @Test("One account per period counts from the opening date")
    func oneAccountPerPeriod() {
        let recent = account(opened: day(2025, 9, 15), closed: day(2026, 2, 1))
        let rule = EligibilityRule(kind: .oneAccountPer, span: .months(12))
        #expect(evaluate([rule], history: [recent]).verdict == .eligibleOn(day(2026, 9, 15)))
    }

    @Test func lifetimeRulesBlockPermanently() {
        let old = account(opened: day(2019, 1, 1), closed: day(2019, 9, 1), bonus: 200, received: day(2019, 3, 1))
        #expect(evaluate([.template(.oncePerLifetime)], history: [old]).verdict == .notEligible)
        #expect(evaluate([.template(.neverHadAccount)], history: [old]).verdict == .notEligible)
    }

    @Test func stateRestriction() {
        let rule = EligibilityRule(kind: .stateRestriction, states: ["NJ", "CT"])
        #expect(evaluate([rule], history: [], state: nil).verdict == .needsReview(count: 1))
        #expect(evaluate([rule], history: [], state: "NY").verdict == .notEligible)
        #expect(evaluate([rule], history: [], state: "nj").verdict == .eligible)
    }

    @Test func manualRules() {
        var rule = EligibilityRule(kind: .manual, note: "No negative balance closures")
        #expect(evaluate([rule], history: []).verdict == .needsReview(count: 1))
        rule.isConfirmed = true
        #expect(evaluate([rule], history: []).verdict == .eligible)
    }

    @Test("Accounts at other banks and excluded accounts are ignored")
    func otherBanksAndExclusions() {
        let elsewhere = account(bank: bankB, opened: day(2026, 1, 1))
        let linked = account(opened: day(2026, 2, 1))
        let rule = EligibilityRule.template(.notCurrentCustomer)
        #expect(evaluate([rule], history: [elsewhere]).verdict == .eligible)
        #expect(evaluate([rule], history: [linked], excluding: [linked.id]).verdict == .eligible)
    }

    @Test("A permanent block outranks a temporary one")
    func permanentBlockWins() {
        let old = account(opened: day(2025, 1, 1), closed: day(2026, 2, 1), bonus: 300, received: day(2025, 3, 1))
        let rules = [EligibilityRule(kind: .noAccountWithin, span: .days(90)), .template(.oncePerLifetime)]
        #expect(evaluate(rules, history: [old]).verdict == .notEligible)
    }

    @Test("Flags offers that expire before you'd become eligible")
    func expiresBeforeEligible() {
        let closed = account(opened: day(2025, 6, 1), closed: day(2026, 2, 1))
        let rule = EligibilityRule(kind: .noAccountWithin, span: .days(90))
        let report = evaluate([rule], expiration: day(2026, 4, 1), history: [closed])
        #expect(report.expiresBeforeEligible)
        #expect(report.headline.contains("expires"))
    }

    @Test func velocityCounts() {
        let history = [
            account(opened: day(2026, 2, 1)),
            account(bank: bankB, opened: day(2025, 8, 1)),
            account(bank: bankB, opened: day(2024, 6, 1)),
        ]
        let velocity = VelocitySummary(accounts: history, today: today, calendar: utc)
        #expect(velocity.openedLast6Months == 1)
        #expect(velocity.openedLast12Months == 2)
        #expect(velocity.openedLast24Months == 3)
    }
}
