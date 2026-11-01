import Foundation

/// Offer details as an AI service reports them. Every field is optional and decoded
/// leniently, since models sometimes send "$300" for 300 or "Checking" for "checking".
/// The accessors below turn the raw values into the app's own types.
public struct OfferExtraction: Decodable, Sendable, Equatable {
    public struct Span: Decodable, Sendable, Equatable {
        public var value: Int?
        public var unit: String?

        public init(value: Int?, unit: String?) {
            self.value = value
            self.unit = unit
        }

        public var timeSpan: TimeSpan? {
            guard let value, value > 0 else { return nil }
            switch normalizedKey(unit ?? "days") {
            case "week", "weeks": return .days(value * 7)
            case "month", "months": return .months(value)
            case "year", "years": return .years(value)
            default: return .days(value)
            }
        }
    }

    public struct Requirement: Decodable, Sendable, Equatable {
        public var kind: String?
        public var amount: Decimal?
        public var count: Int?
        public var within: Span?
        public var holdFor: Span?
        public var holdStart: String?
        public var details: String?
    }

    public struct Waiver: Decodable, Sendable, Equatable {
        public var kind: String?
        public var amount: Decimal?
        public var count: Int?
        public var details: String?
    }

    public struct Rule: Decodable, Sendable, Equatable {
        public var kind: String?
        public var scope: String?
        public var lookback: Span?
        public var measuredFrom: String?
        public var states: [String]?
        public var note: String?
    }

    public var bankName: String?
    public var productName: String?
    public var accountType: String?
    public var bonusAmount: Decimal?
    /// YYYY-MM-DD
    public var expirationDate: String?
    public var promoCode: String?
    public var minimumOpeningDeposit: Decimal?
    public var requirements: [Requirement]?
    public var payoutBasis: String?
    public var payoutWithin: Span?
    public var minimumOpen: Span?
    public var minimumOpenBasis: String?
    public var earlyClosureFee: Decimal?
    public var bonusClawback: Bool?
    public var monthlyFee: Decimal?
    public var feeWaivers: [Waiver]?
    public var feeNotes: String?
    public var taxForm: String?
    public var eligibilityRules: [Rule]?
    public var notes: String?

    // MARK: - Converted values

    public var accountTypeValue: AccountType? {
        match(accountType, synonyms: [
            "investment": .brokerage, "brokerageaccount": .brokerage,
            "moneymarketaccount": .moneyMarket, "mma": .moneyMarket,
            "certificateofdeposit": .cd,
            "checkingaccount": .checking, "savingsaccount": .savings,
        ])
    }

    public func expirationDateValue(calendar: Calendar = .current) -> Date? {
        guard let parts = expirationDate?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public var requirementValues: [BonusRequirement] {
        (requirements ?? []).map { item in
            let kind = match(item.kind, synonyms: [
                "dd": .directDeposit, "directdeposits": .directDeposit,
                "newmoney": .deposit, "fund": .deposit, "funding": .deposit,
                "balance": .maintainBalance, "keepbalance": .maintainBalance, "holdbalance": .maintainBalance,
                "debitcard": .debitPurchases, "debitcardpurchases": .debitPurchases, "debittransactions": .debitPurchases,
                "billpayment": .billPay, "billpayments": .billPay,
            ]) ?? BonusRequirement.Kind.other
            var requirement = BonusRequirement.template(kind)
            requirement.amount = item.amount ?? 0
            requirement.count = item.count ?? 0
            requirement.window = item.within?.timeSpan ?? .days(0)
            if let hold = item.holdFor?.timeSpan, !hold.isZero {
                requirement.holdPeriod = hold
                requirement.keepsDeposit = kind == .deposit
            }
            requirement.holdStart = match(item.holdStart) ?? .afterFunding
            requirement.details = item.details ?? ""
            return requirement
        }
    }

    public var payoutValue: PayoutTiming? {
        guard payoutBasis != nil || payoutWithin != nil else { return nil }
        let defaults = PayoutTiming()
        return PayoutTiming(
            basis: match(payoutBasis) ?? defaults.basis,
            span: payoutWithin?.timeSpan ?? defaults.span
        )
    }

    public var earlyClosureValue: EarlyClosurePolicy? {
        guard minimumOpen != nil || earlyClosureFee != nil || bonusClawback != nil else { return nil }
        return EarlyClosurePolicy(
            minimumOpen: minimumOpen?.timeSpan ?? .days(0),
            basis: match(minimumOpenBasis) ?? .fromOpening,
            fee: earlyClosureFee ?? 0,
            bonusClawback: bonusClawback ?? false
        )
    }

    public var maintenanceFeeValue: MaintenanceFee? {
        let waivers = (feeWaivers ?? []).map { item in
            FeeWaiver(
                kind: match(item.kind, synonyms: [
                    "dailybalance": .minimumDailyBalance, "minimumbalance": .minimumDailyBalance,
                    "averagedailybalance": .averageBalance, "averagemonthlybalance": .averageBalance,
                    "dd": .directDeposit, "monthlydirectdeposit": .directDeposit,
                    "debitcardpurchases": .debitPurchases, "age": .ageOrStudent, "student": .ageOrStudent,
                ]) ?? .other,
                amount: item.amount ?? 0,
                count: item.count ?? 0,
                details: item.details ?? ""
            )
        }
        guard monthlyFee != nil || !waivers.isEmpty else { return nil }
        return MaintenanceFee(monthlyFee: monthlyFee ?? 0, waivers: waivers, notes: feeNotes ?? "")
    }

    public var taxFormValue: TaxFormType? {
        match(taxForm, synonyms: [
            "1099int": .form1099INT, "int": .form1099INT,
            "1099misc": .form1099MISC, "misc": .form1099MISC,
            "1099": .consolidated1099, "consolidated": .consolidated1099, "composite1099": .consolidated1099,
            "none": .noForm,
        ])
    }

    public var ruleValues: [EligibilityRule] {
        (eligibilityRules ?? []).map { item in
            let kind = match(item.kind, synonyms: [
                "existingcustomer": .notCurrentCustomer, "currentcustomer": .notCurrentCustomer,
                "newcustomersonly": .neverHadAccount, "lifetime": .oncePerLifetime,
                "state": .stateRestriction, "states": .stateRestriction, "other": .manual,
            ]) ?? EligibilityRule.Kind.manual
            var rule = EligibilityRule.template(kind)
            rule.scope = match(item.scope, synonyms: ["any": .anyAccount, "same": .sameAccountType]) ?? .sameAccountType
            if let span = item.lookback?.timeSpan { rule.span = span }
            rule.measuredFrom = match(item.measuredFrom, synonyms: [
                "opening": .accountOpenDate, "opendate": .accountOpenDate, "enrollment": .accountOpenDate,
                "payout": .bonusPaidDate, "bonusdate": .bonusPaidDate,
            ]) ?? .bonusPaidDate
            rule.states = USState.parseCodes((item.states ?? []).joined(separator: " ")).valid
            rule.note = item.note ?? ""
            if kind == .manual, rule.note.isEmpty { rule.note = item.kind ?? "Check the offer terms" }
            return rule
        }
    }

    /// Copies everything found into `terms`, leaving the rest alone.
    /// Returns short descriptions of what was filled, for a status message.
    @discardableResult
    public func apply(to terms: inout OfferTerms) -> [String] {
        var filled: [String] = []
        if let bonusAmount {
            terms.bonusAmount = bonusAmount
            filled.append("\(Money.format(bonusAmount)) bonus")
        }
        let requirements = requirementValues
        if !requirements.isEmpty {
            terms.requirements = requirements
            filled.append(requirements.count == 1 ? "1 requirement" : "\(requirements.count) requirements")
        }
        if let payoutValue {
            terms.payout = payoutValue
            filled.append("payout timing")
        }
        if let earlyClosureValue {
            terms.earlyClosure = earlyClosureValue
            filled.append("early closure terms")
        }
        if let maintenanceFeeValue {
            terms.maintenanceFee = maintenanceFeeValue
            filled.append("monthly fee")
        }
        if let minimumOpeningDeposit {
            terms.minimumOpeningDeposit = minimumOpeningDeposit
            filled.append("opening deposit")
        }
        if let taxFormValue {
            terms.taxForm = taxFormValue
            filled.append("tax form")
        }
        return filled
    }

    // MARK: - Lenient decoding

    private enum CodingKeys: String, CodingKey {
        case bankName, productName, accountType, bonusAmount, expirationDate, promoCode, minimumOpeningDeposit
        case requirements, payoutBasis, payoutWithin, minimumOpen, minimumOpenBasis, earlyClosureFee, bonusClawback
        case monthlyFee, feeWaivers, feeNotes, taxForm, eligibilityRules, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bankName = container.lenientString(.bankName)
        productName = container.lenientString(.productName)
        accountType = container.lenientString(.accountType)
        bonusAmount = container.lenientDecimal(.bonusAmount)
        expirationDate = container.lenientString(.expirationDate)
        promoCode = container.lenientString(.promoCode)
        minimumOpeningDeposit = container.lenientDecimal(.minimumOpeningDeposit)
        requirements = container.lossyArray(.requirements)
        payoutBasis = container.lenientString(.payoutBasis)
        payoutWithin = try? container.decodeIfPresent(Span.self, forKey: .payoutWithin)
        minimumOpen = try? container.decodeIfPresent(Span.self, forKey: .minimumOpen)
        minimumOpenBasis = container.lenientString(.minimumOpenBasis)
        earlyClosureFee = container.lenientDecimal(.earlyClosureFee)
        bonusClawback = container.lenientBool(.bonusClawback)
        monthlyFee = container.lenientDecimal(.monthlyFee)
        feeWaivers = container.lossyArray(.feeWaivers)
        feeNotes = container.lenientString(.feeNotes)
        taxForm = container.lenientString(.taxForm)
        eligibilityRules = container.lossyArray(.eligibilityRules)
        notes = container.lenientString(.notes)
    }

    public init() {}
}

extension OfferExtraction.Span {
    private enum CodingKeys: String, CodingKey { case value, unit }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = container.lenientInt(.value)
        unit = container.lenientString(.unit)
    }
}

extension OfferExtraction.Requirement {
    private enum CodingKeys: String, CodingKey { case kind, amount, count, within, holdFor, holdStart, details }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.lenientString(.kind)
        amount = container.lenientDecimal(.amount)
        count = container.lenientInt(.count)
        within = try? container.decodeIfPresent(OfferExtraction.Span.self, forKey: .within)
        holdFor = try? container.decodeIfPresent(OfferExtraction.Span.self, forKey: .holdFor)
        holdStart = container.lenientString(.holdStart)
        details = container.lenientString(.details)
    }
}

extension OfferExtraction.Waiver {
    private enum CodingKeys: String, CodingKey { case kind, amount, count, details }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.lenientString(.kind)
        amount = container.lenientDecimal(.amount)
        count = container.lenientInt(.count)
        details = container.lenientString(.details)
    }
}

extension OfferExtraction.Rule {
    private enum CodingKeys: String, CodingKey { case kind, scope, lookback, measuredFrom, states, note }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.lenientString(.kind)
        scope = container.lenientString(.scope)
        lookback = try? container.decodeIfPresent(OfferExtraction.Span.self, forKey: .lookback)
        measuredFrom = container.lenientString(.measuredFrom)
        states = (try? container.decodeIfPresent([String].self, forKey: .states)) ?? container.lenientString(.states).map { [$0] }
        note = container.lenientString(.note)
    }
}

// MARK: - Helpers

/// Lowercase letters and digits only: "Money Market" and "moneyMarket" both become "moneymarket".
func normalizedKey(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
}

/// Finds the case whose raw value matches `text` loosely, then tries `synonyms`.
func match<Value: RawRepresentable & CaseIterable>(_ text: String?, synonyms: [String: Value] = [:]) -> Value? where Value.RawValue == String {
    guard let text else { return nil }
    let key = normalizedKey(text)
    return Value.allCases.first { normalizedKey($0.rawValue) == key } ?? synonyms[key]
}

private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
        }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }

    func lenientDecimal(_ key: Key) -> Decimal? {
        if let number = try? decodeIfPresent(Decimal.self, forKey: key) { return number }
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return cleaned.isEmpty ? nil : Decimal(string: cleaned, locale: Locale(identifier: "en_US"))
    }

    func lenientInt(_ key: Key) -> Int? {
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number }
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return Int(number.rounded()) }
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return Int(text.filter(\.isNumber))
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        switch normalizedKey(text) {
        case "true", "yes": return true
        case "false", "no": return false
        default: return nil
        }
    }

    func lossyArray<Value: Decodable>(_ key: Key) -> [Value]? {
        (try? decodeIfPresent([Lossy<Value>].self, forKey: key))?.compactMap(\.value)
    }
}
