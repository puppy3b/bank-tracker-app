import SwiftUI
import SwiftData
import Charts
import BankTrackerCore

/// Totals, breakdowns and a few fun numbers. Every chart is single-series in one hue,
/// with a table or direct labels so no value depends on hovering.
struct StatsView: View {
    @Query private var accounts: [BankAccount]
    @Environment(Router.self) private var router
    @Environment(\.isCompactLayout) private var isCompact

    var body: some View {
        let stats = PortfolioStats(accounts: accounts.map(\.snapshot))
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader("Statistics")
                HeroFigure(
                    label: "Total bonuses earned",
                    value: Money.format(stats.totalEarned),
                    detail: heroDetail(stats)
                )

                LazyVGrid(columns: Theme.tileColumns(compact: isCompact, minimum: 180, spacing: 12), spacing: 12) {
                    StatTile(label: "Earned this year", value: Money.compact(stats.earnedThisYear))
                    StatTile(label: "On the road", value: Money.compact(stats.pendingTotal), detail: "\(stats.pending.count) pending")
                    StatTile(label: "Accounts opened", value: "\(stats.accountsOpened)", detail: "\(stats.openAccounts) open · \(stats.closedAccounts) closed")
                    StatTile(label: "Funds parked", value: Money.compact(stats.fundsParked))
                    StatTile(label: "Fees paid", value: Money.compact(stats.feesPaid))
                    StatTile(label: "Average bonus", value: stats.averageBonus.map(Money.compact) ?? "—")
                    StatTile(label: "Days to payout", value: stats.averageDaysToPayout.map { "\($0)" } ?? "—", detail: "Average from opening")
                    StatTile(label: "Biggest bonus", value: stats.largestBonus.map { Money.compact($0.amount) } ?? "—", detail: stats.largestBonus?.accountName)
                }

                if !stats.earnedByYear.isEmpty {
                    ChartCard(title: "Bonuses earned by year") {
                        ColumnChart(data: stats.earnedByYear.map { year in
                            ChartDatum(
                                id: String(year.year),
                                label: String(year.year),
                                value: year.amount.doubleValue,
                                valueText: Money.format(year.amount),
                                detail: year.count == 1 ? "1 bonus" : "\(year.count) bonuses"
                            )
                        }, isCurrency: true)
                        YearTable(rows: stats.earnedByYear)
                    }
                }

                if !stats.earnedByBank.isEmpty {
                    ChartCard(title: "Earned by bank") {
                        RankedBarChart(data: topBanks(stats.earnedByBank).map { bank in
                            ChartDatum(
                                id: bank.bankName,
                                label: bank.bankName,
                                value: bank.amount.doubleValue,
                                valueText: Money.format(bank.amount),
                                detail: bank.count == 1 ? "1 bonus" : "\(bank.count) bonuses"
                            )
                        })
                    }
                }

                if !stats.openedByYear.isEmpty {
                    ChartCard(title: "Accounts opened by year") {
                        ColumnChart(data: stats.openedByYear.map { year in
                            ChartDatum(
                                id: String(year.year),
                                label: String(year.year),
                                value: Double(year.count),
                                valueText: "\(year.count)",
                                detail: year.count == 1 ? "1 account" : "\(year.count) accounts"
                            )
                        }, isCurrency: false)
                    }
                }

                if !stats.pending.isEmpty {
                    ChartCard(title: "Money on the road") {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.pending.enumerated()), id: \.element.id) { index, pending in
                                if index > 0 { Divider() }
                                Button { open(pending.accountID) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pending.accountName)
                                            Text(pending.expectedDate.map { "\(pending.status.displayName), expected by \(DateText.format($0))" } ?? pending.status.displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(Money.format(pending.amount))
                                            .monospacedDigit()
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Application pace")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        StatTile(label: "Opened, 6 months", value: "\(stats.velocity.openedLast6Months)")
                        StatTile(label: "Opened, 12 months", value: "\(stats.velocity.openedLast12Months)")
                        StatTile(label: "Opened, 24 months", value: "\(stats.velocity.openedLast24Months)")
                        StatTile(label: "Hard pulls, 12 months", value: "\(stats.velocity.hardPullsLast12Months)")
                        StatTile(label: "ChexSystems, 12 months", value: "\(stats.velocity.chexSystemsLast12Months)")
                    }
                    Text("Some banks decline applicants who have opened many accounts recently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            if accounts.isEmpty {
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.bar",
                    description: Text("Record accounts to see your totals.")
                )
            }
        }
        .navigationTitle("Statistics")
        .hidesToolbarTitle()
    }

    private func heroDetail(_ stats: PortfolioStats) -> String {
        let bonuses = stats.bonusesReceived == 1 ? "1 bonus" : "\(stats.bonusesReceived) bonuses"
        let banks = stats.earnedByBank.count == 1 ? "1 bank" : "\(stats.earnedByBank.count) banks"
        return "\(bonuses) from \(banks) · \(Money.format(stats.netEarnings)) after fees"
    }

    /// Eight bars at most; the rest fold into "Other".
    private func topBanks(_ banks: [PortfolioStats.BankTotal]) -> [PortfolioStats.BankTotal] {
        guard banks.count > 8 else { return banks }
        let rest = banks.dropFirst(7)
        return Array(banks.prefix(7)) + [PortfolioStats.BankTotal(bankName: "Other", amount: rest.sum(\.amount), count: rest.reduce(0) { $0 + $1.count })]
    }

    private func open(_ accountID: UUID) {
        if let account = accounts.first(where: { $0.uuid == accountID }) {
            router.push(account)
        }
    }
}

struct HeroFigure: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.amount(52))
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .card()
    }
}

struct ChartDatum: Identifiable, Hashable {
    let id: String
    let label: String
    let value: Double
    let valueText: String
    let detail: String
}

/// Vertical bars, one hue. The latest bar is labeled; hovering (or dragging on iPhone)
/// highlights a bar and shows its value.
struct ColumnChart: View {
    let data: [ChartDatum]
    let isCurrency: Bool
    @State private var selection: String?

    var body: some View {
        let maxValue = data.map(\.value).max() ?? 0
        let compactAxis = isCurrency && maxValue >= 10_000
        let labeled = selection ?? data.last?.label
        Chart(data) { datum in
            BarMark(
                x: .value("Year", datum.label),
                y: .value("Value", datum.value),
                width: .fixed(22)
            )
            .foregroundStyle(Palette.series)
            .opacity(selection == nil || selection == datum.label ? 1 : 0.4)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            .annotation(position: .top, spacing: 4) {
                if datum.label == labeled {
                    VStack(spacing: 0) {
                        Text(datum.valueText)
                            .font(.caption.weight(.semibold))
                        if selection != nil {
                            Text(datum.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartXSelection(value: $selection)
        .chartYScale(domain: 0...max(maxValue * 1.2, 1))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Palette.grid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(isCurrency ? Money.axisLabel(number, compact: compactAxis) : number.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .frame(height: 200)
    }
}

/// Horizontal bars ranked largest first, one hue, each value printed at its tip.
struct RankedBarChart: View {
    let data: [ChartDatum]
    @State private var selection: String?

    var body: some View {
        let maxValue = max(data.map(\.value).max() ?? 0, 1)
        Chart(data) { datum in
            BarMark(
                x: .value("Value", datum.value),
                y: .value("Name", datum.label),
                height: .fixed(18)
            )
            .foregroundStyle(Palette.series)
            .opacity(selection == nil || selection == datum.label ? 1 : 0.4)
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
            // Names go above their bars rather than on an axis, which on iPhone draws them over the bars.
            .annotation(position: .top, alignment: .leading, spacing: 3) {
                Text(datum.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .annotation(position: .trailing, spacing: 6) {
                Text(selection == datum.label ? "\(datum.valueText) · \(datum.detail)" : datum.valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYSelection(value: $selection)
        .chartXScale(domain: 0...(maxValue * 1.35))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: CGFloat(data.count) * 42 + 8)
    }
}

/// The table twin of the by-year chart.
private struct YearTable: View {
    let rows: [PortfolioStats.YearTotal]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                Text("Year")
                Text("Bonuses")
                Text("Earned").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(rows.reversed()) { row in
                GridRow {
                    Text(String(row.year))
                    Text("\(row.count)")
                    Text(Money.format(row.amount))
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
    .environment(Router())
    .modelContainer(.preview)
}
