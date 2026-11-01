import SwiftUI
import SwiftData
import BankTrackerCore

/// Per-bank figures shared by the bank cards and the bank page.
struct BankSummary {
    struct Entry: Identifiable {
        let account: BankAccount
        let snapshot: AccountSnapshot
        let status: BonusStatus

        var id: PersistentIdentifier { account.persistentModelID }
    }

    /// Newest first.
    let entries: [Entry]
    let earned: Decimal
    let pending: Decimal
    let lastOpened: Date?
    let lastBonus: Date?

    init(bank: Bank, today: Date = .now) {
        entries = bank.accountList
            .sorted { $0.openedDate > $1.openedDate }
            .map { account in
                let snapshot = account.snapshot
                return Entry(account: account, snapshot: snapshot, status: snapshot.bonusStatus(today: today))
            }
        earned = entries.sum { $0.snapshot.receivedBonusAmount }
        pending = entries.filter(\.status.isPending).sum { $0.snapshot.terms.bonusAmount }
        lastOpened = entries.first?.snapshot.openedDate
        lastBonus = entries.compactMap(\.snapshot.bonusReceivedDate).max()
    }

    var openEntries: [Entry] { entries.filter(\.snapshot.isOpen) }
    var pastEntries: [Entry] { entries.filter { !$0.snapshot.isOpen } }

    var countsText: String {
        let accounts = entries.count == 1 ? "1 account" : "\(entries.count) accounts"
        return "\(accounts) · \(openEntries.count) open"
    }
}

extension Bank {
    /// The website as a link, adding https:// when no scheme was typed.
    var websiteURL: URL? {
        let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }
}

/// Initials in a rounded tile, e.g. "MB" for Maple Bank.
struct BankMonogram: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split { $0 == " " || $0 == "-" }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Bank list

struct BanksListView: View {
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Environment(\.modelContext) private var context
    @State private var sort: Sort = .name
    @State private var searchText = ""
    @State private var showingNewBank = false
    @State private var newBankName = ""
    @State private var bankForNewOffer: Bank?
    @State private var bankToDelete: Bank?
    @Environment(Router.self) private var router

    enum Sort: String, CaseIterable, Identifiable {
        case name = "Name"
        case earned = "Most earned"
        case recent = "Recently opened"

        var id: Self { self }
    }

    var body: some View {
        let summaries = banks
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .map { (bank: $0, summary: BankSummary(bank: $0)) }
            .sorted(by: sortOrder)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Banks", subtitle: banks.isEmpty ? nil : overview)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(summaries, id: \.bank.persistentModelID) { item in
                        NavigationLink(value: item.bank) {
                            BankCard(bank: item.bank, summary: item.summary)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("New Offer at \(item.bank.name)…", systemImage: "tag") { bankForNewOffer = item.bank }
                            Button("Delete Bank…", systemImage: "trash", role: .destructive) { bankToDelete = item.bank }
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
        .overlay {
            if banks.isEmpty {
                ContentUnavailableView {
                    Label("No banks yet", systemImage: "building.columns")
                } description: {
                    Text("Banks are added when you create an offer or account, or with the + button.")
                }
            } else if summaries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search banks")
        .navigationTitle("Banks")
        .hidesToolbarTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(Sort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Bank", systemImage: "plus") {
                    newBankName = ""
                    showingNewBank = true
                }
            }
        }
        .alert("New Bank", isPresented: $showingNewBank) {
            TextField("Bank name", text: $newBankName)
            Button("Add") {
                let name = newBankName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { context.insert(Bank(name: name)) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $bankForNewOffer) { bank in
            OfferEditorView(offer: nil, presetBank: bank) { offer in router.push(offer) }
        }
        .confirmationDialog(
            "Delete this bank?",
            isPresented: Binding(get: { bankToDelete != nil }, set: { if !$0 { bankToDelete = nil } }),
            presenting: bankToDelete
        ) { bank in
            Button("Delete \(bank.name)", role: .destructive) { context.delete(bank) }
        } message: { bank in
            Text("This also deletes its \(bank.accountList.count) accounts and \(bank.offerList.count) offers.")
        }
    }

    private var overview: String {
        let accounts = banks.reduce(0) { $0 + $1.accountList.count }
        let earned = banks.flatMap(\.accountList).sum { $0.snapshot.receivedBonusAmount }
        let bankCount = banks.count == 1 ? "1 bank" : "\(banks.count) banks"
        let accountCount = accounts == 1 ? "1 account" : "\(accounts) accounts"
        return "\(bankCount) · \(accountCount) · \(Money.format(earned)) earned"
    }

    private func sortOrder(_ lhs: (bank: Bank, summary: BankSummary), _ rhs: (bank: Bank, summary: BankSummary)) -> Bool {
        switch sort {
        case .name:
            return lhs.bank.name.localizedStandardCompare(rhs.bank.name) == .orderedAscending
        case .earned:
            if lhs.summary.earned != rhs.summary.earned { return lhs.summary.earned > rhs.summary.earned }
            return lhs.bank.name.localizedStandardCompare(rhs.bank.name) == .orderedAscending
        case .recent:
            return (lhs.summary.lastOpened ?? .distantPast) > (rhs.summary.lastOpened ?? .distantPast)
        }
    }
}

private struct BankCard: View {
    let bank: Bank
    let summary: BankSummary
    @Environment(\.isCompactLayout) private var isCompact

    private let visibleAccounts = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BankMonogram(name: bank.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(summary.countsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(summary.earned))
                        .font(.headline)
                    Text("earned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                let open = summary.openEntries
                if open.isEmpty {
                    Text("No open accounts")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(open.prefix(visibleAccounts)) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.snapshot.accountType.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(entry.snapshot.productLabel)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if entry.snapshot.hasBonus {
                            entry.status.badge
                        } else if entry.snapshot.isKeeper {
                            StatusBadge(text: "Keeper", systemImage: "star.fill", tint: .accentColor)
                        }
                    }
                    .font(.callout)
                }
                if open.count > visibleAccounts {
                    Text("and \(open.count - visibleAccounts) more open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Room for up to three lines, so cards in a row line up. On iPhone each card has its own row.
            .frame(minHeight: isCompact ? 0 : 72, alignment: .topLeading)

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: String {
        var parts: [String] = []
        if let lastOpened = summary.lastOpened { parts.append("Last opened \(DateText.format(lastOpened))") }
        if summary.pending > 0 { parts.append("\(Money.format(summary.pending)) pending") }
        return parts.isEmpty ? "No accounts yet" : parts.joined(separator: " · ")
    }
}

// MARK: - Bank page

struct BankDetailView: View {
    @Bindable var bank: Bank
    @Query private var allAccounts: [BankAccount]
    @AppStorage(SettingsKey.residenceState) private var residenceState = ""
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingNewOffer = false
    @State private var confirmingDelete = false
    @Environment(\.isCompactLayout) private var isCompact

    var body: some View {
        let summary = BankSummary(bank: bank)
        let history = allAccounts.map(\.snapshot)
        let offers = bank.offerList.sorted { $0.foundDate > $1.foundDate }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        BankMonogram(name: bank.name, size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bank.name)
                                .font(.system(size: 26, weight: .bold))
                                .tracking(-0.3)
                            if let url = bank.websiteURL {
                                Link(bank.website, destination: url)
                                    .font(.system(size: 13))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    // One row of figures; rows of three on iPhone, where five would be cut short.
                    Group {
                        if isCompact {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: 3), alignment: .leading, spacing: 14) {
                                bankStats(summary)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 0) {
                                bankStats(summary)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.hairline.opacity(0.7)).frame(height: 1)
                    }
                }
                .padding(.horizontal, isCompact ? 18 : 26)
                .padding(.vertical, isCompact ? 18 : 22)
                .card(radius: 16)

                CardSection("Open accounts") {
                    if summary.openEntries.isEmpty {
                        Text("No open accounts at this bank.")
                            .foregroundStyle(.secondary)
                            .cardRow()
                    }
                    ForEach(summary.openEntries) { entry in
                        CardLink(value: entry.account) {
                            BankAccountRow(entry: entry)
                        }
                    }
                }

                if !summary.pastEntries.isEmpty {
                    CardSection("Past accounts") {
                        ForEach(summary.pastEntries) { entry in
                            CardLink(value: entry.account) {
                                BankAccountRow(entry: entry)
                            }
                        }
                        SectionNote("Closed accounts still count toward eligibility rules for new offers here.")
                    }
                }

                CardSection("Offers") {
                    Button(isCompact ? "New Offer…" : "Check a New Offer Here…", systemImage: "tag") { showingNewOffer = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } content: {
                    if offers.isEmpty {
                        Text("No offers recorded at this bank.")
                            .foregroundStyle(.secondary)
                            .cardRow()
                    }
                    ForEach(offers) { offer in
                        CardLink(value: offer) {
                            OfferRow(
                                offer: offer,
                                report: offer.status == .considering
                                    ? offer.eligibilityReport(history: history, residenceState: residenceState)
                                    : nil
                            )
                        }
                    }
                }

                CardSection("Notes") {
                    TextField("Notes", text: $bank.notes, prompt: Text("e.g. Uses ChexSystems; phone support hours"), axis: .vertical)
                        .lineLimit(2...8)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 22)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ground)
        .navigationTitle(bank.name)
        .hidesToolbarTitle()
        .detailPageTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { showingEditor = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Offer at \(bank.name)…", systemImage: "tag") { showingNewOffer = true }
                    Divider()
                    Button("Delete Bank…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            BankEditorView(bank: bank)
        }
        .sheet(isPresented: $showingNewOffer) {
            OfferEditorView(offer: nil, presetBank: bank) { offer in router.push(offer) }
        }
        .confirmationDialog("Delete \(bank.name)?", isPresented: $confirmingDelete) {
            Button("Delete Bank", role: .destructive) {
                dismiss()
                context.delete(bank)
            }
        } message: {
            Text("This also deletes its \(bank.accountList.count) accounts and \(bank.offerList.count) offers.")
        }
    }
}

extension BankDetailView {
    @ViewBuilder
    private func bankStats(_ summary: BankSummary) -> some View {
        BankStat(label: "Accounts", value: "\(summary.entries.count)")
        BankStat(label: "Open now", value: "\(summary.openEntries.count)")
        BankStat(label: "Earned", value: Money.format(summary.earned), showsMoneyDot: true)
        BankStat(label: "Pending", value: Money.format(summary.pending))
        if let lastBonus = summary.lastBonus {
            BankStat(label: "Last bonus", value: DateText.format(lastBonus))
        }
    }
}

private struct BankStat: View {
    let label: String
    let value: String
    var showsMoneyDot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if showsMoneyDot {
                    Circle().fill(Theme.money).frame(width: 7, height: 7).accessibilityHidden(true)
                }
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.amount(20))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct BankAccountRow: View {
    let entry: BankSummary.Entry

    var body: some View {
        // The badge sits under the amount, or under the dates when the name needs the width.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                IconTile(systemImage: entry.snapshot.accountType.systemImage, tint: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot.productLabel)
                    datesText
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    amount
                    badge
                }
            }
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemImage: entry.snapshot.accountType.systemImage, tint: .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.snapshot.productLabel)
                        Spacer(minLength: 0)
                        amount
                    }
                    datesText
                    badge
                        .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var datesText: some View {
        Text(dates)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var amount: some View {
        if entry.snapshot.hasBonus {
            Text(Money.format(entry.snapshot.terms.bonusAmount))
                .font(Theme.amount(15))
        }
    }

    @ViewBuilder
    private var badge: some View {
        if entry.snapshot.hasBonus {
            entry.status.badge
        } else if entry.snapshot.isKeeper {
            StatusBadge(text: "Keeper", systemImage: "star.fill", tint: .accentColor)
        }
    }

    private var dates: String {
        var text = "Opened \(DateText.format(entry.snapshot.openedDate))"
        if let closed = entry.snapshot.closedDate {
            text += " · Closed \(DateText.format(closed))"
        }
        return text
    }
}

/// Edit a bank's name, website and notes.
private struct BankEditorView: View {
    @Bindable var bank: Bank
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var website = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledTextField(title: "Name", text: $name)
                    LabeledTextField(title: "Website", text: $website, prompt: "e.g. maplebank.com")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, prompt: Text("e.g. Uses ChexSystems; phone support hours"), axis: .vertical)
                        .lineLimit(3...10)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Bank")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        bank.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        bank.website = website.trimmingCharacters(in: .whitespacesAndNewlines)
                        bank.notes = notes
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = bank.name
                website = bank.website
                notes = bank.notes
            }
        }
        .sheetFrame(width: 460, height: 320)
    }
}
