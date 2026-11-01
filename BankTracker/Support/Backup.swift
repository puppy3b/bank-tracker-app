import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import BankTrackerCore

/// A complete JSON copy of the app's data.
nonisolated struct BackupFile: Codable, Sendable {
    var formatVersion = 1
    var exportedAt: Date
    var residenceState: String?
    var banks: [BackupBank]
    var offers: [BackupOffer]
    var accounts: [BackupAccount]
    var taxForms: [BackupTaxForm]
}

nonisolated struct BackupBank: Codable, Sendable {
    var id: UUID
    var name: String
    var website: String
    var notes: String
    var createdAt: Date
}

nonisolated struct BackupOffer: Codable, Sendable {
    var id: UUID
    var bankID: UUID?
    var productName: String
    var accountType: String
    var terms: OfferTerms
    var rules: [EligibilityRule]
    var url: String
    var promoCode: String
    var foundDate: Date
    var expirationDate: Date?
    var status: String
    var notes: String
    var createdAt: Date
}

nonisolated struct BackupAccount: Codable, Sendable {
    var id: UUID
    var bankID: UUID?
    var sourceOfferID: UUID?
    var productName: String
    var accountType: String
    var last4: String
    var openedDate: Date
    var closedDate: Date?
    var hasBonus: Bool
    var terms: OfferTerms
    var bonusReceivedDate: Date?
    var bonusReceivedAmount: Decimal?
    var bonusForfeited: Bool
    var isKeeper: Bool
    var currentBalance: Decimal
    var feesPaid: Decimal
    var inquiry: String
    var notes: String
    var createdAt: Date
}

nonisolated struct BackupTaxForm: Codable, Sendable {
    var id: UUID
    var taxYear: Int
    var bankID: UUID?
    var formType: String
    var isReceived: Bool
    var receivedDate: Date?
    var reportedAmount: Decimal?
    var notes: String
}

nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    static func makeBackup(context: ModelContext, residenceState: String) throws -> Data {
        let backup = BackupFile(
            exportedAt: .now,
            residenceState: residenceState.isEmpty ? nil : residenceState,
            banks: try context.fetch(FetchDescriptor<Bank>()).map { bank in
                BackupBank(id: bank.uuid, name: bank.name, website: bank.website, notes: bank.notes, createdAt: bank.createdAt)
            },
            offers: try context.fetch(FetchDescriptor<Offer>()).map { offer in
                BackupOffer(
                    id: offer.uuid,
                    bankID: offer.bank?.uuid,
                    productName: offer.productName,
                    accountType: offer.accountTypeRaw,
                    terms: offer.terms,
                    rules: offer.eligibilityRules,
                    url: offer.url,
                    promoCode: offer.promoCode,
                    foundDate: offer.foundDate,
                    expirationDate: offer.expirationDate,
                    status: offer.statusRaw,
                    notes: offer.notes,
                    createdAt: offer.createdAt
                )
            },
            accounts: try context.fetch(FetchDescriptor<BankAccount>()).map { account in
                BackupAccount(
                    id: account.uuid,
                    bankID: account.bank?.uuid,
                    sourceOfferID: account.sourceOffer?.uuid,
                    productName: account.productName,
                    accountType: account.accountTypeRaw,
                    last4: account.last4,
                    openedDate: account.openedDate,
                    closedDate: account.closedDate,
                    hasBonus: account.hasBonus,
                    terms: account.terms,
                    bonusReceivedDate: account.bonusReceivedDate,
                    bonusReceivedAmount: account.bonusReceivedAmount,
                    bonusForfeited: account.bonusForfeited,
                    isKeeper: account.isKeeper,
                    currentBalance: account.currentBalance,
                    feesPaid: account.feesPaid,
                    inquiry: account.inquiryRaw,
                    notes: account.notes,
                    createdAt: account.createdAt
                )
            },
            taxForms: try context.fetch(FetchDescriptor<TaxFormStatus>()).map { status in
                BackupTaxForm(
                    id: status.uuid,
                    taxYear: status.taxYear,
                    bankID: status.bank?.uuid,
                    formType: status.formTypeRaw,
                    isReceived: status.isReceived,
                    receivedDate: status.receivedDate,
                    reportedAmount: status.reportedAmount,
                    notes: status.notes
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Replaces everything in the store with the backup's contents.
    static func restore(_ backup: BackupFile, into context: ModelContext) throws {
        try deleteAll(in: context)

        var banks: [UUID: Bank] = [:]
        for record in backup.banks {
            let bank = Bank(name: record.name, website: record.website, notes: record.notes)
            context.insert(bank)
            bank.uuid = record.id
            bank.createdAt = record.createdAt
            banks[record.id] = bank
        }

        var offers: [UUID: Offer] = [:]
        for record in backup.offers {
            let offer = Offer()
            context.insert(offer)
            offer.uuid = record.id
            offer.bank = record.bankID.flatMap { banks[$0] }
            offer.productName = record.productName
            offer.accountTypeRaw = record.accountType
            offer.terms = record.terms
            offer.eligibilityRules = record.rules
            offer.url = record.url
            offer.promoCode = record.promoCode
            offer.foundDate = record.foundDate
            offer.expirationDate = record.expirationDate
            offer.statusRaw = record.status
            offer.notes = record.notes
            offer.createdAt = record.createdAt
            offers[record.id] = offer
        }

        for record in backup.accounts {
            let account = BankAccount()
            context.insert(account)
            account.uuid = record.id
            account.bank = record.bankID.flatMap { banks[$0] }
            account.sourceOffer = record.sourceOfferID.flatMap { offers[$0] }
            account.productName = record.productName
            account.accountTypeRaw = record.accountType
            account.last4 = record.last4
            account.openedDate = record.openedDate
            account.closedDate = record.closedDate
            account.hasBonus = record.hasBonus
            account.terms = record.terms
            account.bonusReceivedDate = record.bonusReceivedDate
            account.bonusReceivedAmount = record.bonusReceivedAmount
            account.bonusForfeited = record.bonusForfeited
            account.isKeeper = record.isKeeper
            account.currentBalance = record.currentBalance
            account.feesPaid = record.feesPaid
            account.inquiryRaw = record.inquiry
            account.notes = record.notes
            account.createdAt = record.createdAt
        }

        for record in backup.taxForms {
            let status = TaxFormStatus()
            context.insert(status)
            status.uuid = record.id
            status.taxYear = record.taxYear
            status.bank = record.bankID.flatMap { banks[$0] }
            status.formTypeRaw = record.formType
            status.isReceived = record.isReceived
            status.receivedDate = record.receivedDate
            status.reportedAmount = record.reportedAmount
            status.notes = record.notes
        }

        try context.save()
    }

    static func deleteAll(in context: ModelContext) throws {
        for status in try context.fetch(FetchDescriptor<TaxFormStatus>()) { context.delete(status) }
        for account in try context.fetch(FetchDescriptor<BankAccount>()) { context.delete(account) }
        for offer in try context.fetch(FetchDescriptor<Offer>()) { context.delete(offer) }
        for bank in try context.fetch(FetchDescriptor<Bank>()) { context.delete(bank) }
        try context.save()
    }
}
