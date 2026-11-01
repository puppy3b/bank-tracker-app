import SwiftUI
import BankTrackerCore

/// "Next 60 days": one lane per account or offer, with deadlines, expected bonuses and
/// safe-to-close dates on a shared time axis. Dates come from each account's timeline.
struct UpcomingTimeline: View {
    struct Event: Identifiable {
        enum Kind { case deadline, payout, close }

        let id: String
        let kind: Kind
        let date: Date
        let title: String
        var showsLabel = true
    }

    struct Lane: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let events: [Event]
        let account: BankAccount?
        let offer: Offer?
    }

    let accounts: [BankAccount]
    let offers: [Offer]
    let today: Date
    let open: (Lane) -> Void
    @Environment(\.isCompactLayout) private var isCompact

    static let days = 60
    #if os(macOS)
    private let nameWidth: CGFloat = 200
    #else
    private let nameWidth: CGFloat = 130
    #endif

    var body: some View {
        let lanes = Self.lanes(accounts: accounts, offers: offers, today: today)
        CardSection("Next 60 days") {
            if !isCompact { legend }
        } content: {
            if lanes.isEmpty {
                Text("Nothing scheduled in the next 60 days.")
                    .foregroundStyle(.secondary)
                    .cardRow()
            } else if isCompact {
                agenda(lanes)
            } else {
                ViewThatFits(in: .horizontal) {
                    chart(lanes).frame(minWidth: 640)
                    ScrollView(.horizontal, showsIndicators: false) {
                        chart(lanes).frame(width: 640)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    /// On iPhone the chart doesn't fit, so the same events are listed by date, soonest first.
    private func agenda(_ lanes: [Lane]) -> some View {
        let entries = lanes
            .flatMap { lane in lane.events.map { (lane: lane, event: $0) } }
            .sorted { $0.event.date < $1.event.date }
        return ForEach(entries, id: \.event.id) { entry in
            Button {
                open(entry.lane)
            } label: {
                HStack(spacing: 12) {
                    Text(entry.event.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .leading)
                    mark(for: entry.event.kind)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.event.kind == .payout ? "\(entry.event.title) bonus expected" : entry.event.title)
                            .font(.system(size: 14, weight: .semibold))
                        Text("\(entry.lane.title) · \(entry.lane.subtitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cardRow(vertical: 10)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Deadline") { DeadlineMark() }
            legendItem("Bonus expected") { PayoutMark() }
            legendItem("Safe to close") { CloseMark() }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func legendItem(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 6) {
            mark()
            Text(title)
        }
    }

    private func chart(_ lanes: [Lane]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: nameWidth, height: 1)
                axis
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            ForEach(lanes) { lane in
                Button {
                    open(lane)
                } label: {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lane.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(lane.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .padding(.trailing, 12)
                        .frame(width: nameWidth, alignment: .leading)
                        track(lane)
                            .frame(height: 50)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cardRow(vertical: 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(for: lane))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private var axis: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                ForEach([14, 30, 44], id: \.self) { offset in
                    Text(Self.date(offset, from: today).formatted(.dateTime.month(.abbreviated).day()))
                        .frame(width: 70)
                        .offset(x: width * CGFloat(offset) / CGFloat(Self.days) - 35)
                }
                Text(Self.date(Self.days, from: today).formatted(.dateTime.month(.abbreviated).day()))
                    .frame(width: width, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(height: 18)
    }

    private func track(_ lane: Lane) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                Path { path in
                    for day in stride(from: 7, to: Self.days, by: 7) {
                        let x = width * CGFloat(day) / CGFloat(Self.days)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Theme.hairline, lineWidth: 1)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                ForEach(lane.events) { event in
                    marker(event, x: max(10, width * fraction(of: event.date)), width: width)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ event: Event, x: CGFloat, width: CGFloat) -> some View {
        let label = Text(event.title).fontWeight(.semibold) + Text(" · \(event.date.formatted(.dateTime.month(.abbreviated).day()))")
        if x > width * 0.72 {
            HStack(spacing: 8) {
                if event.showsLabel { label.font(.caption).lineLimit(1) }
                mark(for: event.kind)
            }
            .frame(width: x + 6, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                mark(for: event.kind)
                if event.showsLabel { label.font(.caption).lineLimit(1) }
            }
            .padding(.leading, max(0, x - 6))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func mark(for kind: Event.Kind) -> some View {
        switch kind {
        case .deadline: DeadlineMark()
        case .payout: PayoutMark()
        case .close: CloseMark()
        }
    }

    private func fraction(of date: Date) -> CGFloat {
        let days = Calendar.current.dayCount(from: today, to: date)
        return min(1, max(0, CGFloat(days) / CGFloat(Self.days)))
    }

    private func accessibilityText(for lane: Lane) -> String {
        let events = lane.events.map { event in
            let kind = switch event.kind {
            case .deadline: "deadline"
            case .payout: "bonus expected"
            case .close: "safe to close"
            }
            return "\(event.title), \(kind), \(DateText.format(event.date))"
        }
        return "\(lane.title) \(lane.subtitle). " + events.joined(separator: "; ")
    }

    // MARK: - Lanes

    static func date(_ offset: Int, from today: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today)) ?? today
    }

    static func lanes(accounts: [BankAccount], offers: [Offer], today: Date) -> [Lane] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = date(days, from: today)
        func inWindow(_ date: Date) -> Bool { date >= start && date <= end }

        var lanes: [Lane] = []
        for account in accounts where account.isOpen {
            let snapshot = account.snapshot
            let timeline = snapshot.timeline(today: today)
            let status = snapshot.bonusStatus(in: timeline)
            var events: [Event] = []

            switch status {
            case .inProgress:
                for requirement in snapshot.terms.requirements {
                    guard let schedule = timeline.schedule(for: requirement.id), !schedule.isSatisfied else { continue }
                    // Money already in only has to stay put; its hold is added below.
                    if requirement.hasHold, requirement.progress.fundedOn != nil, schedule.holdUntil != nil { continue }
                    if let deadline = schedule.deadline {
                        events.append(Event(id: "req-\(requirement.id)", kind: .deadline, date: deadline, title: shortTitle(requirement)))
                    }
                }
                if let payout = timeline.expectedPayout {
                    events.append(Event(id: "pay-\(account.uuid)", kind: .payout, date: payout, title: Money.format(snapshot.terms.bonusAmount)))
                }
            case .awaitingPayout:
                if let payout = timeline.expectedPayout {
                    events.append(Event(id: "pay-\(account.uuid)", kind: .payout, date: payout, title: Money.format(snapshot.terms.bonusAmount)))
                }
            case .received, .forfeited:
                if !snapshot.isKeeper {
                    let close = max(start, timeline.earliestCloseDate)
                    let title = timeline.earliestCloseDate <= start ? "Can close now" : "Safe to close"
                    events.append(Event(id: "close-\(account.uuid)", kind: .close, date: close, title: title))
                }
            case .noBonus:
                break
            }
            for hold in snapshot.holds(in: timeline) where hold.fundedOn != nil && hold.until > start {
                events.append(Event(id: "hold-\(hold.id)", kind: .deadline, date: hold.until, title: "Keep \(Money.format(hold.amount)) until"))
            }

            let visible = labeled(events.filter { inWindow($0.date) })
            if !visible.isEmpty {
                lanes.append(Lane(id: "account-\(account.uuid)", title: account.bankName, subtitle: account.productLabel, events: visible, account: account, offer: nil))
            }
        }

        for offer in offers where offer.status == .considering && !offer.isExpired {
            guard let expiration = offer.expirationDate.map({ calendar.startOfDay(for: $0) }), inWindow(expiration) else { continue }
            lanes.append(Lane(
                id: "offer-\(offer.uuid)",
                title: offer.bankName,
                subtitle: "\(offer.productLabel) offer",
                events: [Event(id: "ends-\(offer.uuid)", kind: .deadline, date: expiration, title: "Offer ends")],
                account: nil,
                offer: offer
            ))
        }

        return Array(lanes.sorted { ($0.events.map(\.date).min() ?? end) < ($1.events.map(\.date).min() ?? end) }.prefix(8))
    }

    /// Hides labels that would sit on top of the previous one.
    private static func labeled(_ events: [Event]) -> [Event] {
        var lastLabeled: Date?
        return events.sorted { $0.date < $1.date }.map { event in
            var event = event
            if let lastLabeled, Calendar.current.dayCount(from: lastLabeled, to: event.date) < 13 {
                event.showsLabel = false
            } else {
                lastLabeled = event.date
            }
            return event
        }
    }

    private static func shortTitle(_ requirement: BonusRequirement) -> String {
        let money = Money.format(requirement.amount)
        switch requirement.kind {
        case .directDeposit: return requirement.amount > 0 ? "\(money) direct deposit" : "Direct deposit"
        case .deposit: return requirement.amount > 0 ? "Deposit \(money)" : "Deposit"
        case .maintainBalance: return "Fund \(money)"
        case .debitPurchases: return requirement.count > 0 ? "\(requirement.count) debit purchases" : "Debit purchases"
        case .billPay: return requirement.count > 0 ? "\(requirement.count) bill payments" : "Bill payments"
        case .other: return requirement.details.isEmpty ? "Requirement" : String(requirement.details.prefix(24))
        }
    }
}

// MARK: - Marks (shape plus color, so they read without color too)

struct DeadlineMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(45))
            .padding(1.5)
            .accessibilityHidden(true)
    }
}

struct PayoutMark: View {
    var body: some View {
        Circle()
            .fill(Theme.money)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

struct CloseMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.closeGray)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
