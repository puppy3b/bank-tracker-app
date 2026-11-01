import Foundation
import BankTrackerCore

/// Editable copy of an offer. Editors work on a draft so Cancel discards everything.
struct OfferDraft {
    var bank: Bank?
    var productName = ""
    var accountType: AccountType = .checking
    var terms = OfferTerms()
    /// Almost every bank offer excludes existing customers, so new offers start with that rule.
    var rules: [EligibilityRule] = [.template(.notCurrentCustomer)]
    var url = ""
    var promoCode = ""
    var foundDate = Date.now
    var expirationDate: Date?
    var status: OfferStatus = .considering
    var notes = ""

    init(bank: Bank? = nil) {
        self.bank = bank
    }

    init(offer: Offer) {
        bank = offer.bank
        productName = offer.productName
        accountType = offer.accountType
        terms = offer.terms
        rules = offer.eligibilityRules
        url = offer.url
        promoCode = offer.promoCode
        foundDate = offer.foundDate
        expirationDate = offer.expirationDate
        status = offer.status
        notes = offer.notes
    }

    var canSave: Bool { bank != nil }

    func apply(to offer: Offer) {
        offer.bank = bank
        offer.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.accountType = accountType
        offer.terms = terms
        offer.eligibilityRules = rules
        offer.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.promoCode = promoCode.trimmingCharacters(in: .whitespacesAndNewlines)
        offer.foundDate = foundDate
        offer.expirationDate = expirationDate
        offer.status = status
        offer.notes = notes
    }
}

/// Editable copy of an account.
struct AccountDraft {
    var bank: Bank?
    var sourceOffer: Offer?
    var productName = ""
    var accountType: AccountType = .checking
    var last4 = ""
    var openedDate = Date.now
    var closedDate: Date?
    var hasBonus = false
    var terms = OfferTerms()
    var bonusReceivedDate: Date?
    var bonusReceivedAmount: Decimal = 0
    var bonusForfeited = false
    var isKeeper = false
    var currentBalance: Decimal = 0
    var feesPaid: Decimal = 0
    var inquiry: InquiryType = .unknown
    var notes = ""

    init() {}

    init(account: BankAccount) {
        bank = account.bank
        sourceOffer = account.sourceOffer
        productName = account.productName
        accountType = account.accountType
        last4 = account.last4
        openedDate = account.openedDate
        closedDate = account.closedDate
        hasBonus = account.hasBonus
        terms = account.terms
        bonusReceivedDate = account.bonusReceivedDate
        bonusReceivedAmount = account.bonusReceivedAmount ?? account.terms.bonusAmount
        bonusForfeited = account.bonusForfeited
        isKeeper = account.isKeeper
        currentBalance = account.currentBalance
        feesPaid = account.feesPaid
        inquiry = account.inquiry
        notes = account.notes
    }

    /// A new account opened with `offer`: its terms are copied, with progress cleared.
    init(offer: Offer) {
        bank = offer.bank
        sourceOffer = offer
        productName = offer.productName
        accountType = offer.accountType
        hasBonus = true
        terms = offer.terms.resettingProgress()
        bonusReceivedAmount = offer.terms.bonusAmount
        if !offer.promoCode.isEmpty {
            notes = "Promo code: \(offer.promoCode)"
        }
    }

    var canSave: Bool { bank != nil }

    func apply(to account: BankAccount) {
        account.bank = bank
        account.sourceOffer = sourceOffer
        account.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        account.accountType = accountType
        account.last4 = last4.trimmingCharacters(in: .whitespacesAndNewlines)
        account.openedDate = openedDate
        account.closedDate = closedDate
        account.hasBonus = hasBonus
        account.terms = terms
        account.bonusReceivedDate = hasBonus ? bonusReceivedDate : nil
        account.bonusReceivedAmount = hasBonus && bonusReceivedDate != nil ? bonusReceivedAmount : nil
        account.bonusForfeited = hasBonus && bonusForfeited
        account.isKeeper = isKeeper
        account.currentBalance = currentBalance
        account.feesPaid = feesPaid
        account.inquiry = inquiry
        account.notes = notes
    }
}

extension OfferDraft {
    /// Copies what an AI service found into the draft, keeping anything it left out.
    /// Returns short descriptions of what was filled, for a status message.
    mutating func merge(_ extraction: OfferExtraction) -> [String] {
        var filled: [String] = []
        if let product = extraction.productName {
            productName = product
            filled.append("product")
        }
        if let type = extraction.accountTypeValue {
            accountType = type
            terms.taxForm = type.defaultTaxForm
            filled.append("account type")
        }
        filled += extraction.apply(to: &terms)
        let rules = extraction.ruleValues
        if !rules.isEmpty {
            self.rules = rules
            filled.append(rules.count == 1 ? "1 eligibility rule" : "\(rules.count) eligibility rules")
        }
        if let date = extraction.expirationDateValue() {
            expirationDate = date
            filled.append("end date")
        }
        if let code = extraction.promoCode {
            promoCode = code
            filled.append("promo code")
        }
        if let extra = extraction.notes {
            notes = notes.isEmpty ? extra : notes + "\n\n" + extra
            filled.append("notes")
        }
        return filled
    }
}
