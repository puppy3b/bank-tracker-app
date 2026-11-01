import SwiftUI
import SwiftData
import BankTrackerCore

/// The 1099 forms to expect for a tax year, as a checklist.
struct TaxView: View {
    @Query private var accounts: [BankAccount]
    @Query private var statuses: [TaxFormStatus]
    @Query private var banks: [Bank]
    @Environment(\.modelContext) private var context
    @State private var taxYear = TaxCalculator.filingYear()

    var body: some View {
        let snapshots = accounts.map(\.snapshot)
        let years = Set(TaxCalculator.taxYears(accounts: snapshots)).union([taxYear]).sorted(by: >)
        let summary = TaxCalculator.summary(taxYear: taxYear, accounts: snapshots)
        let receivedCount = summary.expectedForms.filter { status(for: $0)?.isReceived == true }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader("Taxes", subtitle: "The 1099 forms to expect, as a checklist") {
                    Picker("Tax year", selection: $taxYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        summaryTiles(summary, receivedCount: receivedCount)
                    }
                    .frame(minWidth: 560, idealWidth: 560, maxWidth: .infinity)
                    LazyVGrid(columns: Theme.tileColumns(compact: true, minimum: 0, spacing: 12), spacing: 12) {
                        summaryTiles(summary, receivedCount: receivedCount)
                    }
                }

                Text("A bonus counts in the year it's paid, not the year you opened the account. Banks generally send 1099-INT and 1099-MISC forms by January 31; brokerage consolidated 1099s usually arrive by mid-February.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                CardSection("Forms to expect") {
                    if summary.expectedForms.isEmpty {
                        Text("No forms expected for \(String(taxYear)).")
                            .foregroundStyle(.secondary)
                            .cardRow()
                    }
                    ForEach(summary.expectedForms) { form in
                        TaxFormRow(form: form, status: status(for: form)) { makeStatus(for: form) }
                            .cardRow(vertical: 14)
                    }
                }

                if !summary.belowThresholdForms.isEmpty {
                    CardSection("May not get a form") {
                        ForEach(summary.belowThresholdForms) { form in
                            TaxFormRow(form: form, status: status(for: form)) { makeStatus(for: form) }
                                .cardRow(vertical: 14)
                        }
                        SectionNote("These totals are under the usual reporting threshold, so the bank may not send a form. The income is still taxable.")
                    }
                }

                if !summary.noFormGroups.isEmpty {
                    CardSection("No form expected") {
                        ForEach(summary.noFormGroups) { form in
                            TaxFormRow(form: form, status: nil, makeStatus: nil)
                                .cardRow(vertical: 14)
                        }
                        SectionNote("Report these bonuses as income even without a form.")
                    }
                }

                Text("This checklist is a reminder, not tax advice. Thresholds used: $10 for 1099-INT; $600 for 1099-MISC through 2025 and $2,000 for payments made in 2026 or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ground)
        .navigationTitle("Taxes")
        .hidesToolbarTitle()
    }

    @ViewBuilder
    private func summaryTiles(_ summary: TaxYearSummary, receivedCount: Int) -> some View {
        StatTile(label: "Bonus income received", value: Money.format(summary.paidIncome), showsMoneyDot: true)
        if summary.pendingIncome > 0 {
            StatTile(label: "Still expected this year", value: Money.format(summary.pendingIncome))
        }
        StatTile(label: "Forms checked off", value: "\(receivedCount) of \(summary.expectedForms.count)")
    }

    private func status(for form: ExpectedTaxForm) -> TaxFormStatus? {
        statuses.first { $0.taxYear == form.taxYear && $0.bank?.uuid == form.bankID && $0.formType == form.formType }
    }

    private func makeStatus(for form: ExpectedTaxForm) -> TaxFormStatus {
        if let existing = status(for: form) { return existing }
        let status = TaxFormStatus()
        context.insert(status)
        status.taxYear = form.taxYear
        status.bank = banks.first { $0.uuid == form.bankID }
        status.formType = form.formType
        return status
    }
}

private struct TaxFormRow: View {
    let form: ExpectedTaxForm
    let status: TaxFormStatus?
    /// Nil for groups that don't produce a form, which can't be checked off.
    let makeStatus: (() -> TaxFormStatus)?

    private var isReceived: Bool { status?.isReceived ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if makeStatus != nil {
                    Button(action: toggle) {
                        Image(systemName: isReceived ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isReceived ? Palette.good : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(isReceived ? "Mark as not received" : "Mark as received")
                    .accessibilityLabel(isReceived ? "Received" : "Not received")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(form.bankName) · \(form.formType.displayName)")
                        .font(.system(size: 14, weight: .semibold))
                    ForEach(form.bonuses) { bonus in
                        Text("\(bonus.accountName): \(Money.format(bonus.amount)) \(bonus.isPaid ? "paid" : "expected by") \(DateText.format(bonus.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(form.total))
                        .font(Theme.amount(16))
                    if form.pendingTotal > 0 {
                        Text("\(Money.format(form.pendingTotal)) not paid yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if isReceived, let status {
                AmountField(title: "Amount on the form", value: reportedAmount(status))
                if let reported = status.reportedAmount, reported > 0, reported != form.total {
                    Text("Differs from the expected \(Money.format(form.total)) by \(Money.format(abs(reported - form.total))). Regular interest on the account is reported on the same form.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle() {
        guard let makeStatus else { return }
        let status = makeStatus()
        status.isReceived.toggle()
        status.receivedDate = status.isReceived ? .now : nil
    }

    private func reportedAmount(_ status: TaxFormStatus) -> Binding<Decimal> {
        Binding(
            get: { status.reportedAmount ?? 0 },
            set: { status.reportedAmount = $0 == 0 ? nil : $0 }
        )
    }
}

#Preview {
    NavigationStack {
        TaxView()
    }
    .modelContainer(.preview)
}
