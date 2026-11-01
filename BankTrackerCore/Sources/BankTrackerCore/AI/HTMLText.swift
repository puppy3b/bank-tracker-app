import Foundation

/// Turns an HTML page into plain text that's small enough to send to an AI service.
public enum HTMLText {
    public static func plainText(from html: String, limit: Int = 40_000) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg", "head", "template", "iframe"] {
            text = text.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<(br|/p|/div|/li|/tr|/h[1-6]|/section|/article)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\n[ \n]*", with: "\n", options: .regularExpression)
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "dollar": "$", "reg": "\u{00AE}",
        "trade": "\u{2122}", "copy": "\u{00A9}", "bull": "\u{2022}", "middot": "\u{00B7}",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let pattern = try? NSRegularExpression(pattern: "&(#x?[0-9a-fA-F]+|[a-zA-Z]+);") else { return text }
        let source = text as NSString
        var result = ""
        var location = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            let name = source.substring(with: match.range(at: 1))
            result += replacement(for: name) ?? source.substring(with: match.range)
            location = match.range.location + match.range.length
        }
        result += source.substring(from: location)
        return result
    }

    private static func replacement(for entity: String) -> String? {
        if entity.hasPrefix("#") {
            let isHex = entity.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
            let digits = entity.dropFirst(isHex ? 2 : 1)
            guard let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[entity.lowercased()]
    }
}
