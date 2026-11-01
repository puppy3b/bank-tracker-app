import SwiftUI
import SwiftData
import BankTrackerCore

/// Sidebar + detail. On iPhone the split view collapses into a single navigation stack.
struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var accounts: [BankAccount]
    @Query private var offers: [Offer]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = ReminderDefaults.enabled
    @AppStorage(SettingsKey.reminderMinuteOfDay) private var reminderMinuteOfDay = ReminderDefaults.minuteOfDay
    @AppStorage(SettingsKey.reminderLeadDays) private var reminderLeadDays = ReminderDefaults.leadDays

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            List(selection: $router.selection) {
                Section {
                    ForEach(SidebarItem.mainItems) { item in
                        sidebarRow(item)
                    }
                }
                Section {
                    sidebarRow(.settings)
                }
            }
            .navigationTitle("Bank Tracker")
            #if os(macOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Image("AppMark")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                    Text("Bank Tracker")
                        .font(.system(size: 15, weight: .bold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            #endif
        } detail: {
            NavigationStack(path: $router.path) {
                SectionRootView(item: router.selection ?? .dashboard)
                    .navigationDestination(for: BankAccount.self) { AccountDetailView(account: $0) }
                    .navigationDestination(for: Offer.self) { OfferDetailView(offer: $0) }
                    .navigationDestination(for: Bank.self) { BankDetailView(bank: $0) }
            }
        }
        .onChange(of: router.selection) {
            router.path = NavigationPath()
        }
        .sheet(isPresented: $router.isPresentingNewOffer) {
            OfferEditorView(offer: nil) { offer in router.push(offer) }
        }
        .sheet(isPresented: $router.isPresentingNewAccount) {
            AccountEditorView(account: nil) { account in router.push(account) }
        }
        // Reschedules when the reminders change (data or settings edited) and on returning to
        // the app, which also picks up notifications being turned on in System Settings.
        .task(id: reminderSchedule) {
            guard ReminderNotifications.isActiveForThisLaunch else { return }
            await ReminderNotifications.shared.schedule(reminderSchedule.reminders, enabled: remindersEnabled)
        }
        .onAppear {
            ReminderNotifications.shared.open = { target in open(target) }
        }
        #if DEBUG && os(macOS)
        .task { await DebugSnapshots.runIfRequested(router: router, context: context) }
        .task { await DebugSnapshots.runTourIfRequested(router: router, context: context) }
        .task { await DebugSnapshots.runClickTestIfRequested(router: router) }
        .task { await DebugSnapshots.runAIFillTestIfRequested(router: router) }
        .task { DebugSnapshots.runKeychainTestIfRequested() }
        .task { DebugSnapshots.runAISettingsTestIfRequested() }
        #endif
        #if DEBUG && os(iOS)
        .task { await IOSDebugTour.runIfRequested(router: router, context: context) }
        .task { await IOSDebugTour.runReminderCheckIfRequested(router: router, context: context) }
        #endif
        #if os(iOS)
        .environment(\.isCompactLayout, sizeClass == .compact)
        #endif
    }

    private struct ReminderSchedule: Equatable {
        var reminders: [Reminder]
        var enabled: Bool
        var isActive: Bool
    }

    private var reminderSchedule: ReminderSchedule {
        let reminders = remindersEnabled
            ? ReminderPlanner(leadDays: reminderLeadDays, minuteOfDay: reminderMinuteOfDay)
                .reminders(accounts: accounts.map(\.snapshot), offers: offers.map(\.snapshot))
            : []
        return ReminderSchedule(reminders: reminders, enabled: remindersEnabled, isActive: scenePhase == .active)
    }

    /// Opens the account or offer a tapped reminder is about.
    private func open(_ target: ReminderTarget) {
        switch target {
        case .account(let id):
            if let account = accounts.first(where: { $0.uuid == id }) { show(account, in: .accounts) }
        case .offer(let id):
            if let offer = offers.first(where: { $0.uuid == id }) { show(offer, in: .offers) }
        }
    }

    private func show(_ value: some Hashable, in section: SidebarItem) {
        Task {
            router.show(section)
            // Let the section switch, which clears the path, settle before pushing.
            try? await Task.sleep(for: .milliseconds(400))
            router.push(value)
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) {
            Label(item.title, systemImage: item.systemImage)
        }
        .badge(badgeCount(for: item))
        // The tag must be a SidebarItem; without it the row is tagged with its
        // String id, and clicking it sets the selection to nil.
        .tag(item)
    }

    private func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .dashboard:
            let items = ActionPlanner().items(accounts: accounts.map(\.snapshot), offers: offers.map(\.snapshot))
            return items.filter { $0.urgency <= .dueSoon }.count
        case .offers:
            return offers.filter { $0.status == .considering && !$0.isExpired }.count
        default:
            return 0
        }
    }
}

private struct SectionRootView: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case .dashboard: DashboardView()
        case .offers: OffersListView()
        case .accounts: AccountsListView()
        case .banks: BanksListView()
        case .taxes: TaxView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(Router())
        .modelContainer(.preview)
}
