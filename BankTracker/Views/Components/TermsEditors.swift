import SwiftUI
import BankTrackerCore

// Form sections for editing offer terms. Both the offer editor and the account editor
// use them. List items are addressed by id rather than index, so removing one while
// its row is on screen is safe.

struct RequirementsEditorSection: View {
    @Binding var requirements: [BonusRequirement]
    var isAIFilled = false
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Section {
            if requirements.isEmpty {
                Text("No requirements yet. Add what the offer asks you to do.")
                    .foregroundStyle(.secondary)
            }
            ForEach(requirements) { requirement in
                DisclosureGroup(isExpanded: expansion(for: requirement.id)) {
                    RequirementFields(requirement: binding(for: requirement.id))
                    Button("Remove Requirement", role: .destructive) {
                        requirements.removeAll { $0.id == requirement.id }
                    }
                } label: {
                    Label(requirement.summary, systemImage: requirement.kind.systemImage)
                }
            }
            Menu("Add Requirement") {
                ForEach(BonusRequirement.Kind.allCases) { kind in
                    Button(kind.displayName) {
                        let requirement = BonusRequirement.template(kind)
                        requirements.append(requirement)
                        expanded.insert(requirement.id)
                    }
                }
            }
        } header: {
            FieldLabel("What you need to do", isAIFilled: isAIFilled)
        } footer: {
            Text("Deadlines count from the day the account opens.")
        }
    }

    private func binding(for id: UUID) -> Binding<BonusRequirement> {
        Binding(
            get: { requirements.first { $0.id == id } ?? BonusRequirement(id: id) },
            set: { newValue in
                guard let index = requirements.firstIndex(where: { $0.id == id }) else { return }
                requirements[index] = newValue
            }
        )
    }

    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

private struct RequirementFields: View {
    @Binding var requirement: BonusRequirement

    var body: some View {
        Picker("Type", selection: $requirement.kind) {
            ForEach(BonusRequirement.Kind.allCases) { kind in
                Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
            }
        }
        if requirement.kind.usesAmount {
            AmountField(title: amountTitle, value: $requirement.amount)
        }
        if requirement.kind.usesCount {
            NumberField(title: "Number of transactions", value: $requirement.count)
        }
        TimeSpanField(title: windowTitle, span: $requirement.window)
        if requirement.kind == .deposit {
            Toggle("The money must stay in the account", isOn: $requirement.keepsDeposit)
        }
        if requirement.hasHold {
            TimeSpanField(title: "Keep it for", span: $requirement.holdPeriod)
            Picker("Hold starts", selection: $requirement.holdStart) {
                ForEach(BonusRequirement.HoldStart.allCases) { start in
                    Text(start == .afterFunding && requirement.kind == .deposit ? "After you deposit it" : start.displayName).tag(start)
                }
            }
        }
        TextField(
            "Details",
            text: $requirement.details,
            prompt: Text(requirement.kind == .other ? "Describe the requirement" : "Fine print, e.g. what counts as a direct deposit"),
            axis: .vertical
        )
    }

    private var windowTitle: String {
        switch requirement.kind {
        case .maintainBalance: "Fund within"
        case .deposit: "Deposit within"
        default: "Complete within"
        }
    }

    private var amountTitle: String {
        switch requirement.kind {
        case .directDeposit: "Total direct deposits"
        case .deposit: "Deposit amount"
        case .maintainBalance: "Balance to keep"
        case .debitPurchases, .billPay: "Total amount (optional)"
        case .other: "Amount"
        }
    }
}

struct PayoutEditorSection: View {
    @Binding var payout: PayoutTiming
    var isAIFilled = false

    var body: some View {
        Section {
            Picker("Paid", selection: $payout.basis) {
                ForEach(PayoutTiming.Basis.allCases) { basis in
                    Text(basis.displayName).tag(basis)
                }
            }
            TimeSpanField(title: "Within", span: $payout.span)
        } header: {
            FieldLabel("Bonus payout", isAIFilled: isAIFilled)
        } footer: {
            Text(payout.summary + ".")
        }
    }
}

struct EarlyClosureEditorSection: View {
    @Binding var policy: EarlyClosurePolicy
    let hasBonus: Bool
    var isAIFilled = false

    var body: some View {
        Section {
            TimeSpanField(title: "Keep open at least", span: $policy.minimumOpen)
            if !policy.minimumOpen.isZero {
                Picker("Counted", selection: $policy.basis) {
                    ForEach(EarlyClosurePolicy.Basis.allCases) { basis in
                        Text(basis.displayName).tag(basis)
                    }
                }
                AmountField(title: "Early closure fee", value: $policy.fee)
                if hasBonus {
                    Toggle("Bonus is taken back if closed early", isOn: $policy.bonusClawback)
                }
            }
        } header: {
            FieldLabel("Early closure", isAIFilled: isAIFilled)
        } footer: {
            Text("Use 0 if there's no minimum. " + policy.summary + ".")
        }
    }
}

struct FeeEditorSection: View {
    @Binding var fee: MaintenanceFee
    var isAIFilled = false
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Section {
            AmountField(title: "Monthly fee", value: $fee.monthlyFee)
            if fee.hasFee {
                ForEach(fee.waivers) { waiver in
                    DisclosureGroup(isExpanded: expansion(for: waiver.id)) {
                        WaiverFields(waiver: binding(for: waiver.id))
                        Button("Remove Option", role: .destructive) {
                            fee.waivers.removeAll { $0.id == waiver.id }
                        }
                    } label: {
                        Label(waiver.summary, systemImage: waiver.isMyPlan ? "star.fill" : "circle")
                    }
                }
                Menu("Add a Way to Avoid the Fee") {
                    ForEach(FeeWaiver.Kind.allCases) { kind in
                        Button(kind.displayName) {
                            var waiver = FeeWaiver.template(kind)
                            waiver.isMyPlan = fee.waivers.isEmpty
                            fee.waivers.append(waiver)
                            expanded.insert(waiver.id)
                        }
                    }
                }
                TextField("Fee notes", text: $fee.notes, prompt: Text("Other fees, e.g. paper statements"), axis: .vertical)
            }
        } header: {
            FieldLabel("Monthly fee", isAIFilled: isAIFilled)
        } footer: {
            Text(fee.hasFee ? "List every way to avoid the fee and star the one you'll use." : "Leave at 0 if the account has no monthly fee.")
        }
    }

    private func binding(for id: UUID) -> Binding<FeeWaiver> {
        Binding(
            get: { fee.waivers.first { $0.id == id } ?? FeeWaiver(id: id) },
            set: { newValue in
                guard let index = fee.waivers.firstIndex(where: { $0.id == id }) else { return }
                // Only one waiver can be the plan.
                if newValue.isMyPlan, !fee.waivers[index].isMyPlan {
                    for other in fee.waivers.indices { fee.waivers[other].isMyPlan = false }
                }
                fee.waivers[index] = newValue
            }
        )
    }

    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

private struct WaiverFields: View {
    @Binding var waiver: FeeWaiver

    var body: some View {
        Picker("Waiver", selection: $waiver.kind) {
            ForEach(FeeWaiver.Kind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        if waiver.kind.usesAmount {
            AmountField(title: "Amount", value: $waiver.amount)
        }
        if waiver.kind.usesCount {
            NumberField(title: "Purchases per statement", value: $waiver.count)
        }
        TextField("Details", text: $waiver.details, prompt: Text(waiver.kind == .other ? "Describe the waiver" : "Optional"), axis: .vertical)
        Toggle("This is my plan", isOn: $waiver.isMyPlan)
    }
}

struct OpeningAndTaxSection: View {
    @Binding var terms: OfferTerms
    var isAIFilled = false

    var body: some View {
        Section {
            AmountField(title: "Minimum opening deposit", value: $terms.minimumOpeningDeposit)
            Picker("Tax form", selection: $terms.taxForm) {
                ForEach(TaxFormType.allCases) { form in
                    Text(form.displayName).tag(form)
                }
            }
        } header: {
            FieldLabel("Opening and taxes", isAIFilled: isAIFilled)
        } footer: {
            Text(terms.taxForm.explanation)
        }
    }
}

struct RulesEditorSection: View {
    @Binding var rules: [EligibilityRule]
    let accountType: AccountType
    /// Rules from an earlier offer at the same bank, offered as a starting point.
    var previous: (label: String, rules: [EligibilityRule])?
    var isAIFilled = false
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Section {
            if rules.isEmpty {
                Text("No restrictions entered.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rules) { rule in
                DisclosureGroup(isExpanded: expansion(for: rule.id)) {
                    RuleFields(rule: binding(for: rule.id), accountType: accountType)
                    Button("Remove Rule", role: .destructive) {
                        rules.removeAll { $0.id == rule.id }
                    }
                } label: {
                    Label(rule.summary(for: accountType), systemImage: "checkmark.shield")
                }
            }
            Menu("Add Rule") {
                ForEach(EligibilityRule.Kind.allCases) { kind in
                    Button(kind.displayName) {
                        let rule = EligibilityRule.template(kind)
                        rules.append(rule)
                        expanded.insert(rule.id)
                    }
                }
            }
            if let previous, !previous.rules.isEmpty {
                Button("Copy Rules from \(previous.label)") {
                    rules = previous.rules.map { rule in
                        var copy = rule
                        copy.id = UUID()
                        copy.isConfirmed = false
                        return copy
                    }
                }
            }
        } header: {
            FieldLabel("Eligibility rules", isAIFilled: isAIFilled)
        } footer: {
            Text("Enter the restrictions from the offer's fine print. They're checked against every account you've recorded at this bank.")
        }
    }

    private func binding(for id: UUID) -> Binding<EligibilityRule> {
        Binding(
            get: { rules.first { $0.id == id } ?? EligibilityRule(id: id) },
            set: { newValue in
                guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
                rules[index] = newValue
            }
        )
    }

    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

private struct RuleFields: View {
    @Binding var rule: EligibilityRule
    let accountType: AccountType
    @State private var statesText = ""

    var body: some View {
        Picker("Rule", selection: $rule.kind) {
            ForEach(EligibilityRule.Kind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        if rule.kind.usesScope {
            Picker("Applies to", selection: $rule.scope) {
                ForEach(EligibilityRule.Scope.allCases) { scope in
                    Text(scope.displayName(for: accountType)).tag(scope)
                }
            }
        }
        if rule.kind.usesSpan {
            TimeSpanField(title: rule.kind == .oneAccountPer ? "Period" : "Looking back", span: $rule.span)
        }
        if rule.kind.usesMeasuredFrom {
            Picker("Counted from", selection: $rule.measuredFrom) {
                ForEach(EligibilityRule.BonusDateBasis.allCases) { basis in
                    Text(basis.displayName).tag(basis)
                }
            }
        }
        if rule.kind == .stateRestriction {
            LabeledTextField(title: "Eligible states", text: $statesText, prompt: "e.g. NY, NJ, CT")
                .onAppear { statesText = rule.states.joined(separator: ", ") }
                .onChange(of: statesText) { _, text in
                    rule.states = USState.parseCodes(text).valid
                }
            let invalid = USState.parseCodes(statesText).invalid
            if !invalid.isEmpty {
                Text("Not recognized: \(invalid.joined(separator: ", ")). Use two-letter codes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if rule.kind == .manual {
            TextField("What to check", text: $rule.note, prompt: Text("e.g. No accounts closed with a negative balance"), axis: .vertical)
            Toggle("I've confirmed I meet this", isOn: $rule.isConfirmed)
        }
    }
}

/// Read-only list of what an offer asks you to do.
struct RequirementsSummaryCard: View {
    let terms: OfferTerms

    var body: some View {
        CardSection("What you need to do") {
            if terms.requirements.isEmpty {
                Text("No requirements recorded.")
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
            ForEach(terms.requirements) { requirement in
                HStack(alignment: .top, spacing: 12) {
                    IconTile(systemImage: requirement.kind.systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(requirement.summary)
                            .font(.system(size: 13.5, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if !requirement.details.isEmpty {
                            Text(requirement.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 5)
                }
                .cardRow(vertical: 12)
            }
        }
    }
}

/// Read-only payout, closing, fee and tax terms of an offer.
struct TermsSummaryCard: View {
    let terms: OfferTerms

    var body: some View {
        CardSection("Payout, closing and fees") {
            SummaryLine(title: "Payout", value: terms.payout.summary)
            SummaryLine(title: "Early closure", value: terms.earlyClosure.summary)
            SummaryLine(title: "Monthly fee", value: terms.maintenanceFee.summary)
            if terms.minimumOpeningDeposit > 0 {
                SummaryLine(title: "Opening deposit", value: Money.format(terms.minimumOpeningDeposit))
            }
            SummaryLine(title: "Tax form", value: terms.taxForm.displayName)
        }
    }
}
