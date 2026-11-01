import SwiftUI
import BankTrackerCore

/// The verdict for an offer, with one row per rule and your history at the bank.
struct EligibilitySections: View {
    let report: EligibilityReport
    let accountType: AccountType
    var showsHistory = true

    var body: some View {
        Section {
            VerdictBanner(report: report)
            ForEach(report.evaluations) { evaluation in
                RuleEvaluationRow(evaluation: evaluation, accountType: accountType)
            }
        } header: {
            Text("Eligibility")
        } footer: {
            Text(report.velocitySummary)
        }
        if showsHistory {
            Section("Your history at this bank") {
                if report.bankHistory.isEmpty {
                    Text("No accounts recorded at this bank.")
                        .foregroundStyle(.secondary)
                }
                ForEach(report.bankHistory) { account in
                    HistoryRow(account: account)
                }
            }
        }
    }
}

/// The verdict and rule results as a card, for the offer page.
struct EligibilityCard: View {
    let report: EligibilityReport
    let accountType: AccountType

    var body: some View {
        CardSection("Eligibility") {
            VerdictBanner(report: report)
                .cardRow(vertical: 14)
            ForEach(report.evaluations) { evaluation in
                RuleEvaluationRow(evaluation: evaluation, accountType: accountType)
                    .cardRow(vertical: 11)
            }
            SectionNote(report.velocitySummary)
        }
    }
}

/// Every account recorded at the offer's bank, as a card.
struct BankHistoryCard: View {
    let report: EligibilityReport

    var body: some View {
        CardSection("Your history at this bank") {
            if report.bankHistory.isEmpty {
                Text("No accounts recorded at this bank.")
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
            ForEach(report.bankHistory) { account in
                HistoryRow(account: account)
                    .cardRow(vertical: 10)
            }
        }
    }
}

extension EligibilityReport {
    /// How many accounts you've opened lately, which some banks hold against you.
    var velocitySummary: String {
        var text = "You've opened \(velocity.openedLast12Months) \(velocity.openedLast12Months == 1 ? "account" : "accounts") in the last 12 months (\(velocity.openedLast24Months) in 24)."
        if velocity.chexSystemsLast12Months > 0 {
            text += " \(velocity.chexSystemsLast12Months) used ChexSystems."
        }
        return text
    }
}

struct VerdictBanner: View {
    let report: EligibilityReport

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: report.verdict.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(report.verdict.tint)
                .frame(width: 44, height: 44)
                .background(report.verdict.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(report.headline)
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct RuleEvaluationRow: View {
    let evaluation: RuleEvaluation
    let accountType: AccountType

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(evaluation.rule.summary(for: accountType))
                Text(evaluation.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: evaluation.outcome.systemImage)
                .foregroundStyle(evaluation.outcome.tint)
        }
    }
}

private struct HistoryRow: View {
    let account: AccountSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.productLabel)
                Text(dates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            account.bonusStatus().badge
        }
    }

    private var dates: String {
        var text = "Opened \(DateText.format(account.openedDate))"
        if let closed = account.closedDate { text += " · Closed \(DateText.format(closed))" }
        if let received = account.bonusReceivedDate {
            text += " · \(Money.format(account.receivedBonusAmount)) bonus \(DateText.format(received))"
        }
        return text
    }
}
