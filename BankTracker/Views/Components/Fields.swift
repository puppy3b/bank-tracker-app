import SwiftUI
import SwiftData
import BankTrackerCore

// These fields update their binding on every keystroke, so pressing Save never
// loses an edit that hasn't been "committed" by pressing Return.

/// A labeled dollar amount.
struct AmountField: View {
    let title: String
    @Binding var value: Decimal
    var isAIFilled = false
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 2) {
                Text("$").foregroundStyle(.secondary)
                TextField(title, text: $text, prompt: Text("0"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .decimalKeyboard()
                    .frame(minWidth: 70, maxWidth: 140)
            }
        } label: {
            FieldLabel(title, isAIFilled: isAIFilled)
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, newText in
            let parsed = Self.parse(newText)
            if parsed != value { value = parsed }
        }
        .onChange(of: value) { _, newValue in
            if !isFocused, Self.parse(text) != newValue { text = Self.format(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { text = Self.format(value) }
        }
    }

    static func parse(_ text: String) -> Decimal {
        let cleaned = text.filter { $0.isNumber || $0 == "." }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US")) ?? 0
    }

    static func format(_ value: Decimal) -> String {
        guard value != 0 else { return "" }
        return value.formatted(
            .number
                .precision(.fractionLength(value.isWholeNumber ? 0 : 2))
                .locale(Locale(identifier: "en_US"))
        )
    }
}

/// A labeled whole number.
struct NumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            IntegerTextField(value: $value)
        }
    }
}

/// An unlabeled whole-number text field.
struct IntegerTextField: View {
    @Binding var value: Int
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Number", text: $text, prompt: Text("0"))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .numberKeyboard()
            .frame(minWidth: 44, maxWidth: 70)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Int(newText.filter(\.isNumber)) ?? 0
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused, (Int(text.filter(\.isNumber)) ?? 0) != newValue { text = Self.format(newValue) }
            }
    }

    static func format(_ value: Int) -> String { value == 0 ? "" : String(value) }
}

/// "90 [days ▾]"
struct TimeSpanField: View {
    let title: String
    @Binding var span: TimeSpan

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                IntegerTextField(value: $span.value)
                Picker(title, selection: $span.unit) {
                    ForEach(TimeSpan.Unit.allCases) { unit in
                        Text(unit.label(for: span.value)).tag(unit)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

/// A single-line text field with its label on the leading side on every platform.
struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var isAIFilled = false

    var body: some View {
        LabeledContent {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        } label: {
            FieldLabel(title, isAIFilled: isAIFilled)
        }
    }
}

/// A toggle that reveals a date picker; off means no date.
struct OptionalDatePicker: View {
    let title: String
    let dateLabel: String
    @Binding var date: Date?
    var defaultDate: Date = .now
    var isAIFilled = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { date != nil },
            set: { isOn in date = isOn ? (date ?? defaultDate) : nil }
        )) {
            FieldLabel(title, isAIFilled: isAIFilled)
        }
        if date != nil {
            DatePicker(
                dateLabel,
                selection: Binding(get: { date ?? defaultDate }, set: { date = $0 }),
                displayedComponents: .date
            )
        }
    }
}

/// Bank picker with a button for adding a bank on the spot.
struct BankPickerRow: View {
    @Binding var bank: Bank?
    var isAIFilled = false
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Environment(\.modelContext) private var context
    @State private var showingNewBank = false
    @State private var newBankName = ""

    var body: some View {
        HStack {
            Picker(selection: $bank) {
                Text("Choose a bank").tag(nil as Bank?)
                ForEach(banks) { bank in
                    Text(bank.name).tag(bank as Bank?)
                }
            } label: {
                FieldLabel("Bank", isAIFilled: isAIFilled)
            }
            Button("New Bank…") {
                newBankName = ""
                showingNewBank = true
            }
        }
        .alert("New Bank", isPresented: $showingNewBank) {
            TextField("Bank name", text: $newBankName)
            Button("Add") { addBank() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the bank, credit union or brokerage name.")
        }
    }

    private func addBank() {
        let name = newBankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = banks.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            bank = existing
            return
        }
        let newBank = Bank(name: name)
        context.insert(newBank)
        bank = newBank
    }
}

/// A date with a relative hint underneath ("in 12 days").
struct DateRow: View {
    let title: String
    let date: Date

    init(_ title: String, _ date: Date) {
        self.title = title
        self.date = date
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(DateText.format(date))
                Text(RelativeDay.text(for: date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    func decimalKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.decimalPad)
        #else
        return self
        #endif
    }

    func numberKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.numberPad)
        #else
        return self
        #endif
    }

    /// Sheet sizing on macOS; iPhone and iPad size sheets themselves.
    func sheetFrame(width: CGFloat = 600, height: CGFloat = 720) -> some View {
        #if os(macOS)
        return frame(minWidth: width, idealWidth: width, minHeight: min(height, 420), idealHeight: height)
        #else
        return self
        #endif
    }
}
