import SwiftUI
import SwiftData
import BankTrackerCore

/// Precomputed values for one account row, so the table can sort on them.
nonisolated struct AccountRow: Identifiable {
    let account: BankAccount
    let snapshot: AccountSnapshot
    let timeline: BonusTimeline
    let status: BonusStatus
    let nextTitle: String
    let nextDetail: String
    let nextStepDate: Date
    let isReadyToClose: Bool

    init(account: BankAccount, today: Date = .now) {
        self.account = account
        snapshot = account.snapshot
        timeline = snapshot.timeline(today: today)
        status = snapshot.bonusStatus(in: timeline)
        (nextTitle, nextDetail, nextStepDate) = Self.nextStep(snapshot: snapshot, timeline: timeline, status: status, today: today)
        isReadyToClose = snapshot.isOpen && !snapshot.isKeeper
            && (status == .received || status == .forfeited)
            && timeline.earliestCloseDate <= Calendar.current.startOfDay(for: today)
    }

    var id: PersistentIdentifier { account.persistentModelID }
    var bankName: String { snapshot.bankName }
    var productLabel: String { snapshot.productLabel }
    var sortName: String { snapshot.displayName }
    var openedDate: Date { snapshot.openedDate }
    var bonusAmount: Decimal { snapshot.hasBonus ? snapshot.terms.bonusAmount : 0 }
    var statusOrder: Int { BonusStatus.allCases.firstIndex(of: status) ?? 0 }
    var payoutSort: Date { status == .noBonus || status == .forfeited ? .distantFuture : (timeline.expectedPayout ?? .distantFuture) }

    /// Closed accounts sort by their close date; open ones by when they can be closed.
    var closeSort: Date {
        if let closed = snapshot.closedDate { return closed }
        return snapshot.isKeeper ? .distantFuture : timeline.earliestCloseDate
    }

    var bonusText: String { snapshot.hasBonus ? Money.format(snapshot.terms.bonusAmount) : "—" }

    var payoutText: String {
        guard snapshot.hasBonus, !snapshot.bonusForfeited, let payout = timeline.expectedPayout else { return "—" }
        return timeline.payoutIsActual ? "Paid \(DateText.format(payout))" : "By \(DateText.format(payout))"
    }

    var closeText: String {
        if let closed = snapshot.closedDate { return "Closed \(DateText.format(closed))" }
        if snapshot.isKeeper { return "Keeper" }
        return timeline.earliestCloseDate <= Calendar.current.startOfDay(for: .now)
            ? "Now"
            : "After \(DateText.format(timeline.earliestCloseDate))"
    }

    private static func nextStep(snapshot: AccountSnapshot, timeline: BonusTimeline, status: BonusStatus, today: Date) -> (String, String, Date) {
        guard snapshot.isOpen else { return ("Done", "Counts toward eligibility", .distantFuture) }
        switch status {
        case .inProgress:
            let outstanding = snapshot.terms.requirements.compactMap { requirement -> (BonusRequirement, Date?)? in
                guard let schedule = timeline.schedule(for: requirement.id), !schedule.isSatisfied else { return nil }
                return (requirement, schedule.deadline)
            }
            if let (requirement, deadline) = outstanding.min(by: { ($0.1 ?? .distantFuture) < ($1.1 ?? .distantFuture) }) {
                var parts: [String] = []
                if let progress = requirement.progressSummary { parts.append(progress) }
                if let deadline { parts.append("due \(DateText.format(deadline))") }
                return (requirement.kind.displayName, parts.joined(separator: " · "), deadline ?? .distantFuture)
            }
            return ("Finish requirements", "", .distantFuture)
        case .awaitingPayout:
            let date = timeline.expectedPayout ?? .distantFuture
            return ("Bonus posts", "By \(DateText.format(date))", date)
        case .received, .forfeited:
            if snapshot.isKeeper { return ("Keeping long term", "No action needed", .distantFuture) }
            let close = timeline.earliestCloseDate
            return close <= Calendar.current.startOfDay(for: today)
                ? ("Close the account", "Penalty-free since \(DateText.format(close))", close)
                : ("Wait to close", "Penalty-free after \(DateText.format(close))", close)
        case .noBonus:
            return snapshot.isKeeper ? ("Keeper", "No action needed", .distantFuture) : ("—", "", .distantFuture)
        }
    }
}

struct AccountsListView: View {
    @Query(sort: \BankAccount.openedDate, order: .reverse) private var accounts: [BankAccount]
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var selection = Set<PersistentIdentifier>()
    @State private var sortOrder = [KeyPathComparator(\AccountRow.openedDate, order: .reverse)]
    @State private var accountToDelete: BankAccount?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In progress"
        case waiting = "Waiting for bonus"
        case readyToClose = "Ready to close"
        case keepers = "Keepers"
        case closed = "Closed"

        var id: Self { self }

        func includes(_ row: AccountRow) -> Bool {
            switch self {
            case .all: true
            case .inProgress: row.snapshot.isOpen && row.status == .inProgress
            case .waiting: row.snapshot.isOpen && row.status == .awaitingPayout
            case .readyToClose: row.isReadyToClose
            case .keepers: row.snapshot.isOpen && row.snapshot.isKeeper
            case .closed: !row.snapshot.isOpen
            }
        }
    }

    var body: some View {
        let today = Date.now
        let allRows = accounts.map { AccountRow(account: $0, today: today) }
        let rows = allRows
            .filter { filter.includes($0) }
            .filter { searchText.isEmpty || $0.sortName.localizedCaseInsensitiveContains(searchText) }
            .sorted(using: sortOrder)

        content(rows)
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label(accounts.isEmpty ? "No accounts yet" : "Nothing here", systemImage: "creditcard")
                    } description: {
                        Text(accounts.isEmpty
                             ? "Record the accounts you have now and the ones you've opened before."
                             : "No accounts match this filter.")
                    } actions: {
                        if accounts.isEmpty {
                            Button("Add Account") { router.isPresentingNewAccount = true }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader("Accounts", subtitle: subtitle(allRows))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Filter.allCases) { option in
                                FilterChip(
                                    title: "\(option.rawValue) · \(allRows.filter(option.includes).count)",
                                    isSelected: filter == option
                                ) { filter = option }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 14)
                .pinnedHeaderBackground()
            }
            .background(Theme.ground)
            .searchable(text: $searchText, prompt: "Search accounts")
            .navigationTitle("Accounts")
            .hidesToolbarTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Account", systemImage: "plus") { router.isPresentingNewAccount = true }
                }
            }
            .confirmationDialog(
                "Delete this account?",
                isPresented: Binding(get: { accountToDelete != nil }, set: { if !$0 { accountToDelete = nil } }),
                presenting: accountToDelete
            ) { account in
                Button("Delete \(account.displayName)", role: .destructive) { context.delete(account) }
            } message: { _ in
                Text("Its history will no longer count toward eligibility checks. To keep the history, close the account instead.")
            }
    }

    private func subtitle(_ rows: [AccountRow]) -> String {
        let banks = Set(rows.map(\.bankName)).count
        let open = rows.filter(\.snapshot.isOpen).count
        let accountsText = rows.count == 1 ? "1 account" : "\(rows.count) accounts"
        let banksText = banks == 1 ? "1 bank" : "\(banks) banks"
        return "\(accountsText) at \(banksText) · \(open) open"
    }

    @ViewBuilder
    private func content(_ rows: [AccountRow]) -> some View {
        #if os(iOS)
        if sizeClass == .compact {
            list(rows)
        } else {
            table(rows)
        }
        #else
        table(rows)
        #endif
    }

    private func table(_ rows: [AccountRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Account", value: \.sortName) { row in
                HStack(spacing: 10) {
                    BankMonogram(name: row.bankName, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.bankName)
                            .fontWeight(.semibold)
                        Text("\(row.productLabel) · opened \(row.openedDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .padding(.vertical, 4)
                .opacity(row.snapshot.isOpen ? 1 : 0.6)
            }
            .width(min: 190, ideal: 220)
            TableColumn("Journey", value: \.statusOrder) { row in
                VStack(alignment: .leading, spacing: 6) {
                    JourneyMini(stops: Journey.stops(for: row.snapshot, timeline: row.timeline, status: row.status))
                    Text(Journey.stage(for: row.snapshot, timeline: row.timeline, status: row.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(row.snapshot.isOpen ? 1 : 0.6)
            }
            .width(min: 135, ideal: 150)
            TableColumn("Bonus", value: \.bonusAmount) { row in
                Text(row.bonusText)
                    .font(Theme.amount(13.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64)
            TableColumn("Next step", value: \.nextStepDate) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.nextTitle)
                        .fontWeight(.semibold)
                    if !row.nextDetail.isEmpty {
                        Text(row.nextDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .width(min: 150, ideal: 180)
            TableColumn("Bonus payout", value: \.payoutSort) { row in
                Text(row.payoutText)
            }
            .width(min: 100, ideal: 112)
            TableColumn("Close", value: \.closeSort) { row in
                Text(row.closeText)
            }
            .width(min: 125, ideal: 135)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                Button("Open") { router.push(row.account) }
                Button("Delete…", role: .destructive) { accountToDelete = row.account }
            }
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                router.push(row.account)
            }
        }
        .cardContainer()
    }

    private func list(_ rows: [AccountRow]) -> some View {
        List {
            ForEach(rows) { row in
                NavigationLink(value: row.account) {
                    AccountListRow(row: row)
                }
            }
            .onDelete { indexSet in
                accountToDelete = indexSet.first.map { rows[$0].account }
            }
        }
        .groundBackground()
    }
}

/// An account in the iPhone list: bank and amount, the product, then the journey.
struct AccountListRow: View {
    let row: AccountRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BankMonogram(name: row.bankName, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.bankName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if row.snapshot.hasBonus {
                        Text(row.bonusText)
                            .font(Theme.amount(16))
                    }
                }
                Text(row.productLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    JourneyMini(stops: Journey.stops(for: row.snapshot, timeline: row.timeline, status: row.status))
                    Text(Journey.stage(for: row.snapshot, timeline: row.timeline, status: row.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 5)
            }
        }
        .padding(.vertical, 4)
        .opacity(row.snapshot.isOpen ? 1 : 0.6)
    }
}
