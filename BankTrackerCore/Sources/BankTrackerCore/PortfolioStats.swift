import Foundation

/// Totals and breakdowns across all your accounts.
public struct PortfolioStats: Hashable, Sendable {
    public struct YearTotal: Identifiable, Hashable, Sendable {
        public var year: Int
        public var amount: Decimal
        public var count: Int
        public var id: Int { year }
    }

    public struct BankTotal: Identifiable, Hashable, Sendable {
        public var bankName: String
        public var amount: Decimal
        public var count: Int
        public var id: String { bankName }

        public init(bankName: String, amount: Decimal, count: Int) {
            self.bankName = bankName
            self.amount = amount
            self.count = count
        }
    }

    public struct TypeCount: Identifiable, Hashable, Sendable {
        public var type: AccountType
        public var count: Int
        public var id: String { type.rawValue }
    }

    public struct PendingBonus: Identifiable, Hashable, Sendable {
        public var accountID: UUID
        public var accountName: String
        public var amount: Decimal
        public var expectedDate: Date?
        public var status: BonusStatus
        public var id: UUID { accountID }
    }

    public struct Highlight: Hashable, Sendable {
        public var accountName: String
        public var amount: Decimal
    }

    public var accountsOpened: Int
    public var openAccounts: Int
    public var closedAccounts: Int
    public var banksUsed: Int
    public var bonusesReceived: Int
    public var totalEarned: Decimal
    public var earnedThisYear: Decimal
    /// Bonuses still on the road: in progress or waiting to post.
    public var pending: [PendingBonus]
    public var forfeitedCount: Int
    /// Money sitting in open accounts (from the balances you've entered).
    public var fundsParked: Decimal
    public var feesPaid: Decimal
    public var averageBonus: Decimal?
    public var averageDaysToPayout: Int?
    public var largestBonus: Highlight?
    public var earnedByYear: [YearTotal]
    public var openedByYear: [YearTotal]
    public var earnedByBank: [BankTotal]
    public var accountsByType: [TypeCount]
    public var velocity: VelocitySummary

    public var pendingTotal: Decimal { pending.sum(\.amount) }
    public var netEarnings: Decimal { totalEarned - feesPaid }

    public init(accounts: [AccountSnapshot], today: Date = .now, calendar: Calendar = .current) {
        let thisYear = calendar.component(.year, from: today)

        var pending: [PendingBonus] = []
        var received: [(account: AccountSnapshot, date: Date, amount: Decimal)] = []
        var forfeited = 0
        for account in accounts {
            let timeline = account.timeline(today: today, calendar: calendar)
            let status = account.bonusStatus(in: timeline)
            switch status {
            case .received:
                if let date = account.bonusReceivedDate {
                    received.append((account, date, account.receivedBonusAmount))
                }
            case .inProgress, .awaitingPayout:
                pending.append(PendingBonus(
                    accountID: account.id,
                    accountName: account.displayName,
                    amount: account.terms.bonusAmount,
                    expectedDate: timeline.expectedPayout,
                    status: status
                ))
            case .forfeited:
                forfeited += 1
            case .noBonus:
                break
            }
        }

        accountsOpened = accounts.count
        openAccounts = accounts.filter(\.isOpen).count
        closedAccounts = accountsOpened - openAccounts
        banksUsed = Set(accounts.map { $0.bankID?.uuidString ?? $0.bankName }).count
        bonusesReceived = received.count
        totalEarned = received.sum(\.amount)
        earnedThisYear = received.filter { calendar.component(.year, from: $0.date) == thisYear }.sum(\.amount)
        self.pending = pending.sorted { ($0.expectedDate ?? .distantFuture) < ($1.expectedDate ?? .distantFuture) }
        forfeitedCount = forfeited
        fundsParked = accounts.filter(\.isOpen).sum(\.currentBalance)
        feesPaid = accounts.sum(\.feesPaid)

        if received.isEmpty {
            averageBonus = nil
            averageDaysToPayout = nil
            largestBonus = nil
        } else {
            averageBonus = totalEarned / Decimal(received.count)
            let days = received.map { calendar.dayCount(from: $0.account.openedDate, to: $0.date) }
            averageDaysToPayout = days.reduce(0, +) / days.count
            largestBonus = received.max { $0.amount < $1.amount }.map { Highlight(accountName: $0.account.displayName, amount: $0.amount) }
        }

        earnedByYear = Dictionary(grouping: received) { calendar.component(.year, from: $0.date) }
            .map { YearTotal(year: $0.key, amount: $0.value.sum(\.amount), count: $0.value.count) }
            .sorted { $0.year < $1.year }
        openedByYear = Dictionary(grouping: accounts) { calendar.component(.year, from: $0.openedDate) }
            .map { YearTotal(year: $0.key, amount: 0, count: $0.value.count) }
            .sorted { $0.year < $1.year }
        earnedByBank = Dictionary(grouping: received) { $0.account.bankName }
            .map { BankTotal(bankName: $0.key, amount: $0.value.sum(\.amount), count: $0.value.count) }
            .sorted { ($0.amount, $1.bankName) > ($1.amount, $0.bankName) }
        accountsByType = Dictionary(grouping: accounts, by: \.accountType)
            .map { TypeCount(type: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        velocity = VelocitySummary(accounts: accounts, today: today, calendar: calendar)
    }
}
