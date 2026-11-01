import Foundation
import SwiftData
import BankTrackerCore

/// Your checklist state for one expected tax form (bank + form type + year).
/// The expected amounts themselves are always recomputed from your accounts.
@Model
final class TaxFormStatus {
    var uuid: UUID = UUID()
    var taxYear: Int = 0
    var bank: Bank?
    var formTypeRaw: String = TaxFormType.form1099INT.rawValue
    var isReceived: Bool = false
    var receivedDate: Date? = nil
    var reportedAmount: Decimal? = nil
    var notes: String = ""

    init() {}

    var formType: TaxFormType {
        get { TaxFormType(rawValue: formTypeRaw) ?? .form1099INT }
        set { formTypeRaw = newValue.rawValue }
    }
}

/// JSON storage for the value types kept in `Data` attributes.
nonisolated enum StoredJSON {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}
