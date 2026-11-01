import SwiftUI
import SwiftData
import BankTrackerCore

/// Create or edit an offer. The eligibility check updates live as you fill in the rules.
struct OfferEditorView: View {
    let offer: Offer?
    var onCreate: ((Offer) -> Void)?

    @State private var draft: OfferDraft
    @Query private var accounts: [BankAccount]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @AppStorage(SettingsKey.residenceState) private var residenceState = ""
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    @State private var aiSettings = AISettings()
    @State private var aiSource = ""
    @State private var isFilling = false
    @State private var aiStatus: AIFillStatus?
    /// A bank the AI fill created; removed again if the offer isn't saved with it.
    @State private var aiCreatedBank: Bank?
    @State private var didSave = false
    /// Fields the last AI fill changed, shown with an AI badge.
    @State private var aiFilled: Set<AIField> = []
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    enum AIField: Hashable {
        case bank, product, type, bonus, ends, promo, rules, requirements, payout, closure, fee, openingAndTax, notes
    }

    init(offer: Offer?, presetBank: Bank? = nil, onCreate: ((Offer) -> Void)? = nil) {
        self.offer = offer
        self.onCreate = onCreate
        _draft = State(initialValue: offer.map(OfferDraft.init(offer:)) ?? OfferDraft(bank: presetBank))
    }

    /// Mac and iPad: paste on the left, review on the right. iPhone: one form.
    private var usesTwoPanes: Bool {
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if usesTwoPanes {
                    HStack(spacing: 0) {
                        ScrollView {
                            aiPanel
                                .padding(20)
                        }
                        .frame(width: 360)
                        .background(Theme.ground)
                        Divider()
                        editorForm(includesAI: false)
                    }
                } else {
                    editorForm(includesAI: true)
                }
            }
            .navigationTitle(offer == nil ? "New Offer" : "Edit Offer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave)
                }
            }
            .onChange(of: draft.accountType) { oldType, newType in
                if draft.terms.taxForm == oldType.defaultTaxForm {
                    draft.terms.taxForm = newType.defaultTaxForm
                }
            }
            .onDisappear { discardUnusedBank() }
            #if DEBUG
            .task { await runDebugAutoFill() }
            #endif
        }
        .sheetFrame(width: usesTwoPanes ? 1060 : 640, height: 840)
    }

    // MARK: - Review form

    private func editorForm(includesAI: Bool) -> some View {
        Form {
            if includesAI {
                aiSection
            }

            if draft.bank != nil {
                EligibilitySections(report: liveReport, accountType: draft.accountType, showsHistory: false)
            }

            Section("Offer") {
                BankPickerRow(bank: $draft.bank, isAIFilled: aiFilled.contains(.bank))
                LabeledTextField(title: "Product", text: $draft.productName, prompt: "e.g. Total Checking", isAIFilled: aiFilled.contains(.product))
                Picker(selection: $draft.accountType) {
                    ForEach(AccountType.allCases) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                } label: {
                    FieldLabel("Account type", isAIFilled: aiFilled.contains(.type))
                }
                AmountField(title: "Bonus", value: $draft.terms.bonusAmount, isAIFilled: aiFilled.contains(.bonus))
                LabeledTextField(title: "Offer link", text: $draft.url, prompt: "https://")
                LabeledTextField(title: "Promo code", text: $draft.promoCode, prompt: "Optional", isAIFilled: aiFilled.contains(.promo))
                DatePicker("Found on", selection: $draft.foundDate, displayedComponents: .date)
                OptionalDatePicker(
                    title: "Offer has an end date",
                    dateLabel: "Ends on",
                    date: $draft.expirationDate,
                    defaultDate: Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now,
                    isAIFilled: aiFilled.contains(.ends)
                )
            }

            RulesEditorSection(rules: $draft.rules, accountType: draft.accountType, previous: previousRules, isAIFilled: aiFilled.contains(.rules))
            RequirementsEditorSection(requirements: $draft.terms.requirements, isAIFilled: aiFilled.contains(.requirements))
            PayoutEditorSection(payout: $draft.terms.payout, isAIFilled: aiFilled.contains(.payout))
            EarlyClosureEditorSection(policy: $draft.terms.earlyClosure, hasBonus: true, isAIFilled: aiFilled.contains(.closure))
            FeeEditorSection(fee: $draft.terms.maintenanceFee, isAIFilled: aiFilled.contains(.fee))
            OpeningAndTaxSection(terms: $draft.terms, isAIFilled: aiFilled.contains(.openingAndTax))

            Section {
                TextField("Notes", text: $draft.notes, prompt: Text("Anything else from the terms"), axis: .vertical)
                    .lineLimit(3...10)
                    .labelsHidden()
            } header: {
                FieldLabel("Notes", isAIFilled: aiFilled.contains(.notes))
            }
        }
        .formStyle(.grouped)
        .groundBackground()
    }

    // MARK: - Fill with AI

    /// The left pane on Mac and iPad: paste, fill, and what happened.
    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste the offer")
                    .font(.system(size: 17, weight: .bold))
                Text("A link to the offer page, or the terms themselves. AI reads it and fills in the form.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem = aiSettings.setupProblem {
                Text("To turn on AI filling: \(problem)")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings", systemImage: "gearshape") {
                    dismiss()
                    router.show(.settings)
                }
                .buttonStyle(.bordered)
            } else {
                TextField("Offer terms or link", text: $aiSource, prompt: Text("Paste the offer's terms, or a link to the offer page"), axis: .vertical)
                    .lineLimit(10...18)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    if let provider = aiSettings.provider {
                        Text(provider.shortName)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Theme.hairline, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    if isFilling {
                        ProgressView().controlSize(.small)
                    }
                    Button(isFilling ? "Reading…" : "Fill In with AI", systemImage: "sparkles") {
                        Task { await fillWithAI() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFilling || !canFill)
                }

                if let aiStatus {
                    AIFillStatusView(status: aiStatus)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(statusBackground(aiStatus), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Text("With the box empty, the offer link is used. Only this text is sent to \(aiSettings.provider?.shortName ?? "the AI service"); nothing about your accounts leaves the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
    }

    private func statusBackground(_ status: AIFillStatus) -> Color {
        switch status {
        case .success: Palette.good.opacity(0.12)
        case .failure: Palette.critical.opacity(0.12)
        }
    }

    /// Which parts of the form a fill changed.
    private func changedFields(from before: OfferDraft, to after: OfferDraft) -> Set<AIField> {
        var fields: Set<AIField> = []
        if before.bank !== after.bank { fields.insert(.bank) }
        if before.productName != after.productName { fields.insert(.product) }
        if before.accountType != after.accountType { fields.insert(.type) }
        if before.terms.bonusAmount != after.terms.bonusAmount { fields.insert(.bonus) }
        if before.expirationDate != after.expirationDate { fields.insert(.ends) }
        if before.promoCode != after.promoCode { fields.insert(.promo) }
        if before.rules != after.rules { fields.insert(.rules) }
        if before.terms.requirements != after.terms.requirements { fields.insert(.requirements) }
        if before.terms.payout != after.terms.payout { fields.insert(.payout) }
        if before.terms.earlyClosure != after.terms.earlyClosure { fields.insert(.closure) }
        if before.terms.maintenanceFee != after.terms.maintenanceFee { fields.insert(.fee) }
        if before.terms.taxForm != after.terms.taxForm || before.terms.minimumOpeningDeposit != after.terms.minimumOpeningDeposit {
            fields.insert(.openingAndTax)
        }
        if before.notes != after.notes { fields.insert(.notes) }
        return fields
    }

    @ViewBuilder
    private var aiSection: some View {
        Section {
            if let problem = aiSettings.setupProblem {
                Text("Paste an offer's terms or link, and AI fills in this form. To turn it on: \(problem)")
                    .foregroundStyle(.secondary)
                Button("Open Settings", systemImage: "gearshape") {
                    dismiss()
                    router.show(.settings)
                }
            } else {
                TextField("Offer terms or link", text: $aiSource, prompt: Text("Paste the offer's terms, or a link to the offer page"), axis: .vertical)
                    .lineLimit(3...8)
                    .labelsHidden()
                HStack {
                    Button(isFilling ? "Reading the Offer…" : "Fill In with AI", systemImage: "sparkles") {
                        Task { await fillWithAI() }
                    }
                    .disabled(isFilling || !canFill)
                    if isFilling {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if let provider = aiSettings.provider {
                        Text("Uses \(provider.shortName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let aiStatus {
                    AIFillStatusView(status: aiStatus)
                }
            }
        } header: {
            Text("Fill in with AI")
        } footer: {
            if aiSettings.setupProblem == nil {
                Text("With the box empty, the offer link below is used. AI can misread terms, so check every field before saving.")
            }
        }
    }

    private var canFill: Bool {
        !aiSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Self.link(in: draft.url) != nil
    }

    private func fillWithAI() async {
        guard let configuration = aiSettings.makeConfiguration() else { return }
        let extractor = OfferExtractor(configuration: configuration)
        let providerName = configuration.provider.shortName
        isFilling = true
        aiStatus = nil
        defer { isFilling = false }

        do {
            let source = aiSource.trimmingCharacters(in: .whitespacesAndNewlines)
            var offerText = source
            if let url = Self.link(in: source) ?? (source.isEmpty ? Self.link(in: draft.url) : nil) {
                offerText = try await extractor.fetchPageText(from: url)
                if draft.url.trimmingCharacters(in: .whitespaces).isEmpty {
                    draft.url = url.absoluteString
                }
            }
            let extraction = try await extractor.extract(fromOfferText: offerText)

            let before = draft
            var filled: [String] = []
            if let name = extraction.bankName, let bank = bank(named: name) {
                draft.bank = bank
                filled.append(bank === aiCreatedBank ? "bank (new: \(bank.name))" : "bank")
            }
            filled += draft.merge(extraction)
            aiFilled = changedFields(from: before, to: draft)
            aiStatus = filled.isEmpty
                ? .failure("\(providerName) didn't find offer details in that text.")
                : .success("Filled in by \(providerName): \(filled.joined(separator: ", ")). Check everything before saving.")
        } catch {
            aiStatus = .failure(error.localizedDescription)
        }
    }

    /// An existing bank whose name matches, or a new one (removed later if unused).
    private func bank(named name: String) -> Bank? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = banks.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame })
            ?? banks.first(where: { !$0.name.isEmpty && (trimmed.localizedCaseInsensitiveContains($0.name) || $0.name.localizedCaseInsensitiveContains(trimmed)) }) {
            return existing
        }
        if let created = aiCreatedBank {
            created.name = trimmed
            return created
        }
        let created = Bank(name: trimmed)
        context.insert(created)
        aiCreatedBank = created
        return created
    }

    private func discardUnusedBank() {
        guard let bank = aiCreatedBank, !(didSave && bank === draft.bank),
              bank.offerList.isEmpty, bank.accountList.isEmpty
        else { return }
        context.delete(bank)
        aiCreatedBank = nil
    }

    /// A single http(s) address, or nil for anything else.
    private static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return url
    }

    #if DEBUG
    /// `--ai-fill-source <text or link>` fills a new offer as soon as the editor opens.
    private func runDebugAutoFill() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard offer == nil, let index = arguments.firstIndex(of: "--ai-fill-source"), arguments.indices.contains(index + 1) else { return }
        aiSource = arguments[index + 1]
        await fillWithAI()
        print("AI-FILL: status=\(aiStatus.map { String(describing: $0) } ?? "none")")
        print("AI-FILL: bank=\(draft.bank?.name ?? "-") product=\(draft.productName) type=\(draft.accountType.rawValue) bonus=\(draft.terms.bonusAmount) ends=\(draft.expirationDate.map(DateText.format) ?? "-") url=\(draft.url)")
        print("AI-FILL: requirements=\(draft.terms.requirements.map(\.summary))")
        print("AI-FILL: rules=\(draft.rules.map { $0.summary(for: draft.accountType) })")
        print("AI-FILL: payout=\(draft.terms.payout.summary) | closure=\(draft.terms.earlyClosure.summary) | fee=\(draft.terms.maintenanceFee.summary)")
        fflush(stdout)
    }
    #endif

    private var liveReport: EligibilityReport {
        let excluded = Set(offer?.linkedAccounts.map(\.uuid) ?? [])
        return EligibilityEngine(residenceState: residenceState.isEmpty ? nil : residenceState).evaluate(
            rules: draft.rules,
            bankID: draft.bank?.uuid,
            accountType: draft.accountType,
            offerExpiration: draft.expirationDate,
            history: accounts.map(\.snapshot),
            excluding: excluded
        )
    }

    /// The newest other offer at the same bank that has rules, so they can be reused.
    private var previousRules: (label: String, rules: [EligibilityRule])? {
        guard let bank = draft.bank else { return nil }
        let candidate = bank.offerList
            .filter { $0 !== offer && !$0.eligibilityRules.isEmpty }
            .max { $0.foundDate < $1.foundDate }
        guard let candidate else { return nil }
        return ("\(candidate.productLabel) (\(DateText.format(candidate.foundDate)))", candidate.eligibilityRules)
    }

    private func save() {
        let target: Offer
        if let offer {
            target = offer
        } else {
            target = Offer()
            context.insert(target)
        }
        draft.apply(to: target)
        didSave = true
        try? context.save()
        dismiss()
        if offer == nil { onCreate?(target) }
    }
}
