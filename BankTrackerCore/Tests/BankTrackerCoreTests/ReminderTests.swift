import Foundation
import Testing
@testable import BankTrackerCore

@Suite("Reminders")
struct ReminderTests {
    /// 8:00 on Mar 1, 2026; reminders go off at 9:00 with three days' notice.
    let now = day(2026, 3, 1).addingTimeInterval(8 * 3600)

    func reminders(_ accounts: [AccountSnapshot], offers: [OfferSnapshot] = [], now: Date? = nil, leadDays: Int = 3, limit: Int = 60) -> [Reminder] {
        ReminderPlanner(now: now ?? self.now, calendar: utc, leadDays: leadDays, minuteOfDay: 9 * 60, limit: limit)
            .reminders(accounts: accounts, offers: offers)
    }

    func at9(_ date: Date) -> Date { date.addingTimeInterval(9 * 3600) }

    @Test("A requirement not done gets a heads-up and a reminder on the day")
    func requirementDeadline() {
        let purchases = BonusRequirement(kind: .debitPurchases, count: 10, window: .days(30))
        let result = reminders([account(opened: day(2026, 2, 15), bonus: 300, requirements: [purchases])])

        #expect(result.map(\.kind) == [.requirementSoon, .requirementDue])
        #expect(result.map(\.date) == [at9(day(2026, 3, 14)), at9(day(2026, 3, 17))])
        #expect(result[0].title == "Make 10 debit card purchases")
        #expect(result[0].body == "Maple Bank Checking Account: due in 3 days, on \(DateText.format(day(2026, 3, 17))).")
        #expect(result[1].body == "Maple Bank Checking Account: due today.")
    }

    @Test("Done requirements and closed accounts get no deadline reminders")
    func nothingToDo() {
        var done = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90))
        done.progress.completedOn = day(2026, 2, 20)
        let finished = account(opened: day(2026, 2, 15), bonus: 300, requirements: [done], payout: PayoutTiming(span: .days(90)))
        let closed = account(opened: day(2026, 2, 15), closed: day(2026, 2, 28), bonus: 300, requirements: [BonusRequirement(kind: .deposit, amount: 1_000, window: .days(30))])

        // Only the reminder in case the bonus is late.
        #expect(reminders([finished]).map(\.kind) == [.bonusLate])
        #expect(reminders([closed]).isEmpty)
    }

    @Test("Reminders whose time has passed are left out, not sent late")
    func noBacktracking() {
        let deposit = BonusRequirement(kind: .deposit, amount: 1_000, window: .days(30))
        // Due Mar 3: the heads-up (Feb 28) has passed; the day-of reminder hasn't.
        let account = account(opened: day(2026, 2, 1), bonus: 300, requirements: [deposit])
        #expect(reminders([account]).map(\.kind) == [.requirementDue])

        // 10:00 on the due date: 9:00 has passed too.
        let late = day(2026, 3, 3).addingTimeInterval(10 * 3600)
        #expect(reminders([account], now: late).isEmpty)
    }

    @Test("Money on hold gets a reminder the day it can come out")
    func moneyFree() {
        var deposit = BonusRequirement(kind: .deposit, amount: 15_000, window: .days(30), holdPeriod: .days(90), keepsDeposit: true)
        let unfunded = reminders([account(opened: day(2026, 2, 15), bonus: 600, requirements: [deposit])])
        #expect(unfunded.map(\.kind) == [.requirementSoon, .requirementDue])

        deposit.progress.fundedOn = day(2026, 2, 20)
        let funded = reminders([account(opened: day(2026, 2, 15), bonus: 600, requirements: [deposit])])
        #expect(funded.map(\.kind) == [.moneyFree])
        #expect(funded.first?.date == at9(day(2026, 5, 21)))
        #expect(funded.first?.title == "You can withdraw $15,000")

        // Still on hold after the bonus posts.
        let paid = reminders([account(opened: day(2026, 2, 15), bonus: 600, requirements: [deposit], received: day(2026, 2, 25))])
        #expect(paid.map(\.kind).contains(.moneyFree))
    }

    @Test("Safe to close once the bonus is in, unless it's a keeper")
    func safeToClose() {
        let policy = EarlyClosurePolicy(minimumOpen: .months(6))
        let paid = account(opened: day(2026, 1, 10), bonus: 300, earlyClosure: policy, received: day(2026, 2, 20))
        let keeper = account(opened: day(2026, 1, 10), bonus: 300, earlyClosure: policy, received: day(2026, 2, 20), keeper: true)

        let result = reminders([paid, keeper])
        #expect(result.map(\.kind) == [.safeToClose])
        #expect(result.first?.date == at9(day(2026, 7, 10)))
    }

    @Test("A bonus that doesn't post on time gets a reminder the day after")
    func bonusLate() {
        var done = BonusRequirement(kind: .directDeposit, amount: 500, window: .days(90))
        done.progress.completedOn = day(2026, 2, 10)
        let waiting = account(opened: day(2026, 1, 1), bonus: 300, requirements: [done], payout: PayoutTiming(span: .days(30)))

        let result = reminders([waiting])
        #expect(result.map(\.kind) == [.bonusLate])
        #expect(result.first?.date == at9(day(2026, 3, 13)))
        #expect(result.first?.title == "$300 bonus from Maple Bank is late")
    }

    @Test("Offers you're considering get reminders before they end")
    func offerEnding() {
        let offer = OfferSnapshot(title: "$300 Maple Bank Savings offer", bonusAmount: 300, expirationDate: day(2026, 3, 10))
        let skipped = OfferSnapshot(title: "$200 Harbor offer", bonusAmount: 200, expirationDate: day(2026, 3, 10), isConsidering: false)

        let result = reminders([], offers: [offer, skipped])
        #expect(result.map(\.kind) == [.offerEndingSoon, .offerLastDay])
        #expect(result.map(\.title) == ["The $300 Maple Bank Savings offer ends in 3 days", "Last day for the $300 Maple Bank Savings offer"])
        #expect(result.allSatisfy { $0.offerID == offer.id })

        #expect(reminders([], offers: [offer], leadDays: 0).map(\.kind) == [.offerLastDay])
    }

    @Test("Soonest first, up to the limit, with stable ids")
    func orderingAndLimit() {
        let offers = (1...5).map { OfferSnapshot(title: "Offer \($0)", expirationDate: day(2026, 3, 10 + $0)) }
        let result = reminders([], offers: offers.reversed(), limit: 4)

        #expect(result.count == 4)
        #expect(result.map(\.date) == result.map(\.date).sorted())
        #expect(Set(result.map(\.id)).count == 4)
        #expect(reminders([], offers: offers, limit: 4) == result)
    }
}
