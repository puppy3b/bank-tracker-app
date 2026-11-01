import Foundation

/// Sends offer text to the configured AI provider and reads back the offer details.
public struct OfferExtractor: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public var configuration: AIConfiguration
    public var transport: Transport

    public init(configuration: AIConfiguration, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.configuration = configuration
        self.transport = transport
    }

    /// A short offer used by Settings' connection test.
    public static let sampleOffer = """
    Example Bank: get a $200 bonus when you open a new Everyday Checking account and receive direct deposits \
    totaling $500 or more within 60 days. Offer ends December 31, 2026. Not available to existing checking customers.
    """

    public func extract(fromOfferText text: String, today: Date = .now) async throws -> OfferExtraction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.noOfferText }
        let request = try makeRequest(offerText: String(trimmed.prefix(ExtractionPrompt.maxOfferLength)), today: today)
        let (data, response) = try await transport(request)
        let name = configuration.provider.shortName
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw AIError.http(provider: name, status: status, message: Self.errorMessage(in: data))
        }
        let json = try Self.offerJSON(from: data, provider: configuration.provider)
        do {
            return try JSONDecoder().decode(OfferExtraction.self, from: json)
        } catch {
            throw AIError.unreadableAnswer(provider: name)
        }
    }

    /// Downloads a web page and returns its readable text.
    public func fetchPageText(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw AIError.pageUnavailable(status: status)
        }
        let text = HTMLText.plainText(from: String(decoding: data, as: UTF8.self))
        guard !text.isEmpty else { throw AIError.pageEmpty }
        return text
    }

    // MARK: - Requests

    func makeRequest(offerText: String, today: Date) throws -> URLRequest {
        let model = configuration.resolvedModel
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = ExtractionPrompt.user(offerText: offerText)

        let url: URL
        var headers = ["Content-Type": "application/json"]
        let body: [String: Any]

        switch configuration.provider {
        case .openAI, .openAICompatible:
            url = try chatCompletionsURL()
            if !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
            var chat: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": ExtractionPrompt.system(today: today, includeSchema: true)],
                    ["role": "user", "content": user],
                ],
            ]
            // Compatible servers vary in which response formats they accept, so only OpenAI gets one.
            if configuration.provider == .openAI {
                chat["response_format"] = ["type": "json_object"]
            }
            body = chat

        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = key
            headers["anthropic-version"] = "2023-06-01"
            // A forced tool call makes Claude answer with JSON that follows the schema.
            body = [
                "model": model,
                "max_tokens": 4096,
                "system": ExtractionPrompt.system(today: today, includeSchema: false),
                "tools": [[
                    "name": "record_offer",
                    "description": "Record the details of a bank bonus offer.",
                    "input_schema": ExtractionPrompt.schema,
                ]],
                "tool_choice": ["type": "tool", "name": "record_offer"],
                "messages": [["role": "user", "content": user]],
            ]

        case .gemini:
            let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!
            headers["x-goog-api-key"] = key
            body = [
                "systemInstruction": ["parts": [["text": ExtractionPrompt.system(today: today, includeSchema: true)]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
                "generationConfig": ["responseMimeType": "application/json"],
            ]
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Accepts "https://host/v1", "https://host/v1/" or the full ".../chat/completions" address.
    func chatCompletionsURL() throws -> URL {
        let base = configuration.provider == .openAI
            ? "https://api.openai.com/v1"
            : configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = base
        while address.hasSuffix("/") { address.removeLast() }
        if !address.hasSuffix("/chat/completions") { address += "/chat/completions" }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil
        else { throw AIError.invalidBaseURL }
        return url
    }

    // MARK: - Responses

    /// Pulls the offer JSON out of a provider's response body.
    static func offerJSON(from data: Data, provider: AIProvider) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.unreadableAnswer(provider: provider.shortName)
        }
        let reply: String
        switch provider {
        case .openAI, .openAICompatible:
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            reply = message?["content"] as? String ?? ""
        case .anthropic:
            let blocks = object["content"] as? [[String: Any]] ?? []
            if let input = blocks.first(where: { $0["type"] as? String == "tool_use" })?["input"],
               JSONSerialization.isValidJSONObject(input) {
                return try JSONSerialization.data(withJSONObject: input)
            }
            reply = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .gemini:
            let candidates = object["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            reply = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyAnswer(provider: provider.shortName)
        }
        guard let json = jsonObjectText(in: reply) else {
            throw AIError.unreadableAnswer(provider: provider.shortName)
        }
        return Data(json.utf8)
    }

    /// The JSON object in a reply that may also contain prose, ```json fences or <think> blocks.
    static func jsonObjectText(in reply: String) -> String? {
        let visible = reply.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        guard let start = visible.firstIndex(of: "{"), let end = visible.lastIndex(of: "}"), start < end else { return nil }
        return String(visible[start...end])
    }

    /// The `error.message` that OpenAI, Anthropic and Gemini all use, or the start of the body.
    static func errorMessage(in data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("<") ? "" : text
    }
}
