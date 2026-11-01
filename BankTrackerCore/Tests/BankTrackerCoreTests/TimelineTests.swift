import Foundation
import Testing
@testable import BankTrackerCore

@Suite("Bonus timeline")
struct TimelineTests {
    @Test("Payout estimate assumes the deadline until requirements are done")
    func payoutUsesDeadlineWhileIncomplete() {
        let directDeposit = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90))
        let snapshot = account(opened: day(2026, 1, 1), bonus: 300, requirements: [directDeposit])

        let timeline = snapshot.timeline(today: day(2026, 1, 15), calendar: utc)

        #expect(timeline.requirements.first?.deadline == day(2026, 4, 1))
        #expect(timeline.requirementsMetOn == nil)
        #expect(timeline.expectedPayout == day(2026, 5, 1))
        #expect(snapshot.bonusStatus(in: timeline) == .inProgress)
    }

    @Test("Completing requirements moves the payout estimate earlier")
    func payoutUsesCompletionDate() {
        var directDeposit = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90))
        directDeposit.progress.completedOn = day(2026, 2, 10)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 300, requirements: [directDeposit])

        let timeline = snapshot.timeline(today: day(2026, 2, 15), calendar: utc)

        #expect(timeline.requirementsMetOn == day(2026, 2, 10))
        #expect(timeline.expectedPayout == day(2026, 3, 12))
        #expect(snapshot.bonusStatus(in: timeline) == .awaitingPayout)
    }

    @Test("Outstanding deadline ignores requirements already done")
    func outstandingDeadline() {
        var directDeposit = BonusRequirement(kind: .directDeposit, amount: 1_000, window: .days(90))
        directDeposit.progress.completedOn = day(2026, 1, 20)
        let purchases = BonusRequirement(kind: .debitPurchases, count: 10, window: .days(60))
        let snapshot = account(opened: day(2026, 1, 1), bonus: 400, requirements: [directDeposit, purchases])

        let timeline = snapshot.timeline(today: day(2026, 2, 1), calendar: utc)

        #expect(timeline.qualificationEnd == day(2026, 4, 1))
        #expect(timeline.outstandingDeadline == day(2026, 3, 2))
    }

    @Test("An overdue requirement can't be projected into the past")
    func overdueRequirementProjectsFromToday() {
        let directDeposit = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(30))
        let snapshot = account(opened: day(2026, 1, 1), bonus: 300, requirements: [directDeposit])

        let timeline = snapshot.timeline(today: day(2026, 3, 1), calendar: utc)

        #expect(timeline.expectedPayout == day(2026, 3, 31))
    }

    @Test("A funded balance hold completes itself when the hold period ends")
    func balanceHoldAutoCompletes() {
        var hold = BonusRequirement(kind: .maintainBalance, amount: 15_000, window: .days(30), holdPeriod: .days(90), holdStart: .afterFunding)
        hold.progress.fundedOn = day(2026, 1, 10)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 1_000, requirements: [hold])

        let before = snapshot.timeline(today: day(2026, 4, 9), calendar: utc)
        #expect(before.requirements.first?.holdUntil == day(2026, 4, 10))
        #expect(before.requirementsMetOn == nil)

        let after = snapshot.timeline(today: day(2026, 4, 10), calendar: utc)
        #expect(after.requirementsMetOn == day(2026, 4, 10))
        #expect(snapshot.bonusStatus(in: after) == .awaitingPayout)
    }

    @Test("A deposit that has to stay put completes when its hold ends, and sets the withdraw date")
    func depositHoldAutoCompletes() {
        var deposit = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90), keepsDeposit: true)
        deposit.progress.fundedOn = day(2026, 1, 10)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 600, requirements: [deposit])

        let before = snapshot.timeline(today: day(2026, 4, 9), calendar: utc)
        #expect(before.requirements.first?.holdUntil == day(2026, 4, 10))
        #expect(snapshot.bonusStatus(in: before) == .inProgress)
        #expect(snapshot.holds(in: before).map(\.until) == [day(2026, 4, 10)])
        #expect(before.earliestCloseDate >= day(2026, 4, 10))

        let after = snapshot.timeline(today: day(2026, 4, 10), calendar: utc)
        #expect(after.requirementsMetOn == day(2026, 4, 10))
        #expect(snapshot.bonusStatus(in: after) == .awaitingPayout)
    }

    @Test("A deposit without a hold ignores the hold period")
    func depositWithoutHold() {
        var deposit = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90))
        deposit.progress.fundedOn = day(2026, 1, 10)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 600, requirements: [deposit])

        let timeline = snapshot.timeline(today: day(2026, 6, 1), calendar: utc)

        #expect(timeline.requirements.first?.holdUntil == nil)
        #expect(timeline.requirementsMetOn == nil)
        #expect(snapshot.holds(in: timeline).isEmpty)
    }

    @Test("Holds are dropped once the bonus is forfeited or the account is closed")
    func holdsEndWithTheBonus() {
        var deposit = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90), keepsDeposit: true)
        deposit.progress.fundedOn = day(2026, 1, 10)
        let paid = account(opened: day(2026, 1, 1), bonus: 600, requirements: [deposit], received: day(2026, 2, 1))
        let forfeited = account(opened: day(2026, 1, 1), bonus: 600, requirements: [deposit], forfeited: true)
        let closed = account(opened: day(2026, 1, 1), closed: day(2026, 2, 1), bonus: 600, requirements: [deposit])
        let today = day(2026, 3, 1)

        #expect(paid.holds(in: paid.timeline(today: today, calendar: utc)).map(\.until) == [day(2026, 4, 10)])
        #expect(forfeited.holds(in: forfeited.timeline(today: today, calendar: utc)).isEmpty)
        #expect(closed.holds(in: closed.timeline(today: today, calendar: utc)).isEmpty)
    }

    @Test("An unfunded hold after the deposit window counts from the window's end")
    func holdAfterDepositWindow() {
        let hold = BonusRequirement(kind: .maintainBalance, amount: 15_000, window: .days(30), holdPeriod: .days(90), holdStart: .afterDepositWindow)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 1_000, requirements: [hold])

        let timeline = snapshot.timeline(today: day(2026, 1, 5), calendar: utc)

        #expect(timeline.requirements.first?.holdUntil == day(2026, 5, 1))
        #expect(timeline.qualificationEnd == day(2026, 5, 1))
    }

    @Test("Earliest close is the later of the minimum-open period and the payout")
    func earliestCloseUsesPolicy() {
        let policy = EarlyClosurePolicy(minimumOpen: .months(6), basis: .fromOpening, fee: 25, bonusClawback: true)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 300, earlyClosure: policy, received: day(2026, 3, 1))

        let timeline = snapshot.timeline(today: day(2026, 3, 5), calendar: utc)

        #expect(timeline.payoutIsActual)
        #expect(timeline.minimumOpenUntil == day(2026, 7, 1))
        #expect(timeline.earliestCloseDate == day(2026, 7, 1))
        #expect(timeline.earlyClosurePenalty == 325)
    }

    @Test("Earliest close waits for an unpaid bonus")
    func earliestCloseWaitsForPayout() {
        let policy = EarlyClosurePolicy(minimumOpen: .months(6))
        let payout = PayoutTiming(basis: .afterOpening, span: .months(9))
        let snapshot = account(opened: day(2026, 1, 1), bonus: 300, payout: payout, earlyClosure: policy)

        let timeline = snapshot.timeline(today: day(2026, 2, 1), calendar: utc)

        #expect(timeline.expectedPayout == day(2026, 10, 1))
        #expect(timeline.earliestCloseDate == day(2026, 10, 1))
    }

    @Test("Minimum-open period can count from the payout")
    func minimumOpenFromPayout() {
        let policy = EarlyClosurePolicy(minimumOpen: .days(90), basis: .fromBonusPayout, fee: 0, bonusClawback: true)
        let snapshot = account(opened: day(2026, 1, 1), bonus: 300, earlyClosure: policy, received: day(2026, 3, 1))

        let timeline = snapshot.timeline(today: day(2026, 3, 2), calendar: utc)

        #expect(timeline.earliestCloseDate == day(2026, 5, 30))
        #expect(timeline.earlyClosurePenalty == 300)
    }

    @Test("Accounts without a bonus only use the closure policy")
    func noBonusAccount() {
        let policy = EarlyClosurePolicy(minimumOpen: .days(180), fee: 25)
        let snapshot = account(opened: day(2026, 1, 1), earlyClosure: policy)

        let timeline = snapshot.timeline(today: day(2026, 2, 1), calendar: utc)

        #expect(snapshot.bonusStatus(in: timeline) == .noBonus)
        #expect(timeline.expectedPayout == nil)
        #expect(timeline.earliestCloseDate == day(2026, 6, 30))
        #expect(timeline.earlyClosurePenalty == 25)
    }

    @Test("A bonus with no requirements is waiting for payout from opening")
    func bonusWithoutRequirements() {
        let snapshot = account(opened: day(2026, 1, 1), bonus: 100, payout: PayoutTiming(basis: .afterRequirementsMet, span: .days(14)))

        let timeline = snapshot.timeline(today: day(2026, 1, 2), calendar: utc)

        #expect(snapshot.bonusStatus(in: timeline) == .awaitingPayout)
        #expect(timeline.expectedPayout == day(2026, 1, 15))
    }
}
