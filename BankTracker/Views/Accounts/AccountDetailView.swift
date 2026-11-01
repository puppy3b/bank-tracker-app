import SwiftUI
import SwiftData
import BankTrackerCore

/// The game plan for one account: the bonus journey, what's left to do, money,
/// when it's safe to close, and how to avoid fees.
struct AccountDetailView: View {
    @Bindable var account: BankAccount
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingBonusReceived = false
    @State private var showingClose = false
    @State private var confirmingDelete = false
    @Environment(\.isCompactLayout) private var isCompact

    var body: some View {
        let today = Date.now
        let snapshot = account.snapshot
        let timeline = snapshot.timeline(today: today)
        let status = snapshot.bonusStatus(in: timeline)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overview(snapshot: snapshot, timeline: timeline, status: status, today: today)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        mainColumn(timeline: timeline, status: status)
                            .frame(maxWidth: .infinity, alignment: .top)
                        sideColumn(timeline: timeline, status: status)
                            .frame(width: 330)
                    }
                    .frame(minWidth: 780, idealWidth: 780, maxWidth: .infinity)
                    VStack(spacing: 18) {
                        mainColumn(timeline: timeline, status: status)
                        sideColumn(timeline: timeline, status: status)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 22)
            .padding(.bottom, 40)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ground)
        .navigationTitle(account.displayName)
        .hidesToolbarTitle()
        .detailPageTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { showingEditor = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    switch status {
                    case .inProgress, .awaitingPayout:
                        Button("Mark Bonus Received…", systemImage: "checkmark.circle") { showingBonusReceived = true }
                        Button("Mark as Forfeited", systemImage: "xmark.circle") { account.bonusForfeited = true }
                    case .received:
                        Button("Undo Bonus Received", systemImage: "arrow.uturn.backward") {
                            account.bonusReceivedDate = nil
                            account.bonusReceivedAmount = nil
                        }
                    case .forfeited:
                        Button("Undo Forfeit", systemImage: "arrow.uturn.backward") { account.bonusForfeited = false }
                    case .noBonus:
                        EmptyView()
                    }
                    Divider()
                    Button("Delete Account…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            AccountEditorView(account: account)
        }
        .sheet(isPresented: $showingBonusReceived) {
            BonusReceivedSheet(account: account)
        }
        .sheet(isPresented: $showingClose) {
            CloseAccountSheet(account: account, timeline: timeline, status: status)
        }
        .confirmationDialog("Delete this account?", isPresented: $confirmingDelete) {
            Button("Delete Account", role: .destructive) {
                dismiss()
                context.delete(account)
            }
        } message: {
            Text("Its history will no longer count toward eligibility checks. To keep the history, close the account instead.")
        }
    }

    // MARK: - Overview

    private func overview(snapshot: AccountSnapshot, timeline: BonusTimeline, status: BonusStatus, today: Date) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 20 : 26) {
            // The amount sits beside the name, or below it when the name needs the width.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    BankMonogram(name: account.bankName, size: 52)
                    titles(size: 26)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        amount(size: 34)
                        badges(status)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        BankMonogram(name: account.bankName, size: 44)
                        titles(size: 22)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        amount(size: 30)
                        Spacer(minLength: 0)
                        badges(status)
                    }
                }
            }
            JourneyTrack(stops: Journey.stops(for: snapshot, timeline: timeline, status: status, today: today))
        }
        .padding(.horizontal, isCompact ? 18 : 26)
        .padding(.top, isCompact ? 18 : 22)
        .padding(.bottom, isCompact ? 20 : 26)
        .card(radius: 16)
    }

    private func titles(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.displayName)
                .font(.system(size: size, weight: .bold))
                .tracking(-0.3)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { subtitle }
                VStack(alignment: .leading, spacing: 2) { subtitle }
            }
            .font(.system(size: 13))
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        Text("\(account.accountType.displayName) · opened \(DateText.format(account.openedDate))")
            .foregroundStyle(.secondary)
        if let offer = account.sourceOffer {
            NavigationLink(value: offer) {
                Text("with the \(Money.format(offer.bonusAmount)) offer")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func amount(size: CGFloat) -> some View {
        if account.hasBonus {
            Text(Money.format(account.terms.bonusAmount))
                .font(Theme.amount(size))
        }
    }

    private func badges(_ status: BonusStatus) -> some View {
        HStack(spacing: 6) {
            if let closed = account.closedDate {
                StatusBadge(text: "Closed \(DateText.format(closed))", systemImage: "xmark.circle", tint: .secondary)
            }
            if account.hasBonus { status.badge }
            if account.isKeeper { StatusBadge(text: "Keeper", systemImage: "star.fill", tint: .accentColor) }
        }
    }

    // MARK: - Checklist and notes

    private func mainColumn(timeline: BonusTimeline, status: BonusStatus) -> some View {
        VStack(spacing: 18) {
            if account.hasBonus {
                CardSection("Bonus checklist") {
                    if account.terms.requirements.isEmpty {
                        Text("No requirements recorded. Edit the account to add them.")
                            .foregroundStyle(.secondary)
                            .cardRow()
                    }
                    ForEach(account.terms.requirements) { requirement in
                        RequirementChecklistRow(
                            requirement: requirementBinding(requirement.id),
                            schedule: timeline.schedule(for: requirement.id),
                            isPending: status.isPending,
                            bonusReceivedDate: account.bonusReceivedDate
                        )
                        .cardRow(vertical: 16)
                    }
                    SectionNote(account.terms.payout.summary + ". Until you check items off, estimates assume you finish on each deadline, so they show the latest likely date.")
                }
            }

            CardSection("Notes") {
                TextField("Notes", text: $account.notes, prompt: Text("Anything worth remembering"), axis: .vertical)
                    .lineLimit(3...10)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Money, closing, fees, details

    private func sideColumn(timeline: BonusTimeline, status: BonusStatus) -> some View {
        VStack(spacing: 18) {
            CardSection("Money") {
                if account.hasBonus {
                    LabeledContent("Bonus", value: bonusText(timeline: timeline, status: status))
                        .cardRow(vertical: 10)
                }
                AmountField(title: "Balance", value: $account.currentBalance)
                    .cardRow(vertical: 8)
                // Once the bonus is paid and the hold is over, the money is simply yours again.
                ForEach(account.snapshot.holds(in: timeline).filter { status.isPending || !isOver($0) }) { hold in
                    LabeledContent("Withdraw \(Money.format(hold.amount))", value: withdrawText(hold))
                        .cardRow(vertical: 10)
                }
                AmountField(title: "Fees paid", value: $account.feesPaid)
                    .cardRow(vertical: 8)
                if account.hasBonus {
                    LabeledContent("Tax form", value: account.terms.taxForm.displayName)
                        .cardRow(vertical: 10)
                }
                if status.isPending {
                    Button("Mark Bonus Received…", systemImage: "checkmark.circle") { showingBonusReceived = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .cardRow(vertical: 12)
                }
            }

            CardSection("Closing") {
                if let closed = account.closedDate {
                    LabeledContent("Closed", value: DateText.format(closed))
                        .cardRow(vertical: 10)
                    Button("Reopen Account", systemImage: "arrow.uturn.backward") { account.closedDate = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .cardRow(vertical: 12)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(closeTitle(timeline))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(closeRule(timeline))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if status.isPending {
                            Label {
                                Text("Wait for the bonus to post before closing.")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                            }
                            .font(.caption)
                            .padding(.top, 2)
                        }
                    }
                    .cardRow(vertical: 12)
                    Toggle("Keeper: I plan to keep this account", isOn: $account.isKeeper)
                        .cardRow(vertical: 10)
                    Button("Close Account…", systemImage: "xmark.circle") { showingClose = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .cardRow(vertical: 12)
                }
            }

            FeeSummaryCard(fee: account.terms.maintenanceFee)

            CardSection("Details") {
                LabeledContent("Type", value: account.accountType.displayName)
                    .cardRow(vertical: 10)
                if !account.last4.isEmpty {
                    LabeledContent("Account number", value: "••••\(account.last4)")
                        .cardRow(vertical: 10)
                }
                LabeledContent("Credit check", value: account.inquiry.displayName)
                    .cardRow(vertical: 10)
                if let offer = account.sourceOffer {
                    NavigationLink(value: offer) {
                        LabeledContent("Opened with offer", value: offer.title)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cardRow(vertical: 10)
                }
            }
        }
    }

    private func bonusText(timeline: BonusTimeline, status: BonusStatus) -> String {
        switch status {
        case .received:
            let paid = account.bonusReceivedDate.map { " · paid \(DateText.format($0))" } ?? ""
            return Money.format(account.snapshot.receivedBonusAmount) + paid
        case .forfeited:
            return "Forfeited"
        case .inProgress, .awaitingPayout:
            let by = timeline.expectedPayout.map { " · by \(DateText.format($0))" } ?? ""
            return Money.format(account.terms.bonusAmount) + by
        case .noBonus:
            return "—"
        }
    }

    /// When money on hold can come out: "From Jun 1, 2026", "Any time", or the rule before it's deposited.
    private func withdrawText(_ hold: MoneyHold) -> String {
        if hold.isEstimate {
            let start = hold.requirement.kind == .deposit ? "depositing" : "funding"
            return "\(hold.requirement.holdPeriod.displayText) after \(start)"
        }
        return isOver(hold) ? "Any time" : "From \(DateText.format(hold.until))"
    }

    private func isOver(_ hold: MoneyHold) -> Bool {
        !hold.isEstimate && hold.until <= Calendar.current.startOfDay(for: .now)
    }

    private func closeTitle(_ timeline: BonusTimeline) -> String {
        let earliest = timeline.earliestCloseDate
        return earliest <= Calendar.current.startOfDay(for: .now)
            ? "Safe to close now"
            : "Safe to close after \(DateText.format(earliest))"
    }

    private func closeRule(_ timeline: BonusTimeline) -> String {
        var text = account.terms.earlyClosure.summary + "."
        if timeline.earlyClosurePenalty > 0 {
            text += " Closing early costs \(Money.format(timeline.earlyClosurePenalty))."
        }
        return text
    }

    private func requirementBinding(_ id: UUID) -> Binding<BonusRequirement> {
        Binding(
            get: { account.terms.requirements.first { $0.id == id } ?? BonusRequirement(id: id) },
            set: { newValue in
                var terms = account.terms
                guard let index = terms.requirements.firstIndex(where: { $0.id == id }) else { return }
                terms.requirements[index] = newValue
                account.terms = terms
            }
        )
    }
}

/// One requirement with a checkbox, its deadline and progress controls.
///
/// The checkbox also works after the bonus is paid or forfeited, so an account entered after
/// the fact can have its checklist filled in. Progress controls only show while it's pending,
/// except the funding date of a hold, which sets when the money can come out.
struct RequirementChecklistRow: View {
    @Binding var requirement: BonusRequirement
    let schedule: BonusTimeline.RequirementSchedule?
    /// The bonus is still expected, so deadlines and progress matter.
    let isPending: Bool
    /// A requirement checked off after the bonus posted was done by this date at the latest.
    let bonusReceivedDate: Date?

    private var isSatisfied: Bool { schedule?.isSatisfied ?? (requirement.progress.completedOn != nil) }
    private var isAutoSatisfied: Bool { isSatisfied && requirement.progress.completedOn == nil }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: toggle) {
                Image(systemName: isSatisfied ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSatisfied ? Palette.good : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isAutoSatisfied)
            .help(isSatisfied ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(isSatisfied ? "Done" : "Not done")

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(requirement.actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSatisfied ? Color.secondary : Color.primary)
                    statusLine
                    if !requirement.details.isEmpty {
                        Text(requirement.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isSatisfied, !isAutoSatisfied {
                    DatePicker("Completed on", selection: completedDate, displayedComponents: .date)
                        .fixedSize()
                } else if !isSatisfied, isPending {
                    progressControls
                }
                if requirement.hasHold {
                    OptionalDatePicker(
                        title: requirement.kind == .deposit ? "I've deposited it" : "I've funded it",
                        dateLabel: requirement.kind == .deposit ? "Deposited on" : "Funded on",
                        date: $requirement.progress.fundedOn,
                        defaultDate: min(.now, bonusReceivedDate ?? .now)
                    )
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if requirement.hasHold, let funded = requirement.progress.fundedOn, let holdUntil = schedule?.holdUntil {
            // Once the money is in, when it can come out matters more than whether the box is checked.
            let verb = requirement.kind == .deposit ? "Deposited" : "Funded"
            Group {
                if holdUntil > Calendar.current.startOfDay(for: .now) {
                    Text("\(verb) \(DateText.format(funded)) · keep it until \(DateText.format(holdUntil)) · ")
                        + Text(RelativeDay.text(for: holdUntil)).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                } else {
                    Text("\(verb) \(DateText.format(funded)) · free to withdraw since \(DateText.format(holdUntil))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let satisfied = schedule?.satisfiedOn {
            Text("Done \(DateText.format(satisfied))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let deadline = schedule?.deadline, !isPending {
            // The bonus was paid or forfeited, so a missed deadline no longer needs attention.
            Text("\(deadline < Calendar.current.startOfDay(for: .now) ? "Was due" : "Due") \(DateText.format(deadline))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let deadline = schedule?.deadline {
            let overdue = deadline < Calendar.current.startOfDay(for: .now)
            HStack(spacing: 4) {
                if overdue {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
                }
                Text("\(overdue ? "Was due" : "Due") \(DateText.format(deadline)) · ")
                    + Text(RelativeDay.text(for: deadline)).fontWeight(.semibold).foregroundStyle(overdue ? Palette.critical : Color.accentColor)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressControls: some View {
        switch requirement.kind {
        case .directDeposit, .deposit, .debitPurchases, .billPay:
            if requirement.kind.usesCount, requirement.count > 0 {
                // The bar only repeats the count, so it goes first when space is short.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ProgressView(value: min(1, Double(requirement.progress.countSoFar) / Double(requirement.count)))
                            .frame(minWidth: 80, maxWidth: 260)
                            .accessibilityLabel("Transactions so far")
                        countStepper
                        markDoneButton
                    }
                    HStack(spacing: 12) {
                        countStepper
                        markDoneButton
                    }
                }
            }
            if requirement.kind.usesAmount, requirement.amount > 0 {
                HStack(spacing: 12) {
                    ProgressView(value: min(1, (requirement.progress.amountSoFar / requirement.amount).doubleValue))
                        .frame(maxWidth: 260)
                        .accessibilityLabel("Amount so far")
                    AmountField(title: "So far", value: $requirement.progress.amountSoFar)
                        .frame(maxWidth: 220)
                }
            }
        case .maintainBalance, .other:
            EmptyView()
        }
    }

    private var markDoneButton: some View {
        Button("Mark Done", action: toggle)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .fixedSize()
    }

    private var countStepper: some View {
        HStack(spacing: 0) {
            Button {
                requirement.progress.countSoFar = max(0, requirement.progress.countSoFar - 1)
            } label: {
                Image(systemName: "minus").frame(width: 28, height: 24).contentShape(Rectangle())
            }
            .accessibilityLabel("One fewer")
            HStack(spacing: 6) {
                IntegerTextField(value: $requirement.progress.countSoFar)
                    .frame(width: 36)
                Text("of \(requirement.count)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            Button {
                requirement.progress.countSoFar += 1
            } label: {
                Image(systemName: "plus").frame(width: 28, height: 24).contentShape(Rectangle())
            }
            .accessibilityLabel("One more")
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
    }

    private var completedDate: Binding<Date> {
        Binding(
            get: { requirement.progress.completedOn ?? .now },
            set: { requirement.progress.completedOn = $0 }
        )
    }

    private func toggle() {
        if requirement.progress.completedOn == nil {
            requirement.progress.completedOn = min(.now, bonusReceivedDate ?? .now)
        } else {
            requirement.progress.completedOn = nil
        }
    }
}

/// The monthly fee and the ways to avoid it, with your plan starred.
struct FeeSummaryCard: View {
    let fee: MaintenanceFee

    var body: some View {
        CardSection("Monthly fee") {
            Text(fee.hasFee ? "\(Money.format(fee.monthlyFee))/month" : "None")
                .font(.system(size: 13, weight: .semibold))
        } content: {
            if fee.hasFee {
                if fee.waivers.isEmpty {
                    Text("No waiver recorded. Edit the account to add how to avoid the fee.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .cardRow(vertical: 10)
                }
                ForEach(fee.waivers) { waiver in
                    Label {
                        if waiver.isMyPlan {
                            Text("My plan: ").fontWeight(.semibold) + Text(waiver.summary)
                        } else {
                            Text("Or: \(waiver.summary)").foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: waiver.isMyPlan ? "star.fill" : "circle")
                            .foregroundStyle(waiver.isMyPlan ? Color.accentColor : Color.secondary)
                    }
                    .font(.system(size: 13))
                    .cardRow(vertical: 10)
                }
                if !fee.notes.isEmpty {
                    Text(fee.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .cardRow(vertical: 10)
                }
            } else {
                Text("This account has no monthly fee.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .cardRow(vertical: 10)
            }
        }
    }
}

private struct BonusReceivedSheet: View {
    @Bindable var account: BankAccount
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var amount: Decimal = 0

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Received on", selection: $date, displayedComponents: .date)
                AmountField(title: "Amount", value: $amount)
                if amount != account.terms.bonusAmount {
                    Text("The offer promised \(Money.format(account.terms.bonusAmount)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Bonus Received")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        account.bonusReceivedDate = date
                        account.bonusReceivedAmount = amount
                        account.bonusForfeited = false
                        dismiss()
                    }
                }
            }
            .onAppear { amount = account.terms.bonusAmount }
        }
        .sheetFrame(width: 420, height: 260)
    }
}

private struct CloseAccountSheet: View {
    @Bindable var account: BankAccount
    let timeline: BonusTimeline
    let status: BonusStatus
    @Environment(\.dismiss) private var dismiss
    @State private var closeDate = Date.now
    @State private var forfeitBonus = false

    var body: some View {
        let isEarly = Calendar.current.startOfDay(for: closeDate) < timeline.earliestCloseDate
        NavigationStack {
            Form {
                DatePicker("Closed on", selection: $closeDate, displayedComponents: .date)
                if isEarly {
                    Label {
                        Text("That's before the earliest penalty-free date, \(DateText.format(timeline.earliestCloseDate)).")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    }
                    if timeline.earlyClosurePenalty > 0 {
                        Text("It may cost \(Money.format(timeline.earlyClosurePenalty)) in fees or clawbacks.")
                            .foregroundStyle(.secondary)
                    }
                }
                if status.isPending {
                    Toggle("I won't get the bonus (mark it forfeited)", isOn: $forfeitBonus)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Close Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close Account") {
                        account.closedDate = closeDate
                        if forfeitBonus { account.bonusForfeited = true }
                        dismiss()
                    }
                }
            }
        }
        .sheetFrame(width: 440, height: 300)
    }
}
