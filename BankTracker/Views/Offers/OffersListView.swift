import SwiftUI
import SwiftData
import BankTrackerCore

struct OffersListView: View {
    @Query(sort: \Offer.foundDate, order: .reverse) private var offers: [Offer]
    @Query private var accounts: [BankAccount]
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.residenceState) private var residenceState = ""
    @State private var filter: Filter = .considering
    @State private var searchText = ""
    @State private var offerToDelete: Offer?

    enum Filter: String, CaseIterable, Identifiable {
        case considering = "Considering"
        case opened = "Opened"
        case closed = "Skipped or expired"
        case all = "All"

        var id: Self { self }

        func includes(_ offer: Offer) -> Bool {
            switch self {
            case .considering: offer.status == .considering && !offer.isExpired
            case .opened: offer.status == .opened
            case .closed: offer.status == .skipped || offer.isExpired
            case .all: true
            }
        }
    }

    var body: some View {
        let history = accounts.map(\.snapshot)
        let visible = offers.filter { offer in
            filter.includes(offer) && (searchText.isEmpty || offer.title.localizedCaseInsensitiveContains(searchText))
        }
        List {
            ForEach(visible) { offer in
                NavigationLink(value: offer) {
                    OfferRow(
                        offer: offer,
                        report: offer.status == .considering
                            ? offer.eligibilityReport(history: history, residenceState: residenceState)
                            : nil
                    )
                }
                .contextMenu {
                    Button("Delete Offer…", role: .destructive) { offerToDelete = offer }
                }
            }
            .onDelete { indexSet in
                offerToDelete = indexSet.first.map { visible[$0] }
            }
        }
        #if os(iOS)
        // On the Mac the list sits in a card; on iPhone and iPad it shares the page background.
        .groundBackground()
        #endif
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label(offers.isEmpty ? "No offers yet" : "Nothing here", systemImage: "tag")
                } description: {
                    Text(offers.isEmpty
                         ? "Found a bonus offer? Add it to see whether you're eligible."
                         : "No offers match this filter.")
                } actions: {
                    if offers.isEmpty {
                        Button("Add Offer") { router.isPresentingNewOffer = true }
                    }
                }
            }
        }
        .cardContainer()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader("Offers", subtitle: subtitle)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { option in
                            FilterChip(
                                title: "\(option.rawValue) · \(offers.filter(option.includes).count)",
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
        .searchable(text: $searchText, prompt: "Search offers")
        .navigationTitle("Offers")
        .hidesToolbarTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Offer", systemImage: "plus") { router.isPresentingNewOffer = true }
            }
        }
        .confirmationDialog(
            "Delete this offer?",
            isPresented: Binding(get: { offerToDelete != nil }, set: { if !$0 { offerToDelete = nil } }),
            presenting: offerToDelete
        ) { offer in
            Button("Delete \(offer.title)", role: .destructive) { context.delete(offer) }
        } message: { _ in
            Text("Accounts you opened with it are kept.")
        }
    }

    private var subtitle: String {
        let considering = offers.filter { Filter.considering.includes($0) }.count
        let opened = offers.filter { $0.status == .opened }.count
        return "\(considering) considering · \(opened) opened"
    }
}

struct OfferRow: View {
    let offer: Offer
    let report: EligibilityReport?

    var body: some View {
        // The badge sits under the amount, or under the details when the title needs the width.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                BankMonogram(name: offer.bankName, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    title
                    details
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    amount
                    badge
                }
            }
            HStack(alignment: .top, spacing: 12) {
                BankMonogram(name: offer.bankName, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title
                        Spacer(minLength: 0)
                        amount
                    }
                    details
                    badge
                        .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: some View {
        Text(offer.title)
            .font(.system(size: 14, weight: .semibold))
    }

    private var details: some View {
        Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var amount: some View {
        Text(Money.format(offer.bonusAmount))
            .font(Theme.amount(16))
    }

    @ViewBuilder
    private var badge: some View {
        if let report {
            report.verdict.badge
        } else if offer.isExpired {
            StatusBadge(text: "Expired", systemImage: "calendar.badge.exclamationmark", tint: .secondary)
        } else {
            StatusBadge(
                text: offer.status.displayName,
                systemImage: offer.status == .opened ? "checkmark.circle" : "arrow.uturn.right.circle",
                tint: .secondary
            )
        }
    }

    private var detail: String {
        var parts = [offer.accountType.displayName]
        if let expiration = offer.expirationDate {
            parts.append((offer.isExpired ? "Ended " : "Ends ") + DateText.format(expiration))
        } else {
            parts.append("Found \(DateText.format(offer.foundDate))")
        }
        return parts.joined(separator: " · ")
    }
}
