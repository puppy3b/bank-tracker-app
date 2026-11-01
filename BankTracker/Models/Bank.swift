import Foundation
import SwiftData

@Model
final class Bank {
    var uuid: UUID = UUID()
    var name: String = ""
    var website: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \BankAccount.bank)
    var accounts: [BankAccount]? = []

    @Relationship(deleteRule: .cascade, inverse: \Offer.bank)
    var offers: [Offer]? = []

    @Relationship(deleteRule: .cascade, inverse: \TaxFormStatus.bank)
    var taxForms: [TaxFormStatus]? = []

    init(name: String, website: String = "", notes: String = "") {
        self.name = name
        self.website = website
        self.notes = notes
    }

    var accountList: [BankAccount] { accounts ?? [] }
    var offerList: [Offer] { offers ?? [] }
}
