import SwiftUI
import SwiftData
import BankTrackerCore

/// Today: headline numbers, the next 60 days, and what needs doing.
struct DashboardView: View {
    @Query private var accounts: [BankAccount]
    @Query private var offers: [Offer]
    @Query private var taxStatuses: [TaxFormStatus]
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.isCompactLayout) private var isCompact

    var body: some View {
        let today = Date.now
        let snapshots = accounts.map(\.snapshot)
        let stats = PortfolioStats(accounts: snapshots, today: today)
        let items = ActionPlanner(today: today).items(accounts: snapshots, offers: offers.map(\.snapshot))

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("Today", subtitle: today.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                    HStack(spacing: 8) {
                        Button("Record Account") { router.isPresentingNewAccount = true }
                            .buttonStyle(.bordered)
                        Button("Add Offer", systemImage: "plus") { router.isPresentingNewOffer = true }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if accounts.isEmpty && offers.isEmpty {
                    WelcomeCard(
                        onNewOffer: { router.isPresentingNewOffer = true },
                        onNewAccount: { router.isPresentingNewAccount = true },
                        onSampleData: { SampleData.load(into: context) }
                    )
                } else {
                    LazyVGrid(columns: Theme.tileColumns(compact: isCompact, minimum: 200, spacing: isCompact ? 12 : 14), spacing: isCompact ? 12 : 14) {
                        StatTile(label: "Earned this year", value: Money.compact(stats.earnedThisYear), detail: "\(Money.compact(stats.totalEarned)) all time", showsMoneyDot: true)
                        StatTile(label: "On the road", value: Money.compact(stats.pendingTotal), detail: stats.pending.count == 1 ? "1 bonus expected" : "\(stats.pending.count) bonuses expected")
                        StatTile(label: "Funds parked", value: Money.compact(stats.fundsParked), detail: stats.openAccounts == 1 ? "In 1 open account" : "Across \(stats.openAccounts) open accounts")
                        nextPayoutTile(stats)
                    }

                    if let banner = taxSeasonBanner(snapshots) {
                        banner
                    }

                    UpcomingTimeline(accounts: accounts, offers: offers, today: today) { lane in
                        if let account = lane.account {
                            router.push(account)
                        } else if let offer = lane.offer {
                            router.push(offer)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            needsYou(items)
                            sideColumn(stats: stats, items: items)
                        }
                        .frame(minWidth: 780, idealWidth: 780, maxWidth: .infinity)
                        VStack(spacing: 14) {
                            needsYou(items)
                            sideColumn(stats: stats, items: items)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ground)
        .navigationTitle("Today")
        .hidesToolbarTitle()
    }

    private func nextPayoutTile(_ stats: PortfolioStats) -> StatTile {
        guard let next = stats.pending.first(where: { $0.expectedDate != nil }), let date = next.expectedDate else {
            return StatTile(label: "Next payout", value: "—", detail: "No bonuses pending")
        }
        return StatTile(
            label: "Next payout",
            value: date.formatted(.dateTime.month(.abbreviated).day()),
            detail: "\(Money.format(next.amount)) from \(next.accountName)"
        )
    }

    // MARK: - Needs you

    private func needsYou(_ items: [ActionItem]) -> some View {
        let needs = items.filter { item in
            switch item.kind {
            case .requirement, .bonusOverdue, .keepBalance, .readyToClose, .offerExpiring: true
            case .awaitingBonus, .closeLater, .avoidFee: false
            }
        }
        return CardSection("Needs you") {
            Text(needs.count == 1 ? "1 item" : "\(needs.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        } content: {
            if needs.isEmpty {
                Label("Nothing needs you right now.", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
            ForEach(needs) { item in
                NeedsYouRow(
                    item: item,
                    account: account(for: item),
                    open: { open(item) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Coming in, fee plans, closing later

    private func sideColumn(stats: PortfolioStats, items: [ActionItem]) -> some View {
        let fees = items.filter { $0.kind == .avoidFee }
        let later = items.filter { $0.kind == .closeLater }
        return VStack(spacing: 14) {
            CardSection("Coming in") {
                Text(Money.format(stats.pendingTotal))
                    .font(Theme.amount(15))
            } content: {
                if stats.pending.isEmpty {
                    Text("No bonuses on the way.")
                        .foregroundStyle(.secondary)
                        .cardRow()
                }
                ForEach(stats.pending) { pending in
                    Button {
                        if let account = accounts.first(where: { $0.uuid == pending.accountID }) { router.push(account) }
                    } label: {
                        ComingInRow(pending: pending)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !fees.isEmpty {
                CardSection("Fee plans") {
                    ForEach(fees) { item in
                        Button { open(item) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account(for: item)?.displayName ?? item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Plan: \(item.detail)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                if let amount = item.amount {
                                    Text("\(Money.format(amount))/mo")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .cardRow(vertical: 12)
                    }
                }
            }

            if !later.isEmpty {
                CardSection("Closing later") {
                    ForEach(later) { item in
                        Button { open(item) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account(for: item)?.displayName ?? item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if let date = item.date {
                                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .cardRow(vertical: 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Helpers

    private func account(for item: ActionItem) -> BankAccount? {
        item.accountID.flatMap { id in accounts.first { $0.uuid == id } }
    }

    private func open(_ item: ActionItem) {
        if let account = account(for: item) {
            router.push(account)
        } else if let id = item.offerID, let offer = offers.first(where: { $0.uuid == id }) {
            router.push(offer)
        }
    }

    /// January through April: how many of last year's forms you've checked off.
    private func taxSeasonBanner(_ snapshots: [AccountSnapshot]) -> TaxSeasonBanner? {
        let calendar = Calendar.current
        guard calendar.component(.month, from: .now) <= 4 else { return nil }
        let year = TaxCalculator.filingYear()
        let expected = TaxCalculator.summary(taxYear: year, accounts: snapshots).expectedForms
        guard !expected.isEmpty else { return nil }
        let received = expected.filter { form in
            taxStatuses.contains { $0.taxYear == year && $0.bank?.uuid == form.bankID && $0.formType == form.formType && $0.isReceived }
        }.count
        return TaxSeasonBanner(year: year, expected: expected.count, received: received) {
            router.show(.taxes)
        }
    }
}

/// One item in "Needs you", with a progress bar and an inline action where it helps.
private struct NeedsYouRow: View {
    let item: ActionItem
    let account: BankAccount?
    let open: () -> Void

    var body: some View {
        let requirement = matchingRequirement
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: item.systemImage, tint: tileTint)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    Text(detail(for: requirement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.kind == .requirement, let requirement, let progress = progress(of: requirement) {
                        HStack(spacing: 8) {
                            ProgressView(value: progress.fraction)
                                .frame(maxWidth: 220)
                                .accessibilityLabel("Progress")
                            Text(progress.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actions(for: requirement)
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
        .cardRow(vertical: 14)
    }

    private var tileTint: Color {
        if item.urgency == .overdue { return Palette.critical }
        if item.kind == .readyToClose { return .secondary }
        return .accentColor
    }

    /// The requirement this item is about. The planner's ids are "req-<id>" and "hold-<id>".
    private var matchingRequirement: BonusRequirement? {
        guard item.kind == .requirement || item.kind == .keepBalance, let account else { return nil }
        return account.terms.requirements.first { item.id == "req-\($0.id)" || item.id == "hold-\($0.id)" }
    }

    private func detail(for requirement: BonusRequirement?) -> String {
        guard requirement != nil, let account, let date = item.date else { return item.detail }
        let prefix = item.kind == .keepBalance ? "until" : (item.urgency == .overdue ? "was due" : "due")
        return "\(account.displayName) · \(prefix) \(DateText.format(date)), \(RelativeDay.text(for: date))"
    }

    private func progress(of requirement: BonusRequirement) -> (fraction: Double, text: String)? {
        if requirement.kind.usesCount, requirement.count > 0 {
            let done = requirement.progress.countSoFar
            return (min(1, Double(done) / Double(requirement.count)), "\(done) of \(requirement.count)")
        }
        if requirement.kind.usesAmount, requirement.kind != .maintainBalance, requirement.amount > 0 {
            let soFar = requirement.progress.amountSoFar
            return (min(1, (soFar / requirement.amount).doubleValue), "\(Money.format(soFar)) of \(Money.format(requirement.amount))")
        }
        return nil
    }

    @ViewBuilder
    private func actions(for requirement: BonusRequirement?) -> some View {
        switch item.kind {
        case .requirement:
            if let requirement, requirement.kind.usesCount, requirement.count > 0 {
                if requirement.progress.countSoFar < requirement.count {
                    Button(logTitle(for: requirement.kind)) { update(requirement) { $0.progress.countSoFar += 1 } }
                } else {
                    Button("Mark Done") { update(requirement) { $0.progress.completedOn = .now } }
                }
            } else {
                Button("Open", action: open)
            }
        case .readyToClose:
            HStack(spacing: 6) {
                Button("Keep") { account?.isKeeper = true }
                Button("Close…", action: open)
            }
        case .offerExpiring:
            Button("Review", action: open)
        default:
            Button("Open", action: open)
        }
    }

    private func logTitle(for kind: BonusRequirement.Kind) -> String {
        switch kind {
        case .debitPurchases: "Log Purchase"
        case .billPay: "Log Payment"
        default: "Log Deposit"
        }
    }

    private func update(_ requirement: BonusRequirement, _ change: (inout BonusRequirement) -> Void) {
        guard let account else { return }
        var terms = account.terms
        guard let index = terms.requirements.firstIndex(where: { $0.id == requirement.id }) else { return }
        change(&terms.requirements[index])
        account.terms = terms
    }
}

private struct ComingInRow: View {
    let pending: PortfolioStats.PendingBonus

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.money.opacity(0.16))
                if pending.status == .awaitingPayout {
                    Circle().fill(Theme.money).frame(width: 12, height: 12)
                } else {
                    Circle().strokeBorder(Theme.money, lineWidth: 2).frame(width: 12, height: 12)
                }
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.accountName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(pending.amount))
                    .font(Theme.amount(15))
                if let date = pending.expectedDate {
                    Text(RelativeDay.text(for: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .cardRow(vertical: 12)
    }

    private var detail: String {
        let by = pending.expectedDate.map { "expected by \(DateText.format($0))" } ?? "date not known yet"
        return pending.status == .awaitingPayout ? "Requirements done · \(by)" : "After requirements · \(by)"
    }
}

struct TaxSeasonBanner: View {
    let year: Int
    let expected: Int
    let received: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                IconTile(systemImage: "doc.text.fill", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tax season: \(expected) \(expected == 1 ? "form" : "forms") to expect for \(String(year))")
                        .font(.headline)
                    Text("\(received) checked off. Open the tax checklist.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WelcomeCard: View {
    let onNewOffer: () -> Void
    let onNewAccount: () -> Void
    let onSampleData: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                IconTile(systemImage: "sparkles", size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Bank Tracker")
                        .font(.system(size: 24, weight: .bold))
                    Text("Track bank bonuses from offer to payout, and know when it's safe to close.")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                step("1.circle.fill", "Found an offer? Add it with its fine print and see right away whether you're eligible, based on your account history.")
                step("2.circle.fill", "Opened it? Get a checklist with deadlines, the expected payout date and the earliest date you can close without a penalty.")
                step("3.circle.fill", "At tax time, check off each 1099 you should receive.")
            }
            HStack {
                Button("Add an Offer", systemImage: "tag", action: onNewOffer)
                    .buttonStyle(.borderedProminent)
                Button("Record an Account", systemImage: "creditcard", action: onNewAccount)
                    .buttonStyle(.bordered)
                Button("Try Sample Data", systemImage: "wand.and.stars", action: onSampleData)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
    }

    private func step(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.accentColor)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(Router())
    .modelContainer(.preview)
}
