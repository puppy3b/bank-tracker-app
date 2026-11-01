import SwiftUI
import BankTrackerCore

/// Asset-catalog colors from the validated data-viz palette. Charts use one hue (`series`);
/// status colors always appear next to an icon and a text label, never on their own.
enum Palette {
    static let series = Color("ChartSeries")
    static let grid = Color("ChartGrid")
    static let good = Color("StatusGood")
    static let warning = Color("StatusWarning")
    static let critical = Color("StatusCritical")
}

/// A small capsule with a tinted icon and a plain-text label.
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        // A list on iPhone and iPad restyles plain labels in its rows, which stretches the badge.
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .fixedSize()
    }
}

extension BonusStatus {
    var badge: StatusBadge {
        switch self {
        case .noBonus: StatusBadge(text: displayName, systemImage: "minus.circle", tint: .secondary)
        case .inProgress: StatusBadge(text: displayName, systemImage: "circle.dashed", tint: .accentColor)
        case .awaitingPayout: StatusBadge(text: displayName, systemImage: "clock", tint: .accentColor)
        case .received: StatusBadge(text: displayName, systemImage: "checkmark.circle.fill", tint: Palette.good)
        case .forfeited: StatusBadge(text: displayName, systemImage: "xmark.circle", tint: .secondary)
        }
    }
}

extension EligibilityVerdict {
    var badge: StatusBadge {
        switch self {
        case .eligible:
            StatusBadge(text: "Eligible", systemImage: "checkmark.seal.fill", tint: Palette.good)
        case .noRulesEntered:
            StatusBadge(text: "No rules entered", systemImage: "questionmark.circle", tint: .secondary)
        case .needsReview(let count):
            StatusBadge(text: count == 1 ? "Check 1 item" : "Check \(count) items", systemImage: "questionmark.circle.fill", tint: .accentColor)
        case .eligibleOn(let date):
            StatusBadge(text: "Eligible \(DateText.format(date))", systemImage: "calendar.badge.clock", tint: Palette.warning)
        case .closeAccountFirst:
            StatusBadge(text: "Close account first", systemImage: "lock.circle", tint: Palette.warning)
        case .notEligible:
            StatusBadge(text: "Not eligible", systemImage: "xmark.octagon.fill", tint: Palette.critical)
        }
    }

    var systemImage: String {
        switch self {
        case .eligible: "checkmark.seal.fill"
        case .noRulesEntered: "questionmark.circle"
        case .needsReview: "questionmark.circle.fill"
        case .eligibleOn: "calendar.badge.clock"
        case .closeAccountFirst: "lock.circle"
        case .notEligible: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .eligible: Palette.good
        case .noRulesEntered: .secondary
        case .needsReview: .accentColor
        case .eligibleOn, .closeAccountFirst: Palette.warning
        case .notEligible: Palette.critical
        }
    }
}

extension RuleOutcome {
    var systemImage: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle"
        case .blockedUntil: "clock.fill"
        case .blockedUntilClosed: "lock.fill"
        case .blocked: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pass: Palette.good
        case .needsReview: .accentColor
        case .blockedUntil, .blockedUntilClosed: Palette.warning
        case .blocked: Palette.critical
        }
    }
}

extension ActionItem {
    var systemImage: String {
        switch kind {
        case .requirement: urgency == .overdue ? "exclamationmark.triangle.fill" : "checklist"
        case .keepBalance: "lock.fill"
        case .awaitingBonus: "clock"
        case .bonusOverdue: "exclamationmark.triangle.fill"
        case .readyToClose: "door.left.hand.open"
        case .closeLater: "calendar.badge.clock"
        case .offerExpiring: "tag"
        case .avoidFee: "dollarsign.circle"
        }
    }

    var tint: Color {
        switch urgency {
        case .overdue: Palette.critical
        case .dueSoon: Palette.warning
        case .upcoming, .waiting: .accentColor
        case .info: .secondary
        }
    }
}
