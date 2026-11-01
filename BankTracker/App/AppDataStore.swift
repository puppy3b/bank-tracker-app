import Foundation
import SwiftData

enum AppDataStore {
    static let schema = Schema([Bank.self, Offer.self, BankAccount.self, TaxFormStatus.self])

    /// Data stays on this device for now. The models are already CloudKit-compatible
    /// (every attribute has a default and every relationship is optional), so syncing
    /// between Mac, iPhone and iPad later means adding the iCloud capability and passing
    /// `.private("iCloud.<bundle id>")` here instead of `.none`.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "BankTracker",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

extension ModelContainer {
    /// In-memory store filled with sample data, for SwiftUI previews.
    @MainActor static let preview: ModelContainer = {
        do {
            let container = try AppDataStore.makeContainer(inMemory: true)
            SampleData.load(into: container.mainContext)
            return container
        } catch {
            fatalError("Couldn't create the preview store: \(error)")
        }
    }()
}

enum SettingsKey {
    static let residenceState = "residenceState"
    static let remindersEnabled = "remindersEnabled"
    static let reminderMinuteOfDay = "reminderMinuteOfDay"
    static let reminderLeadDays = "reminderLeadDays"
}
