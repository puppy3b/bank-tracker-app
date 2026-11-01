import SwiftUI
import SwiftData
import BankTrackerCore

struct OfferDetailView: View {
    @Bindable var offer: Offer
    @Query private var accounts: [BankAccount]
    @AppStorage(SettingsKey.residenceState) private var residenceState = ""
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditor = false
    @State private var showingOpenAccount = false
    @State private var confirmingDelete = false
    @Environment(\.isCompactLayout) private var isCompact

    var body: some View {
        let report = offer.eligibilityReport(history: accounts.map(\.snapshot), residenceState: residenceState)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overview

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        mainColumn(report)
                            .frame(maxWidth: .infinity, alignment: .top)
                        sideColumn(report)
                            .frame(width: 330)
                    }
                    .frame(minWidth: 780, idealWidth: 780, maxWidth: .infinity)
                    VStack(spacing: 18) {
                        mainColumn(report)
                        sideColumn(report)
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
        .navigationTitle(offer.title)
        .hidesToolbarTitle()
        .detailPageTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { showingEditor = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Status", selection: $offer.status) {
                        ForEach(OfferStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    Divider()
                    Button("Delete Offer…", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            OfferEditorView(offer: offer)
        }
        .sheet(isPresented: $showingOpenAccount) {
            AccountEditorView(account: nil, draft: AccountDraft(offer: offer)) { account in
                router.push(account)
            }
        }
        .confirmationDialog("Delete this offer?", isPresented: $confirmingDelete) {
            Button("Delete Offer", role: .destructive) {
                dismiss()
                context.delete(offer)
            }
        } message: {
            Text("Accounts you opened with it are kept.")
        }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The amount sits beside the title, or below it when the title needs the width.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    BankMonogram(name: offer.bankName, size: 52)
                    titles(size: 26)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(Money.format(offer.bonusAmount))
                            .font(Theme.amount(34))
                        statusBadge
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        BankMonogram(name: offer.bankName, size: 44)
                        titles(size: 22)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Text(Money.format(offer.bonusAmount))
                            .font(Theme.amount(30))
                        Spacer(minLength: 0)
                        statusBadge
                    }
                }
            }

            let showsFacts = offer.expirationDate != nil || !offer.promoCode.isEmpty
            if showsFacts || offer.status == .considering {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) {
                        facts
                        Spacer(minLength: 0)
                        openAccountButton
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        if showsFacts {
                            HStack(alignment: .center, spacing: 28) { facts }
                        }
                        openAccountButton
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.hairline.opacity(0.7)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, isCompact ? 18 : 26)
        .padding(.vertical, isCompact ? 18 : 22)
        .card(radius: 16)
    }

    private func titles(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(offer.title)
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
        Text("\(offer.accountType.displayName) offer · found \(DateText.format(offer.foundDate))")
            .foregroundStyle(.secondary)
        if let url = URL(string: offer.url), url.scheme != nil {
            Link("Open offer page", destination: url)
        }
    }

    @ViewBuilder
    private var facts: some View {
        if let expiration = offer.expirationDate {
            OverviewFact(
                title: offer.isExpired ? "Ended" : "Ends",
                value: DateText.format(expiration),
                detail: RelativeDay.text(for: expiration)
            )
        }
        if !offer.promoCode.isEmpty {
            OverviewFact(title: "Promo code", value: offer.promoCode)
        }
    }

    @ViewBuilder
    private var openAccountButton: some View {
        if offer.status == .considering {
            Button("Open Account with This Offer…", systemImage: "checkmark.circle") {
                showingOpenAccount = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(offer.bank == nil)
        }
    }

    // MARK: - Columns

    private func mainColumn(_ report: EligibilityReport) -> some View {
        VStack(spacing: 18) {
            if offer.status == .considering {
                EligibilityCard(report: report, accountType: offer.accountType)
            }
            RequirementsSummaryCard(terms: offer.terms)
            if !offer.notes.isEmpty {
                CardSection("Notes") {
                    Text(offer.notes)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .cardRow()
                }
            }
        }
    }

    private func sideColumn(_ report: EligibilityReport) -> some View {
        VStack(spacing: 18) {
            if !offer.linkedAccounts.isEmpty {
                CardSection("Opened with this offer") {
                    ForEach(offer.linkedAccounts) { account in
                        CardLink(value: account) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                Text("Opened \(DateText.format(account.openedDate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            TermsSummaryCard(terms: offer.terms)
            if offer.status == .considering {
                BankHistoryCard(report: report)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if offer.isExpired {
            StatusBadge(text: "Expired", systemImage: "calendar.badge.exclamationmark", tint: .secondary)
        } else {
            switch offer.status {
            case .considering: StatusBadge(text: "Considering", systemImage: "magnifyingglass", tint: .accentColor)
            case .opened: StatusBadge(text: "Opened", systemImage: "checkmark.circle.fill", tint: Palette.good)
            case .skipped: StatusBadge(text: "Skipped", systemImage: "arrow.uturn.right.circle", tint: .secondary)
            }
        }
    }
}

/// A small label-over-value fact in a page's overview card.
private struct OverviewFact: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 13.5, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
