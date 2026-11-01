import Foundation

public enum RuleOutcome: Hashable, Sendable {
    /// The rule is satisfied.
    case pass
    /// The app can't check this; you need to confirm it yourself.
    case needsReview
    /// Blocked until the given date.
    case blockedUntil(Date)
    /// Blocked by an account that's still open. The estimate assumes you close it
    /// on its earliest penalty-free date.
    case blockedUntilClosed(estimate: Date?)
    /// Blocked for good.
    case blocked

    public var isBlocking: Bool {
        switch self {
        case .pass, .needsReview: false
        case .blockedUntil, .blockedUntilClosed, .blocked: true
        }
    }
}

public struct RuleEvaluation: Identifiable, Hashable, Sendable {
    public var rule: EligibilityRule
    public var outcome: RuleOutcome
    public var explanation: String
    public var relatedAccountIDs: [UUID]

    public var id: UUID { rule.id }
}

public enum EligibilityVerdict: Hashable, Sendable {
    case eligible
    case noRulesEntered
    case needsReview(count: Int)
    case eligibleOn(Date)
    case closeAccountFirst(estimate: Date?)
    case notEligible
}

/// How many accounts you've opened recently. Some banks decline applicants who open too many.
public struct VelocitySummary: Hashable, Sendable {
    public var openedLast6Months: Int
    public var openedLast12Months: Int
    public var openedLast24Months: Int
    public var hardPullsLast12Months: Int
    public var chexSystemsLast12Months: Int

    public init(accounts: [AccountSnapshot], today: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: today)
        func opened(withinMonths months: Int) -> [AccountSnapshot] {
            let cutoff = calendar.date(byAdding: .month, value: -months, to: today) ?? today
            return accounts.filter { $0.openedDate >= cutoff }
        }
        let lastYear = opened(withinMonths: 12)
        openedLast6Months = opened(withinMonths: 6).count
        openedLast12Months = lastYear.count
        openedLast24Months = opened(withinMonths: 24).count
        hardPullsLast12Months = lastYear.filter { $0.inquiry == .hardPull }.count
        chexSystemsLast12Months = lastYear.filter { $0.inquiry == .chexSystems }.count
    }
}

public struct EligibilityReport: Hashable, Sendable {
    public var verdict: EligibilityVerdict
    public var evaluations: [RuleEvaluation]
    /// Your accounts at the offer's bank, newest first.
    public var bankHistory: [AccountSnapshot]
    public var velocity: VelocitySummary
    /// The offer expires before the date you'd become eligible.
    public var expiresBeforeEligible: Bool
    public var headline: String
}

/// Checks an offer's rules against your account history.
public struct EligibilityEngine: Sendable {
    public var today: Date
    public var calendar: Calendar
    /// USPS code of the state you live in, for state-restricted offers.
    public var residenceState: String?

    public init(today: Date = .now, calendar: Calendar = .current, residenceState: String? = nil) {
        self.today = today
        self.calendar = calendar
        self.residenceState = residenceState
    }

    /// - Parameters:
    ///   - history: All your accounts. Only those at `bankID` are considered.
    ///   - excludedIDs: Accounts to ignore, e.g. ones already opened with this same offer.
    public func evaluate(
        rules: [EligibilityRule],
        bankID: UUID?,
        accountType: AccountType,
        offerExpiration: Date? = nil,
        history: [AccountSnapshot],
        excluding excludedIDs: Set<UUID> = []
    ) -> EligibilityReport {
        let today = calendar.startOfDay(for: today)
        let atBank = bankID.map { id in
            history.filter { $0.bankID == id && !excludedIDs.contains($0.id) }
        } ?? []

        let evaluations = rules.map { evaluate($0, accountType: accountType, accounts: atBank, today: today) }
        let verdict = Self.verdict(for: evaluations)

        let eligibleDate: Date? = switch verdict {
        case .eligibleOn(let date): date
        case .closeAccountFirst(let estimate): estimate
        default: nil
        }
        var expiresFirst = false
        if let eligibleDate, let offerExpiration {
            expiresFirst = eligibleDate > calendar.startOfDay(for: offerExpiration)
        }

        return EligibilityReport(
            verdict: verdict,
            evaluations: evaluations,
            bankHistory: atBank.sorted { $0.openedDate > $1.openedDate },
            velocity: VelocitySummary(accounts: history, today: today, calendar: calendar),
            expiresBeforeEligible: expiresFirst,
            headline: Self.headline(for: verdict, expiresFirst: expiresFirst)
        )
    }

    static func verdict(for evaluations: [RuleEvaluation]) -> EligibilityVerdict {
        guard !evaluations.isEmpty else { return .noRulesEntered }
        var latestDate: Date?
        var needsClosing = false
        var closingDateUnknown = false
        var reviewCount = 0
        for evaluation in evaluations {
            switch evaluation.outcome {
            case .blocked:
                return .notEligible
            case .blockedUntil(let date):
                latestDate = max(latestDate ?? date, date)
            case .blockedUntilClosed(let estimate):
                needsClosing = true
                if let estimate {
                    latestDate = max(latestDate ?? estimate, estimate)
                } else {
                    closingDateUnknown = true
                }
            case .needsReview:
                reviewCount += 1
            case .pass:
                break
            }
        }
        if needsClosing { return .closeAccountFirst(estimate: closingDateUnknown ? nil : latestDate) }
        if let latestDate { return .eligibleOn(latestDate) }
        if reviewCount > 0 { return .needsReview(count: reviewCount) }
        return .eligible
    }

    static func headline(for verdict: EligibilityVerdict, expiresFirst: Bool) -> String {
        let expiryNote = expiresFirst ? " The offer expires before then." : ""
        switch verdict {
        case .eligible:
            return "You're eligible for this offer."
        case .noRulesEntered:
            return "No restrictions entered. Add the offer's eligibility rules to check them against your history."
        case .needsReview(let count):
            return count == 1
                ? "Looks eligible. 1 item needs your confirmation."
                : "Looks eligible. \(count) items need your confirmation."
        case .eligibleOn(let date):
            return "Not yet. You'll be eligible on \(DateText.format(date))." + expiryNote
        case .closeAccountFirst(let estimate):
            let estimateText = estimate.map { " Estimated eligibility: \(DateText.format($0))." } ?? ""
            return "Not while your current account is open. Close it first." + estimateText + expiryNote
        case .notEligible:
            return "Not eligible for this offer."
        }
    }

    // MARK: - Individual rules

    private func evaluate(_ rule: EligibilityRule, accountType: AccountType, accounts: [AccountSnapshot], today: Date) -> RuleEvaluation {
        let scoped = rule.scope == .anyAccount ? accounts : accounts.filter { $0.accountType == accountType }
        let noun = rule.scope == .anyAccount ? "account" : "\(accountType.inlineName) account"
        let bonusNoun = rule.scope == .anyAccount ? "bonus" : "\(accountType.inlineName) bonus"

        func result(_ outcome: RuleOutcome, _ explanation: String, _ related: [AccountSnapshot] = []) -> RuleEvaluation {
            RuleEvaluation(rule: rule, outcome: outcome, explanation: explanation, relatedAccountIDs: related.map(\.id))
        }
        func earliestClose(_ account: AccountSnapshot) -> Date {
            max(today, account.timeline(today: today, calendar: calendar).earliestCloseDate)
        }

        switch rule.kind {
        case .notCurrentCustomer:
            let open = scoped.filter(\.isOpen)
            guard !open.isEmpty else { return result(.pass, "You have no open \(noun) here.") }
            let estimate = open.map(earliestClose).max()
            var text = "Still open: \(describe(open))."
            if let estimate {
                text += estimate <= today
                    ? " You can close it now without a penalty."
                    : " Earliest penalty-free close: \(DateText.format(estimate))."
            }
            return result(.blockedUntilClosed(estimate: estimate), text, open)

        case .noAccountWithin:
            var blockers: [AccountSnapshot] = []
            var openBlockers: [AccountSnapshot] = []
            var latest: Date?
            for account in scoped {
                let until: Date
                if let closed = account.closedDate {
                    until = rule.span.added(to: calendar.startOfDay(for: closed), calendar: calendar)
                    guard until > today else { continue }
                } else {
                    until = rule.span.added(to: earliestClose(account), calendar: calendar)
                    openBlockers.append(account)
                }
                blockers.append(account)
                latest = max(latest ?? until, until)
            }
            guard let latest else { return result(.pass, "No \(noun) here in the past \(rule.span.displayText).") }
            if !openBlockers.isEmpty {
                return result(
                    .blockedUntilClosed(estimate: latest),
                    "Still open: \(describe(openBlockers)). You qualify \(rule.span.displayText) after closing, around \(DateText.format(latest)) if you close on the earliest penalty-free date.",
                    blockers
                )
            }
            return result(.blockedUntil(latest), "Closed within the past \(rule.span.displayText): \(describe(blockers)). Eligible on \(DateText.format(latest)).", blockers)

        case .noBonusWithin:
            var blockers: [AccountSnapshot] = []
            var latest: Date?
            for account in scoped {
                let timeline = account.timeline(today: today, calendar: calendar)
                guard account.bonusStatus(in: timeline).countsAsBonus else { continue }
                let reference = switch rule.measuredFrom {
                case .accountOpenDate: account.openedDate
                case .bonusPaidDate: account.bonusReceivedDate ?? timeline.expectedPayout ?? account.openedDate
                }
                let until = rule.span.added(to: calendar.startOfDay(for: reference), calendar: calendar)
                guard until > today else { continue }
                blockers.append(account)
                latest = max(latest ?? until, until)
            }
            guard let latest else { return result(.pass, "No \(bonusNoun) here in the past \(rule.span.displayText).") }
            return result(.blockedUntil(latest), "Recent bonus: \(describeBonuses(blockers)). Eligible on \(DateText.format(latest)).", blockers)

        case .oneAccountPer:
            var blockers: [AccountSnapshot] = []
            var latest: Date?
            for account in scoped {
                let until = rule.span.added(to: calendar.startOfDay(for: account.openedDate), calendar: calendar)
                guard until > today else { continue }
                blockers.append(account)
                latest = max(latest ?? until, until)
            }
            guard let latest else { return result(.pass, "No \(noun) opened here in the past \(rule.span.displayText).") }
            return result(.blockedUntil(latest), "Opened within the past \(rule.span.displayText): \(describe(blockers)). Eligible on \(DateText.format(latest)).", blockers)

        case .neverHadAccount:
            guard !scoped.isEmpty else { return result(.pass, "You've never had a \(noun) here.") }
            return result(.blocked, "You've had \(scoped.count == 1 ? "a \(noun)" : "\(scoped.count) \(noun)s") here before: \(describe(scoped)).", scoped)

        case .oncePerLifetime:
            let bonuses = scoped.filter { $0.bonusStatus(today: today, calendar: calendar).countsAsBonus }
            guard !bonuses.isEmpty else { return result(.pass, "No previous \(bonusNoun) here.") }
            return result(.blocked, "You've already earned (or are earning) a bonus here: \(describeBonuses(bonuses)).", bonuses)

        case .stateRestriction:
            let states = rule.states.map { $0.uppercased() }
            guard !states.isEmpty else { return result(.needsReview, "No states listed. Add them to check automatically.") }
            guard let residence = residenceState?.uppercased(), !residence.isEmpty else {
                return result(.needsReview, "Set your state of residence in Settings to check this automatically.")
            }
            if states.contains(residence) { return result(.pass, "Available in \(residence).") }
            return result(.blocked, "Not available in \(residence). Only \(states.joined(separator: ", ")).")

        case .manual:
            if rule.isConfirmed { return result(.pass, "You confirmed you meet this.") }
            return result(.needsReview, rule.note.isEmpty ? "Check the offer terms yourself." : "Check yourself: \(rule.note)")
        }
    }

    private func describe(_ accounts: [AccountSnapshot]) -> String {
        accounts
            .sorted { $0.openedDate > $1.openedDate }
            .map { account in
                if let closed = account.closedDate {
                    return "\(account.productLabel) (opened \(DateText.format(account.openedDate)), closed \(DateText.format(closed)))"
                }
                return "\(account.productLabel) (opened \(DateText.format(account.openedDate)))"
            }
            .joined(separator: "; ")
    }

    private func describeBonuses(_ accounts: [AccountSnapshot]) -> String {
        accounts
            .sorted { $0.openedDate > $1.openedDate }
            .map { account in
                if let received = account.bonusReceivedDate {
                    return "\(account.productLabel), \(Money.format(account.receivedBonusAmount)) paid \(DateText.format(received))"
                }
                let expected = account.timeline(today: today, calendar: calendar).expectedPayout
                let expectedText = expected.map { ", expected by \(DateText.format($0))" } ?? ""
                return "\(account.productLabel), \(Money.format(account.terms.bonusAmount)) pending\(expectedText)"
            }
            .joined(separator: "; ")
    }
}
