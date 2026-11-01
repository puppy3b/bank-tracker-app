import Foundation

/// A notification to show at a set time about something coming up.
public struct Reminder: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// A requirement not done yet, a few days before its deadline.
        case requirementSoon
        /// A requirement not done yet, on the day it's due.
        case requirementDue
        /// Money on hold can come out.
        case moneyFree
        /// The account can be closed without a penalty.
        case safeToClose
        /// The bonus hasn't posted by the date the terms promise.
        case bonusLate
        /// An offer you're considering ends in a few days.
        case offerEndingSoon
        /// The last day to apply for an offer you're considering.
        case offerLastDay
    }

    /// Stable for the same event, so rescheduling replaces rather than duplicates.
    public var id: String
    public var kind: Kind
    /// When to show it.
    public var date: Date
    public var title: String
    public var body: String
    public var accountID: UUID?
    public var offerID: UUID?
}

/// Works out which reminders to schedule: requirements coming due, money that can come out,
/// accounts that can be closed, late bonuses and offers about to end. Each goes off at the same
/// time of day. Reminders whose time has already passed are left out rather than sent late.
public struct ReminderPlanner: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// Days of notice before a deadline or an offer's end, on top of the reminder on the day.
    /// Zero means the day itself only.
    public var leadDays: Int
    /// When reminders go off, in minutes after midnight.
    public var minuteOfDay: Int
    /// At most this many, soonest first. iOS keeps up to 64 scheduled notifications per app.
    public var limit: Int

    public init(now: Date = .now, calendar: Calendar = .current, leadDays: Int = 3, minuteOfDay: Int = 9 * 60, limit: Int = 60) {
        self.now = now
        self.calendar = calendar
        self.leadDays = leadDays
        self.minuteOfDay = minuteOfDay
        self.limit = limit
    }

    /// Soonest first; only reminders still in the future.
    public func reminders(accounts: [AccountSnapshot], offers: [OfferSnapshot]) -> [Reminder] {
        var reminders: [Reminder] = []
        for account in accounts where account.isOpen {
            reminders += accountReminders(account)
        }
        for offer in offers where offer.isConsidering {
            reminders += offerReminders(offer)
        }
        let upcoming = reminders
            .filter { $0.date > now }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        return Array(upcoming.prefix(limit))
    }

    private func accountReminders(_ account: AccountSnapshot) -> [Reminder] {
        let timeline = account.timeline(today: now, calendar: calendar)
        let name = account.displayName
        var reminders: [Reminder] = []

        switch account.bonusStatus(in: timeline) {
        case .inProgress:
            for requirement in account.terms.requirements {
                guard let schedule = timeline.schedule(for: requirement.id), !schedule.isSatisfied, let deadline = schedule.deadline else { continue }
                // Money already in only has to stay put; its reminder is the day it can come out.
                if requirement.hasHold, requirement.progress.fundedOn != nil { continue }

                let title = requirement.kind == .maintainBalance
                    ? "Fund \(Money.format(requirement.amount)) for the balance requirement"
                    : requirement.actionTitle
                let progress = requirement.progressSummary.map { " So far: \($0)." } ?? ""
                if leadDays > 0, let soon = calendar.date(byAdding: .day, value: -leadDays, to: deadline) {
                    let when = leadDays == 1 ? "tomorrow" : "in \(leadDays) days, on \(DateText.format(deadline))"
                    reminders.append(reminder(
                        "req-\(requirement.id)-soon", .requirementSoon, on: soon,
                        title: title, body: "\(name): due \(when).\(progress)", accountID: account.id
                    ))
                }
                reminders.append(reminder(
                    "req-\(requirement.id)-due", .requirementDue, on: deadline,
                    title: title, body: "\(name): due today.\(progress)", accountID: account.id
                ))
            }

        case .awaitingPayout:
            if let expected = timeline.expectedPayout, !timeline.payoutIsActual,
               let dayAfter = calendar.date(byAdding: .day, value: 1, to: expected) {
                reminders.append(reminder(
                    "late-\(account.id)", .bonusLate, on: dayAfter,
                    title: "\(Money.format(account.terms.bonusAmount)) bonus from \(account.bankName) is late",
                    body: "\(name): it was expected by \(DateText.format(expected)). Check the account or contact the bank.",
                    accountID: account.id
                ))
            }

        case .received, .forfeited:
            if !account.isKeeper {
                reminders.append(reminder(
                    "close-\(account.id)", .safeToClose, on: timeline.earliestCloseDate,
                    title: "You can close \(name)",
                    body: "There's no penalty for closing it from today. Mark it as a keeper if you'd rather keep it.",
                    accountID: account.id
                ))
            }

        case .noBonus:
            break
        }

        for hold in account.holds(in: timeline) where hold.fundedOn != nil {
            let money = hold.amount > 0 ? Money.format(hold.amount) : "the money"
            reminders.append(reminder(
                "hold-\(hold.id)", .moneyFree, on: hold.until,
                title: "You can withdraw \(money)",
                body: "\(name): the hold ends today, so the money can come out.",
                accountID: account.id
            ))
        }
        return reminders
    }

    private func offerReminders(_ offer: OfferSnapshot) -> [Reminder] {
        guard let expiration = offer.expirationDate else { return [] }
        var reminders: [Reminder] = []
        if leadDays > 0, let soon = calendar.date(byAdding: .day, value: -leadDays, to: expiration) {
            let when = leadDays == 1 ? "tomorrow" : "in \(leadDays) days"
            reminders.append(reminder(
                "offer-\(offer.id)-soon", .offerEndingSoon, on: soon,
                title: "The \(offer.title) ends \(when)",
                body: "Apply by \(DateText.format(expiration)) to get it.",
                offerID: offer.id
            ))
        }
        reminders.append(reminder(
            "offer-\(offer.id)-last", .offerLastDay, on: expiration,
            title: "Last day for the \(offer.title)",
            body: "Apply today to get it.",
            offerID: offer.id
        ))
        return reminders
    }

    /// A reminder at the set time of day on `day`.
    private func reminder(
        _ id: String, _ kind: Reminder.Kind, on day: Date,
        title: String, body: String, accountID: UUID? = nil, offerID: UUID? = nil
    ) -> Reminder {
        // Set the clock time rather than add minutes, which would drift on daylight-saving days.
        let start = calendar.startOfDay(for: day)
        let date = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: start) ?? start
        return Reminder(id: id, kind: kind, date: date, title: title, body: body, accountID: accountID, offerID: offerID)
    }
}
