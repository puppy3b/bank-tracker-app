#if DEBUG && os(iOS)
import BankTrackerCore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Debug aid for the iPhone and iPad layout: launch in a simulator with `--demo --tour` to step
/// through every page with the sample data. At each stop, and after scrolling each further
/// screenful of a long page, the app prints `TOUR <name>` and holds still, so a script can take
/// a screenshot with `xcrun simctl io <device> screenshot` (or `xcrun devicectl device capture
/// screenshot` on a real device, which is slower; add `--tour-hold <seconds>` to wait longer).
/// It quits after `TOUR done`.
enum IOSDebugTour {
    static func runIfRequested(router: Router, context: ModelContext) async {
        guard ProcessInfo.processInfo.arguments.contains("--tour") else { return }
        // A real device would otherwise lock partway through.
        UIApplication.shared.isIdleTimerDisabled = true
        try? await Task.sleep(for: .seconds(2))

        for screen in screens(router: router, context: context) {
            await screen.show()
            try? await Task.sleep(for: .milliseconds(1500))
            await hold(screen.name)
            // Long pages: one more stop per screenful, up to a few.
            var page = 1
            while page < 6, let scrollView = mainScrollView(), scrollView.scrollsFurther {
                page += 1
                let step = scrollView.bounds.height - scrollView.adjustedContentInset.top - 80
                let bottom = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
                scrollView.setContentOffset(CGPoint(x: 0, y: min(bottom, scrollView.contentOffset.y + step)), animated: false)
                try? await Task.sleep(for: .milliseconds(600))
                await hold("\(screen.name)-\(page)")
            }
            router.isPresentingNewOffer = false
            router.isPresentingNewAccount = false
            try? await Task.sleep(for: .milliseconds(800))
        }
        print("TOUR done")
        fflush(stdout)
        exit(0)
    }

    /// Debug aid: launch in a simulator with `--demo --reminder-check` to schedule reminders for
    /// the sample data, list what the system has scheduled, open one as a tap would, and quit.
    /// The simulator can't answer the permission prompt, so it asks for provisional permission,
    /// which needs no answer.
    static func runReminderCheckIfRequested(router: Router, context: ModelContext) async {
        guard ProcessInfo.processInfo.arguments.contains("--reminder-check") else { return }
        try? await Task.sleep(for: .seconds(2))
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .alert, .sound])
        let accounts = (try? context.fetch(FetchDescriptor<BankAccount>())) ?? []
        let offers = (try? context.fetch(FetchDescriptor<Offer>())) ?? []
        let planned = ReminderPlanner().reminders(accounts: accounts.map(\.snapshot), offers: offers.map(\.snapshot))
        await ReminderNotifications.shared.schedule(planned, enabled: true, askPermission: false)

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        print("CHECK planned \(planned.count), scheduled \(pending.count)")
        for request in pending.sorted(by: { $0.identifier < $1.identifier }) {
            let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            print("CHECK \(next.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "no trigger") | \(request.content.title) | \(request.content.body)")
        }

        if let reminder = planned.first(where: { $0.accountID != nil }), let id = reminder.accountID {
            router.show(.taxes)
            try? await Task.sleep(for: .milliseconds(800))
            ReminderNotifications.shared.open?(.account(id))
            try? await Task.sleep(for: .seconds(2))
            let name = accounts.first { $0.uuid == id }?.displayName ?? "?"
            print("CHECK opened \(name): section \(router.selection?.rawValue ?? "nil"), path \(router.path.count)")
            await hold("reminder-opened")
        }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("TOUR done")
        fflush(stdout)
        exit(0)
    }

    private static func hold(_ name: String) async {
        print("TOUR \(name)")
        fflush(stdout)
        try? await Task.sleep(for: .seconds(holdSeconds))
    }

    private static let holdSeconds: Double = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--tour-hold"), index + 1 < arguments.count else { return 1.5 }
        return Double(arguments[index + 1]) ?? 1.5
    }()

    private static func screens(router: Router, context: ModelContext) -> [(name: String, show: () async -> Void)] {
        let accounts = (try? context.fetch(FetchDescriptor<BankAccount>())) ?? []
        let offers = (try? context.fetch(FetchDescriptor<Offer>())) ?? []

        var screens: [(name: String, show: () async -> Void)] = [("sidebar", { router.selection = nil })]
        screens += SidebarItem.allCases.map { item in (item.rawValue, { router.show(item) }) }
        for status in [BonusStatus.inProgress, .awaitingPayout, .received] {
            if let account = accounts.first(where: { $0.isOpen && $0.snapshot.bonusStatus() == status }) {
                screens.append(("account-\(status.rawValue)", { await push(account, in: .accounts, router: router) }))
            }
        }
        if let offer = offers.first(where: { $0.status == .considering && $0.bank?.name.hasPrefix("Harbor") == true }) {
            screens.append(("offer-detail", { await push(offer, in: .offers, router: router) }))
        }
        if let bank = offers.compactMap(\.bank).first(where: { $0.accountList.count > 1 }) {
            screens.append(("bank-detail", { await push(bank, in: .banks, router: router) }))
        }
        screens.append(("new-offer", { router.show(.offers); router.isPresentingNewOffer = true }))
        screens.append(("new-account", { router.show(.accounts); router.isPresentingNewAccount = true }))
        return screens
    }

    private static func push(_ value: some Hashable, in section: SidebarItem, router: Router) async {
        router.show(section)
        try? await Task.sleep(for: .milliseconds(700))
        router.push(value)
    }

    /// The tallest scrolling view on top: in a sheet when one is showing, else the page.
    private static func mainScrollView() -> UIScrollView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let root = controller?.view else { return nil }
        return scrollViews(in: root)
            .filter { $0.isScrollEnabled && $0.window != nil && $0.bounds.height > 200 }
            .max { $0.bounds.height * $0.bounds.width < $1.bounds.height * $1.bounds.width }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        let own = (view as? UIScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }
}

private extension UIScrollView {
    var scrollsFurther: Bool {
        contentOffset.y + bounds.height < contentSize.height + adjustedContentInset.bottom - 4
    }
}
#endif
