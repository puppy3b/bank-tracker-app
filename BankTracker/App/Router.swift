import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case offers
    case accounts
    case banks
    case taxes
    case stats
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Today"
        case .offers: "Offers"
        case .accounts: "Accounts"
        case .banks: "Banks"
        case .taxes: "Taxes"
        case .stats: "Statistics"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .offers: "tag"
        case .accounts: "creditcard"
        case .banks: "building.columns"
        case .taxes: "doc.text"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }

    /// The sections at the top of the sidebar. Settings sits on its own below them.
    static let mainItems: [SidebarItem] = allCases.filter { $0 != .settings }
}

/// Shared navigation state, so any screen (or a menu command) can open another.
@Observable
final class Router {
    var selection: SidebarItem? = Router.launchSection
    var path = NavigationPath()
    var isPresentingNewOffer = false
    var isPresentingNewAccount = false

    func push(_ value: some Hashable) {
        path.append(value)
    }

    func show(_ item: SidebarItem) {
        selection = item
        path = NavigationPath()
    }

    /// The section to open at launch: `--section <name>` (e.g. `--section stats`), else the dashboard.
    private static var launchSection: SidebarItem {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--section"),
              arguments.indices.contains(index + 1),
              let section = SidebarItem(rawValue: arguments[index + 1])
        else { return .dashboard }
        return section
    }
}
