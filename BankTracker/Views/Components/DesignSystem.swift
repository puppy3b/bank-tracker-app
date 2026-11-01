import SwiftUI
import BankTrackerCore

// The pieces from the "Design language" sheet: tokens, cards, page headers,
// the bonus journey track, stat tiles, filter chips and AI badges.

// MARK: - Tokens

enum Theme {
    static let ground = Color("Ground")
    static let surface = Color("Surface")
    static let hairline = Color("Hairline")
    static let track = Color("TrackGray")
    /// Bonuses paid or expected. Used for marks only, never for text.
    static let money = Color("Money")
    /// Safe-to-close marks.
    static let closeGray = Color("CloseGray")

    static let radius: CGFloat = 14

    #if os(macOS)
    static let pagePadding: CGFloat = 36
    #else
    static let pagePadding: CGFloat = 16
    #endif

    /// Columns for a grid of stat tiles: two on iPhone, otherwise as many as fit.
    static func tileColumns(compact: Bool, minimum: CGFloat, spacing: CGFloat) -> [GridItem] {
        compact
            ? Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2)
            : [GridItem(.adaptive(minimum: minimum), spacing: spacing)]
    }

    /// Amounts and headline numbers use SF Pro Rounded.
    static func amount(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension EnvironmentValues {
    /// iPhone, or an iPad window narrow enough to use iPhone layouts: grids use two columns and
    /// charts give way to lists. Set at the root from the horizontal size class; always false on the Mac.
    @Entry var isCompactLayout = false
}

// MARK: - Cards

extension View {
    /// White (or dark-gray) surface with a hairline border.
    func card(radius: CGFloat = Theme.radius) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }

    /// One row inside a `CardSection`: padded, with a hairline above it.
    func cardRow(vertical: CGFloat = 13) -> some View {
        padding(.horizontal, 20)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline.opacity(0.7)).frame(height: 1)
            }
    }
}

/// A card with a title row; rows inside use `.cardRow()`.
struct CardSection<Trailing: View, Content: View>: View {
    let title: String
    let trailing: Trailing
    let content: Content

    init(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .card()
    }
}

extension CardSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, trailing: { EmptyView() }, content: content)
    }
}

/// A footnote as the last row of a `CardSection`.
struct SectionNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .cardRow(vertical: 12)
    }
}

/// A row inside a `CardSection` that opens another page.
struct CardLink<Value: Hashable, Label: View>: View {
    let value: Value
    var vertical: CGFloat = 10
    @ViewBuilder let label: Label

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardRow(vertical: vertical)
    }
}

/// A label above a value, for the narrow side column of a detail page.
struct SummaryLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardRow(vertical: 10)
    }
}

/// A rounded tile holding a tinted symbol, used at the start of list rows.
struct IconTile: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Page headers

/// A large title with a subtitle and optional actions. On iPhone and iPad the navigation bar
/// already shows the large title, so only the subtitle and actions appear.
struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let actions: Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        // The actions sit beside the title, or below it when there isn't room.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                titles
                Spacer(minLength: 16)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                titles
                actions
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            #if os(macOS)
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            #endif
        }
    }
}

extension PageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// The header of a form's first section, with the page title above it on the Mac so the
/// title lines up with the form's centered content. iPhone and iPad show the large title
/// in the navigation bar, so only the section title appears there.
struct FormSectionHeader: View {
    let page: String
    let subtitle: String?
    let section: String

    init(page: String, subtitle: String? = nil, section: String) {
        self.page = page
        self.subtitle = subtitle
        self.section = section
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(page, subtitle: subtitle)
                .foregroundStyle(.primary)
                .padding(.bottom, 20)
            Text(section)
        }
        #else
        Text(section)
        #endif
    }
}

extension View {
    /// On macOS the page shows its own large title, so the toolbar doesn't repeat it.
    func hidesToolbarTitle() -> some View {
        #if os(macOS)
        return toolbar(removing: .title)
        #else
        return self
        #endif
    }

    /// A detail page shows its name in its own header card, so on iPhone and iPad the navigation
    /// bar uses the small title instead of repeating it in large type.
    func detailPageTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// The background of a header pinned above a list. It stays within the safe area: reaching
    /// under the navigation bar would hide the large title on iPhone and iPad.
    func pinnedHeaderBackground() -> some View {
        background(Theme.ground, ignoresSafeAreaEdges: [])
    }

    /// On the Mac, a list or table sits in a rounded, bordered box with page margins.
    @ViewBuilder
    func cardContainer() -> some View {
        #if os(macOS)
        clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline))
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        #else
        self
        #endif
    }

    /// The page background, behind lists and forms too.
    func groundBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.ground)
    }
}

// MARK: - Filter chips

/// A pill that filters a list; the selected one is filled.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.ground : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(isSelected ? Color.primary : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - AI badges

/// Marks a field that AI filled in, so it gets a second look.
struct AIBadge: View {
    var body: some View {
        Text("AI")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel("Filled by AI")
    }
}

/// A field or section label, with an AI badge when AI filled it.
struct FieldLabel: View {
    let title: String
    var isAIFilled = false

    init(_ title: String, isAIFilled: Bool = false) {
        self.title = title
        self.isAIFilled = isAIFilled
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if isAIFilled { AIBadge() }
        }
    }
}

// MARK: - Stat tiles

/// A headline number: label, rounded value, one detail line.
struct StatTile: View {
    let label: String
    let value: String
    var detail: String?
    var showsMoneyDot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if showsMoneyDot {
                    Circle().fill(Theme.money).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Text(label)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.amount(30))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // Always one detail line, so tiles in a row line up.
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(detail == nil)
        }
        // Fills its grid row, so tiles side by side match when one label wraps.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bonus journey

/// One stop on an account's journey: Opened → Requirements → Bonus posts → Safe to close.
struct JourneyStop: Identifiable, Hashable {
    enum State: Hashable {
        case done
        case current
        case upcoming
        /// The bonus has posted.
        case paid
        /// Doesn't apply, e.g. an account without a bonus.
        case inactive
    }

    let id: Int
    let title: String
    let detail: String
    var note: String?
    let state: State
    var isMoney = false
}

/// Builds journey stops from what the timeline already computed.
enum Journey {
    static func stops(for snapshot: AccountSnapshot, timeline: BonusTimeline, status: BonusStatus, today: Date = .now) -> [JourneyStop] {
        let start = Calendar.current.startOfDay(for: today)
        let opened = JourneyStop(id: 0, title: "Opened", detail: DateText.format(snapshot.openedDate), state: .done)
        let close = closeStop(for: snapshot, timeline: timeline, status: status, start: start)

        guard snapshot.hasBonus else {
            return [
                opened,
                JourneyStop(id: 1, title: "Requirements", detail: "No bonus", state: .inactive),
                JourneyStop(id: 2, title: "Bonus posts", detail: "No bonus", state: .inactive, isMoney: true),
                close,
            ]
        }

        let total = snapshot.terms.requirements.count
        let done = timeline.requirements.filter(\.isSatisfied).count
        let requirements: JourneyStop
        switch status {
        case .inProgress:
            let due = timeline.outstandingDeadline
            let detail = [due.map { "Due \(DateText.format($0))" }, total > 0 ? "\(done) of \(total) done" : nil]
                .compactMap { $0 }
                .joined(separator: " · ")
            requirements = JourneyStop(id: 1, title: "Requirements", detail: detail, note: due.map { RelativeDay.text(for: $0) }, state: .current)
        case .forfeited where timeline.requirementsMetOn == nil:
            requirements = JourneyStop(id: 1, title: "Requirements", detail: "Not met", state: .inactive)
        default:
            let detail = total == 0 ? "None" : (timeline.requirementsMetOn.map { "Done \(DateText.format($0))" } ?? "Done")
            requirements = JourneyStop(id: 1, title: "Requirements", detail: detail, state: .done)
        }

        let expected = timeline.expectedPayout
        let bonus: JourneyStop
        switch status {
        case .inProgress:
            bonus = JourneyStop(id: 2, title: "Bonus posts", detail: expected.map { "By \(DateText.format($0))" } ?? "After requirements", state: .upcoming, isMoney: true)
        case .awaitingPayout:
            bonus = JourneyStop(id: 2, title: "Bonus posts", detail: expected.map { "By \(DateText.format($0))" } ?? "Soon", note: expected.map { RelativeDay.text(for: $0) }, state: .current, isMoney: true)
        case .received:
            bonus = JourneyStop(id: 2, title: "Bonus posts", detail: snapshot.bonusReceivedDate.map { "Paid \(DateText.format($0))" } ?? "Paid", state: .paid, isMoney: true)
        case .forfeited, .noBonus:
            bonus = JourneyStop(id: 2, title: "Bonus posts", detail: "Forfeited", state: .inactive, isMoney: true)
        }

        return [opened, requirements, bonus, close]
    }

    private static func closeStop(for snapshot: AccountSnapshot, timeline: BonusTimeline, status: BonusStatus, start: Date) -> JourneyStop {
        let title = "Safe to close"
        if let closed = snapshot.closedDate {
            return JourneyStop(id: 3, title: title, detail: "Closed \(DateText.format(closed))", state: .done)
        }
        if snapshot.isKeeper {
            return JourneyStop(id: 3, title: title, detail: "Keeper", state: .upcoming)
        }
        let earliest = timeline.earliestCloseDate
        if !snapshot.hasBonus {
            return JourneyStop(id: 3, title: title, detail: earliest <= start ? "Any time" : "After \(DateText.format(earliest))", state: .upcoming)
        }
        if (status == .received || status == .forfeited), earliest <= start {
            return JourneyStop(id: 3, title: title, detail: "Now", state: .current)
        }
        return JourneyStop(id: 3, title: title, detail: "After \(DateText.format(earliest))", state: .upcoming)
    }

    /// A short label for where an account is, e.g. "Requirements · 1 of 2 done".
    static func stage(for snapshot: AccountSnapshot, timeline: BonusTimeline, status: BonusStatus, today: Date = .now) -> String {
        if let closed = snapshot.closedDate { return "Closed \(DateText.format(closed))" }
        switch status {
        case .noBonus:
            return snapshot.isKeeper ? "Keeper · no bonus" : "No bonus"
        case .inProgress:
            let total = snapshot.terms.requirements.count
            let done = timeline.requirements.filter(\.isSatisfied).count
            return total > 0 ? "Requirements · \(done) of \(total) done" : "Requirements"
        case .awaitingPayout:
            return "Waiting for bonus"
        case .received:
            if snapshot.isKeeper { return "Keeper · bonus paid" }
            return timeline.earliestCloseDate <= Calendar.current.startOfDay(for: today) ? "Ready to close" : "Bonus paid"
        case .forfeited:
            return "Forfeited"
        }
    }
}

struct JourneyDot: View {
    let state: JourneyStop.State
    var isMoney = false
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(Color.accentColor)
                checkmark
            case .paid:
                Circle().fill(Theme.money)
                checkmark
            case .current:
                Circle().fill(Theme.surface)
                Circle().strokeBorder(Color.accentColor, lineWidth: max(2.5, size * 0.15))
            case .upcoming:
                Circle().fill(Theme.surface)
                Circle().strokeBorder(isMoney ? Theme.money : Theme.track, lineWidth: max(2, size * 0.14))
            case .inactive:
                Circle().fill(Theme.hairline)
            }
        }
        .frame(width: size, height: size)
        .background {
            if state == .current, size >= 16 {
                Circle().fill(Color.accentColor.opacity(0.15)).padding(-4)
            }
        }
    }

    @ViewBuilder
    private var checkmark: some View {
        if size >= 16 {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// The full journey track with titles and dates under each stop, or down the side when the
/// stops don't fit across.
struct JourneyTrack: View {
    let stops: [JourneyStop]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            across
            down
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(stops))
    }

    private var across: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stops) { stop in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        JourneyDot(state: stop.state, isMoney: stop.isMoney)
                        if stop.id < stops.count - 1 {
                            Capsule()
                                .fill(Self.reached(stops, after: stop.id) ? Color.accentColor : Theme.track.opacity(0.7))
                                .frame(height: 3)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(stop.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let note = stop.note {
                            Text(note)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.trailing, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var down: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stops) { stop in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        JourneyDot(state: stop.state, isMoney: stop.isMoney)
                        if stop.id < stops.count - 1 {
                            Capsule()
                                .fill(Self.reached(stops, after: stop.id) ? Color.accentColor : Theme.track.opacity(0.7))
                                .frame(width: 3)
                                .frame(maxHeight: .infinity)
                                .padding(.bottom, 4)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title)
                            .font(.system(size: 13, weight: .semibold))
                        (Text(stop.detail).foregroundStyle(.secondary)
                            + Text(stop.note.map { " · \($0)" } ?? "").fontWeight(.semibold).foregroundStyle(Color.accentColor))
                            .font(.caption)
                    }
                    .padding(.top, 1)
                    .padding(.bottom, stop.id < stops.count - 1 ? 14 : 0)
                    Spacer(minLength: 0)
                }
                // Lets the connecting line stretch to the height of the text beside it.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func reached(_ stops: [JourneyStop], after index: Int) -> Bool {
        guard stops.indices.contains(index + 1) else { return false }
        switch stops[index + 1].state {
        case .done, .paid, .current: return true
        case .upcoming, .inactive: return false
        }
    }

    static func summary(_ stops: [JourneyStop]) -> String {
        "Bonus journey. " + stops.map { "\($0.title): \($0.detail)" }.joined(separator: ". ")
    }
}

/// The compact track used in tables and lists.
struct JourneyMini: View {
    let stops: [JourneyStop]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stops) { stop in
                JourneyDot(state: stop.state, size: 10)
                if stop.id < stops.count - 1 {
                    Rectangle()
                        .fill(JourneyTrack.reached(stops, after: stop.id) ? Color.accentColor : Theme.track.opacity(0.7))
                        .frame(width: 14, height: 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneyTrack.summary(stops))
    }
}
