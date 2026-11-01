import Foundation

public struct USState: Identifiable, Hashable, Sendable {
    public var code: String
    public var name: String

    public var id: String { code }

    public static let all: [USState] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"),
        ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"),
        ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"),
        ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"), ("NV", "Nevada"),
        ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"),
        ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"), ("OR", "Oregon"),
        ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
        ("PR", "Puerto Rico"), ("GU", "Guam"), ("VI", "U.S. Virgin Islands"), ("AS", "American Samoa"),
        ("MP", "Northern Mariana Islands"),
    ].map { USState(code: $0.0, name: $0.1) }

    public static func name(for code: String) -> String? {
        all.first { $0.code == code.uppercased() }?.name
    }

    /// Splits text like "NY, nj ct" into known codes and anything unrecognized.
    public static func parseCodes(_ text: String) -> (valid: [String], invalid: [String]) {
        let tokens = text
            .uppercased()
            .split { $0 == "," || $0 == " " || $0 == ";" || $0 == "\n" }
            .map(String.init)
        var valid: [String] = []
        var invalid: [String] = []
        for token in tokens {
            if all.contains(where: { $0.code == token }) {
                if !valid.contains(token) { valid.append(token) }
            } else {
                invalid.append(token)
            }
        }
        return (valid, invalid)
    }
}
