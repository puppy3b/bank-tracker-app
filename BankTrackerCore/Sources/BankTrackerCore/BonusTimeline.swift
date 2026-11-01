import Foundation

/// Key dates for an account: requirement deadlines, when the bonus should post, and the
/// first day you can close the account without losing money.
///
/// Estimates are deliberately conservative: until a requirement is marked done, the
/// timeline assumes you finish it on its deadline, which gives the latest likely payout.
public struct BonusTimeline: Hashable, Sendable {
    public struct RequirementSchedule: Identifiable, Hashable, Sendable {
        public var id: UUID
        /// Complete (or fund) by this date. Nil when the offer gives no deadline.
        public var deadline: Date?
        /// Requirements with a hold: keep the money in the account until this date, when it
        /// can be withdrawn. Before funding it's an estimate.
        public var holdUntil: Date?
        /// When the requirement was met, or nil while it's outstanding.
        public var satisfiedOn: Date?

        public var isSatisfied: Bool { satisfiedOn != nil }
    }

    public var openedDate: Date
    public var requirements: [RequirementSchedule]
    /// The last deadline across all requirements, including balance holds.
    public var qualificationEnd: Date?
    /// When every requirement was met; nil while any is outstanding.
    public var requirementsMetOn: Date?
    /// The actual payout date once received; otherwise the latest date the terms allow.
    public var expectedPayout: Date?
    public var payoutIsActual: Bool
    /// End of the minimum-open period in the early-closure policy.
    public var minimumOpenUntil: Date?
    /// First day you can close without a fee, a clawback, or giving up an unpaid bonus.
    public var earliestCloseDate: Date
    /// What closing before `minimumOpenUntil` would cost: the fee plus any clawed-back bonus.
    public var earlyClosurePenalty: Decimal

    public func schedule(for requirementID: UUID) -> RequirementSchedule? {
        requirements.first { $0.id == requirementID }
    }

    /// The last deadline (or balance-hold end) among requirements not met yet.
    public var outstandingDeadline: Date? {
        requirements.filter { !$0.isSatisfied }.compactMap { $0.holdUntil ?? $0.deadline }.max()
    }

    public init(account: AccountSnapshot, today: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: today)
        let opened = calendar.startOfDay(for: account.openedDate)
        let terms = account.terms
        let tracksBonus = account.hasBonus && !account.bonusForfeited

        var schedules: [RequirementSchedule] = []
        if account.hasBonus {
            for requirement in terms.requirements {
                let deadline = requirement.window.isZero ? nil : requirement.window.added(to: opened, calendar: calendar)
                let funded = requirement.progress.fundedOn.map { calendar.startOfDay(for: $0) }

                var holdUntil: Date?
                if requirement.hasHold, !requirement.holdPeriod.isZero {
                    // Before funding, assume it happens on the deadline (or today if there is none).
                    let start = switch requirement.holdStart {
                    case .fromOpening: opened
                    case .afterDepositWindow: deadline ?? funded ?? max(today, opened)
                    case .afterFunding: funded ?? deadline ?? max(today, opened)
                    }
                    holdUntil = requirement.holdPeriod.added(to: start, calendar: calendar)
                }

                var satisfiedOn = requirement.progress.completedOn.map { calendar.startOfDay(for: $0) }
                // A funded hold completes itself once the hold period is over.
                if satisfiedOn == nil, requirement.hasHold, funded != nil, let holdUntil, holdUntil <= today {
                    satisfiedOn = holdUntil
                }
                schedules.append(RequirementSchedule(id: requirement.id, deadline: deadline, holdUntil: holdUntil, satisfiedOn: satisfiedOn))
            }
        }

        let qualificationEnd = schedules.compactMap { $0.holdUntil ?? $0.deadline }.max()

        let requirementsMetOn: Date?
        if !account.hasBonus {
            requirementsMetOn = nil
        } else if schedules.isEmpty {
            requirementsMetOn = opened
        } else if schedules.allSatisfy(\.isSatisfied) {
            requirementsMetOn = schedules.compactMap(\.satisfiedOn).max()
        } else {
            requirementsMetOn = nil
        }

        // Outstanding requirements can't finish before today, and are assumed to finish by their deadline.
        let projectedMet = requirementsMetOn ?? schedules
            .map { $0.satisfiedOn ?? max(today, $0.holdUntil ?? $0.deadline ?? today) }
            .max() ?? opened

        var expectedPayout: Date?
        var payoutIsActual = false
        if let received = account.bonusReceivedDate {
            expectedPayout = calendar.startOfDay(for: received)
            payoutIsActual = true
        } else if tracksBonus {
            let base = switch terms.payout.basis {
            case .afterRequirementsMet: projectedMet
            case .afterQualificationPeriod: qualificationEnd ?? projectedMet
            case .afterOpening: opened
            }
            expectedPayout = terms.payout.span.added(to: base, calendar: calendar)
        }

        let policy = terms.earlyClosure
        var minimumOpenUntil: Date?
        if !policy.minimumOpen.isZero {
            let start = switch policy.basis {
            case .fromOpening: opened
            case .fromBonusPayout: expectedPayout ?? opened
            }
            minimumOpenUntil = policy.minimumOpen.added(to: start, calendar: calendar)
        }

        var closeCandidates = [opened]
        if let minimumOpenUntil { closeCandidates.append(minimumOpenUntil) }
        if tracksBonus {
            if let expectedPayout { closeCandidates.append(expectedPayout) }
            closeCandidates.append(contentsOf: schedules.compactMap(\.holdUntil))
        }

        let clawback = policy.bonusClawback && tracksBonus ? (account.bonusReceivedAmount ?? terms.bonusAmount) : 0

        self.openedDate = opened
        self.requirements = schedules
        self.qualificationEnd = qualificationEnd
        self.requirementsMetOn = requirementsMetOn
        self.expectedPayout = expectedPayout
        self.payoutIsActual = payoutIsActual
        self.minimumOpenUntil = minimumOpenUntil
        self.earliestCloseDate = closeCandidates.max() ?? opened
        self.earlyClosurePenalty = policy.fee + clawback
    }
}
