import SwiftUI
import SwiftData
import BankTrackerCore

/// Create or edit an account. When opened from an offer, the offer's terms are prefilled.
struct AccountEditorView: View {
    let account: BankAccount?
    var onCreate: ((BankAccount) -> Void)?

    @State private var draft: AccountDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(account: BankAccount?, draft: AccountDraft? = nil, onCreate: ((BankAccount) -> Void)? = nil) {
        self.account = account
        self.onCreate = onCreate
        _draft = State(initialValue: draft ?? account.map(AccountDraft.init(account:)) ?? AccountDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                if let offer = draft.sourceOffer, account == nil {
                    Section {
                        Label("Terms are copied from the \(offer.title) offer. Adjust anything that's different for your account.", systemImage: "doc.on.doc")
                    }
                }

                Section("Account") {
                    BankPickerRow(bank: $draft.bank)
                    LabeledTextField(title: "Product", text: $draft.productName, prompt: "e.g. Total Checking")
                    Picker("Account type", selection: $draft.accountType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    LabeledTextField(title: "Last 4 digits", text: $draft.last4, prompt: "Optional")
                    DatePicker("Opened on", selection: $draft.openedDate, displayedComponents: .date)
                    OptionalDatePicker(title: "Account is closed", dateLabel: "Closed on", date: $draft.closedDate)
                    Picker("Credit check", selection: $draft.inquiry) {
                        ForEach(InquiryType.allCases) { inquiry in
                            Text(inquiry.displayName).tag(inquiry)
                        }
                    }
                }

                Section {
                    Toggle("Opened for a bonus", isOn: $draft.hasBonus)
                    if draft.hasBonus {
                        AmountField(title: "Bonus amount", value: $draft.terms.bonusAmount)
                        OptionalDatePicker(title: "Bonus received", dateLabel: "Received on", date: $draft.bonusReceivedDate)
                        if draft.bonusReceivedDate != nil {
                            AmountField(title: "Amount received", value: $draft.bonusReceivedAmount)
                        } else {
                            Toggle("Bonus forfeited", isOn: $draft.bonusForfeited)
                        }
                    }
                } header: {
                    Text("Bonus")
                }

                if draft.hasBonus {
                    RequirementsEditorSection(requirements: $draft.terms.requirements)
                    PayoutEditorSection(payout: $draft.terms.payout)
                }
                EarlyClosureEditorSection(policy: $draft.terms.earlyClosure, hasBonus: draft.hasBonus)
                FeeEditorSection(fee: $draft.terms.maintenanceFee)

                Section {
                    AmountField(title: "Current balance", value: $draft.currentBalance)
                    AmountField(title: "Fees paid so far", value: $draft.feesPaid)
                    if draft.hasBonus {
                        Picker("Tax form", selection: $draft.terms.taxForm) {
                            ForEach(TaxFormType.allCases) { form in
                                Text(form.displayName).tag(form)
                            }
                        }
                    }
                    Toggle("Keeper (I plan to keep this account)", isOn: $draft.isKeeper)
                } header: {
                    Text("Money")
                } footer: {
                    Text("The balance feeds the \"funds parked\" statistic. Keepers don't get close reminders.")
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, prompt: Text("Anything worth remembering"), axis: .vertical)
                        .lineLimit(3...10)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .groundBackground()
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave)
                }
            }
            .onChange(of: draft.bonusReceivedDate) { oldDate, newDate in
                if oldDate == nil, newDate != nil, draft.bonusReceivedAmount == 0 {
                    draft.bonusReceivedAmount = draft.terms.bonusAmount
                }
            }
            .onChange(of: draft.accountType) { oldType, newType in
                if draft.terms.taxForm == oldType.defaultTaxForm {
                    draft.terms.taxForm = newType.defaultTaxForm
                }
            }
        }
        .sheetFrame(width: 640, height: 820)
    }

    private func save() {
        let target: BankAccount
        if let account {
            target = account
        } else {
            target = BankAccount()
            context.insert(target)
        }
        draft.apply(to: target)
        if account == nil, let offer = draft.sourceOffer {
            offer.status = .opened
        }
        try? context.save()
        dismiss()
        if account == nil { onCreate?(target) }
    }
}
