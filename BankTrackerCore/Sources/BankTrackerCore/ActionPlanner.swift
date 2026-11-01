import Foundation

/// The parts of an offer the action planner needs.
public struct OfferSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var bonusAmount: Decimal
    public var expirationDate: Date?
    public var isConsidering: Bool

    public init(id: UUID = UUID(), title: String, bonusAmount: Decimal = 0, expirationDate: Date? = nil, isConsidering: Bool = true) {
        self.id = id
        self.title = title
        self.bonusAmount = bonusAmount
        self.expirationDate = expirationDate
        self.isConsidering = isConsidering
    }
}

/// One thing to do or watch for, shown on the dashboard.
public struct ActionItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// A requirement still to complete.
        case requirement
        /// Money that must stay in the account until a date.
        case keepBalance
        /// Requirements done; waiting for the bonus to post.
        case awaitingBonus
        /// The bonus is later than the terms promise.
        case bonusOverdue
        /// Safe to close now.
        case readyToClose
        /// Can close after a future date.
        case closeLater
        /// An offer you're considering ends soon.
        case offerExpiring
        /// A monthly fee and how you plan to avoid it.
        case avoidFee
    }

    public enum Urgency: Int, Comparable, Sendable {
        case overdue
        case dueSoon
        case upcoming
        case waiting
        case info

        public static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: String
    public var kind: Kind
    public var urgency: Urgency
    public var title: String
    public var detail: String
    public var date: Date?
    public var amount: Decimal?
    public var accountID: UUID?
    public var offerID: UUID?
}

/// Turns accounts and offers into a to-do list.
public struct ActionPlanner: Sendable {
    public var today: Date
    public var calendar: Calendar
    /// Deadlines within this many days count as due soon.
    public var dueSoonDays: Int
    /// Offers expiring within this many days get a reminder.
    public var offerReminderDays: Int

    public init(today: Date = .now, calendar: Calendar = .current, dueSoonDays: Int = 7, offerReminderDays: Int = 14) {
        self.today = today
        self.calendar = calendar
        self.dueSoonDays = dueSoonDays
        self.offerReminderDays = offerReminderDays
    }

    /// Most urgent first; within the same urgency, earliest date first.
    public func items(accounts: [AccountSnapshot], offers: [OfferSnapshot] = []) -> [ActionItem] {
        let today = calendar.startOfDay(for: today)
        var items: [ActionItem] = []
        for account in accounts where account.isOpen {
            items += accountItems(account, today: today)
        }
        for offer in offers where offer.isConsidering {
            if let item = offerItem(offer, today: today) { items.append(item) }
        }
        return items.sorted {
            ($0.urgency, $0.date ?? .distantFuture, $0.title) < ($1.urgency, $1.date ?? .distantFuture, $1.title)
        }
    }

    private func accountItems(_ account: AccountSnapshot, today: Date) -> [ActionItem] {
        var items: [ActionItem] = []
        let timeline = account.timeline(today: today, calendar: calendar)
        let name = account.displayName
        let bonus = Money.format(account.terms.bonusAmount)

        switch account.bonusStatus(in: timeline) {
        case .inProgress:
            for requirement in account.terms.requirements {
                guard let schedule = timeline.schedule(for: requirement.id), !schedule.isSatisfied else { continue }
                // Once the money is in, all that's left is to leave it there; see the holds below.
                if requirement.hasHold, requirement.progress.fundedOn != nil, schedule.holdUntil != nil { continue }

                let title = requirement.kind == .maintainBalance
                    ? "Fund \(Money.format(requirement.amount)) for the balance requirement"
                    : requirement.actionTitle
                var detail = name
                if let deadline = schedule.deadline { detail += ", due \(DateText.format(deadline))" }
                if let progress = requirement.progressSummary { detail += ". So far: \(progress)" }
                items.append(ActionItem(
                    id: "req-\(requirement.id)",
                    kind: .requirement,
                    urgency: urgency(for: schedule.deadline, today: today),
                    title: title,
                    detail: detail,
                    date: schedule.deadline,
                    amount: requirement.kind.usesAmount && requirement.amount > 0 ? requirement.amount : nil,
                    accountID: account.id
                ))
            }

        case .awaitingPayout:
            if let expected = timeline.expectedPayout {
                if expected < today {
                    items.append(ActionItem(
                        id: "late-\(account.id)",
                        kind: .bonusOverdue,
                        urgency: .overdue,
                        title: "\(bonus) bonus from \(account.bankName) is late",
                        detail: "\(name): expected by \(DateText.format(expected)). Check the account or contact the bank.",
                        date: expected,
                        amount: account.terms.bonusAmount,
                        accountID: account.id
                    ))
                } else {
                    items.append(ActionItem(
                        id: "await-\(account.id)",
                        kind: .awaitingBonus,
                        urgency: .waiting,
                        title: "Expect \(bonus) from \(account.bankName)",
                        detail: "\(name): by \(DateText.format(expected)).",
                        date: expected,
                        amount: account.terms.bonusAmount,
                        accountID: account.id
                    ))
                }
            }

        case .received, .forfeited:
            guard !account.isKeeper else { break }
            let closeDate = timeline.earliestCloseDate
            if closeDate <= today {
                items.append(ActionItem(
                    id: "close-\(account.id)",
                    kind: .readyToClose,
                    urgency: .info,
                    title: "You can close \(name)",
                    detail: "No penalty since \(DateText.format(closeDate)). Mark it as a keeper to stop this reminder.",
                    date: closeDate,
                    accountID: account.id
                ))
            } else {
                var detail = "Earliest penalty-free close."
                if timeline.earlyClosurePenalty > 0 {
                    detail += " Closing sooner costs \(Money.format(timeline.earlyClosurePenalty))."
                }
                items.append(ActionItem(
                    id: "close-\(account.id)",
                    kind: .closeLater,
                    urgency: .info,
                    title: "Close \(name) after \(DateText.format(closeDate))",
                    detail: detail,
                    date: closeDate,
                    accountID: account.id
                ))
            }

        case .noBonus:
            break
        }

        for hold in account.holds(in: timeline) where hold.fundedOn != nil && hold.until > today {
            items.append(ActionItem(
                id: "hold-\(hold.id)",
                kind: .keepBalance,
                urgency: .waiting,
                title: "Keep \(Money.format(hold.amount)) in \(name)",
                detail: "Don't withdraw before \(DateText.format(hold.until)).",
                date: hold.until,
                amount: hold.amount,
                accountID: account.id
            ))
        }

        let fee = account.terms.maintenanceFee
        if fee.hasFee {
            items.append(ActionItem(
                id: "fee-\(account.id)",
                kind: .avoidFee,
                urgency: .info,
                title: "Avoid the \(Money.format(fee.monthlyFee))/month fee at \(name)",
                detail: fee.plannedWaiver?.summary ?? "No waiver recorded. Add one in the account's fee details.",
                amount: fee.monthlyFee,
                accountID: account.id
            ))
        }
        return items
    }

    private func offerItem(_ offer: OfferSnapshot, today: Date) -> ActionItem? {
        guard let expiration = offer.expirationDate.map({ calendar.startOfDay(for: $0) }), expiration >= today else { return nil }
        let days = calendar.dayCount(from: today, to: expiration)
        guard days <= offerReminderDays else { return nil }
        return ActionItem(
            id: "offer-\(offer.id)",
            kind: .offerExpiring,
            urgency: days <= dueSoonDays ? .dueSoon : .upcoming,
            title: "\(offer.title) ends \(DateText.format(expiration))",
            detail: days == 0 ? "Last day to apply." : "\(days) \(days == 1 ? "day" : "days") left to apply.",
            date: expiration,
            amount: offer.bonusAmount,
            offerID: offer.id
        )
    }

    private func urgency(for deadline: Date?, today: Date) -> ActionItem.Urgency {
        guard let deadline else { return .upcoming }
        if deadline < today { return .overdue }
        if calendar.dayCount(from: today, to: deadline) <= dueSoonDays { return .dueSoon }
        return .upcoming
    }
}
