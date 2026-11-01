import Foundation

/// The instructions and JSON schema sent to every provider.
enum ExtractionPrompt {
    static func system(today: Date, includeSchema: Bool) -> String {
        let date = today.formatted(.iso8601.year().month().day())
        var text = """
        You read bank account bonus offers (bank web pages, terms and conditions, or blog posts such as \
        Doctor of Credit) and extract their details for a personal bonus tracker.

        General rules:
        - Report only what the text says. Leave a field out when the text doesn't cover it. Never invent amounts, dates or rules.
        - Amounts are US dollars as plain numbers (300, not "$300").
        - Dates use YYYY-MM-DD. Today is \(date); resolve relative dates against it.
        - Time spans are {"value": number, "unit": "days" | "months" | "years"}. Deadlines count from account opening unless the text says otherwise.
        - If the bonus has tiers, use the highest tier and list every tier in notes.

        Requirements (requirements):
        - directDeposit: amount = total direct deposits needed; count = number of deposits when a number is required.
        - deposit: amount = new money to deposit; within = deposit deadline. When the money must then stay in the account \
        for a while ("maintain the new money for 90 days"), add holdFor and holdStart as for maintainBalance.
        - maintainBalance: amount = balance to keep; within = funding deadline; holdFor = how long to keep it; holdStart = afterFunding, afterDepositWindow or fromOpening.
        - debitPurchases and billPay: count = number of transactions; amount = total spend when one is required.
        - other: describe it in details.

        Eligibility rules (eligibilityRules), from the fine print:
        - notCurrentCustomer: not available to current customers. scope = sameAccountType when it names the account type ("current checking customers"), anyAccount when any relationship counts.
        - noAccountWithin: had or closed an account within a lookback, e.g. "closed within the past 90 days" or "not a customer in the past 12 months".
        - noBonusWithin: received a bonus within a lookback. measuredFrom = accountOpenDate when counted from enrollment or opening, otherwise bonusPaidDate.
        - oneAccountPer: limit one new account per period.
        - neverHadAccount: new customers only, or never had an account.
        - oncePerLifetime: one bonus per customer, ever.
        - stateRestriction: only for residents of the listed states; states are USPS codes.
        - manual: any other condition, described in note.

        Closing, fees and taxes:
        - minimumOpen, minimumOpenBasis, earlyClosureFee and bonusClawback describe closing early. "If the account is closed within 6 months, the bonus will be deducted" means minimumOpen 6 months, fromOpening, bonusClawback true.
        - monthlyFee is the maintenance fee (0 when the text says there is none); feeWaivers are the ways to avoid it.
        - taxForm is form1099INT for bank bonuses unless the text says otherwise, and form1099MISC for most brokerage bonuses.
        """
        if includeSchema {
            text += "\n\nRespond with one JSON object that follows this JSON Schema, and nothing else:\n" + schemaText
        }
        return text
    }

    static func user(offerText: String) -> String {
        "Offer text:\n\n" + offerText
    }

    /// Longest offer text sent, in characters. Long pages are mostly navigation and footers.
    static let maxOfferLength = 40_000

    static var schemaText: String {
        let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    static var schema: [String: Any] {
        let span: [String: Any] = [
            "type": "object",
            "properties": [
                "value": ["type": "integer"],
                "unit": ["type": "string", "enum": ["days", "months", "years"]],
            ],
        ]
        func text(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
        func number(_ description: String) -> [String: Any] { ["type": "number", "description": description] }
        func choice(_ values: [String], _ description: String = "") -> [String: Any] {
            description.isEmpty ? ["type": "string", "enum": values] : ["type": "string", "enum": values, "description": description]
        }
        func spanWith(_ description: String) -> [String: Any] {
            var copy = span
            copy["description"] = description
            return copy
        }
        func list(_ properties: [String: Any]) -> [String: Any] {
            ["type": "array", "items": ["type": "object", "properties": properties]]
        }

        return [
            "type": "object",
            "properties": [
                "bankName": text("Bank, credit union or brokerage, e.g. Chase"),
                "productName": text("Account product, e.g. Total Checking"),
                "accountType": choice(AccountType.allCases.map(\.rawValue)),
                "bonusAmount": number("Bonus in dollars"),
                "expirationDate": text("Last day to open the account, YYYY-MM-DD"),
                "promoCode": text("Promo or coupon code"),
                "minimumOpeningDeposit": number("Minimum deposit to open, in dollars"),
                "requirements": list([
                    "kind": choice(BonusRequirement.Kind.allCases.map(\.rawValue)),
                    "amount": number("Dollars: direct deposit total, deposit, balance to keep, or spend total"),
                    "count": ["type": "integer", "description": "Number of deposits or transactions required"],
                    "within": spanWith("Deadline, counted from account opening"),
                    "holdFor": spanWith("deposit and maintainBalance: how long the money must stay in the account"),
                    "holdStart": choice(BonusRequirement.HoldStart.allCases.map(\.rawValue)),
                    "details": text("Fine print, e.g. what counts as a direct deposit"),
                ]),
                "payoutBasis": choice(PayoutTiming.Basis.allCases.map(\.rawValue)),
                "payoutWithin": spanWith("How soon the bonus is paid after payoutBasis"),
                "minimumOpen": spanWith("How long the account must stay open to avoid a fee or clawback"),
                "minimumOpenBasis": choice(EarlyClosurePolicy.Basis.allCases.map(\.rawValue)),
                "earlyClosureFee": number("Early account closure fee in dollars"),
                "bonusClawback": ["type": "boolean", "description": "Whether the bonus is taken back if the account closes early"],
                "monthlyFee": number("Monthly maintenance fee in dollars; 0 if none"),
                "feeWaivers": list([
                    "kind": choice(FeeWaiver.Kind.allCases.map(\.rawValue)),
                    "amount": number("Dollar amount for the waiver"),
                    "count": ["type": "integer", "description": "Number of purchases, for debitPurchases"],
                    "details": text("Anything else about the waiver"),
                ]),
                "feeNotes": text("Other fees worth knowing about"),
                "taxForm": choice(TaxFormType.allCases.map(\.rawValue)),
                "eligibilityRules": list([
                    "kind": choice(EligibilityRule.Kind.allCases.map(\.rawValue)),
                    "scope": choice(EligibilityRule.Scope.allCases.map(\.rawValue)),
                    "lookback": spanWith("Lookback or period for noAccountWithin, noBonusWithin and oneAccountPer"),
                    "measuredFrom": choice(EligibilityRule.BonusDateBasis.allCases.map(\.rawValue)),
                    "states": ["type": "array", "items": ["type": "string"], "description": "USPS codes for stateRestriction"],
                    "note": text("For manual rules: the condition to check"),
                ]),
                "notes": text("Anything important that doesn't fit above, in one or two short sentences"),
            ],
        ]
    }
}
