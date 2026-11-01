import Foundation
import Testing
@testable import BankTrackerCore

private func body(of request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

private func extractor(_ provider: AIProvider, key: String = "test-key", model: String = "", baseURL: String = "", reply: String = "{}", status: Int = 200) -> OfferExtractor {
    OfferExtractor(configuration: AIConfiguration(provider: provider, apiKey: key, model: model, baseURL: baseURL)) { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.utf8), response)
    }
}

private let offerJSON = #"{"bankName": "Maple Bank", "bonusAmount": 300}"#

private func jsonString(_ value: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)
}

@Suite("AI requests")
struct AIRequestTests {
    let today = day(2026, 11, 1)

    @Test func openAI() throws {
        let request = try extractor(.openAI).makeRequest(offerText: "offer", today: today)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let json = body(of: request)
        #expect(json["model"] as? String == "gpt-5-mini")
        #expect((json["response_format"] as? [String: String])?["type"] == "json_object")
        let messages = json["messages"] as? [[String: String]] ?? []
        #expect(messages.first?["content"]?.contains("\"bonusAmount\"") == true, "the schema is in the system prompt")
        #expect(messages.first?["content"]?.contains("2026-11-01") == true)
        #expect(messages.last?["content"] == "Offer text:\n\noffer")
    }

    @Test func compatibleServer() throws {
        let local = try extractor(.openAICompatible, key: "", model: "llama3.1", baseURL: "http://localhost:11434/v1/").makeRequest(offerText: "offer", today: today)
        #expect(local.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(local.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body(of: local)["response_format"] == nil)
        #expect(body(of: local)["model"] as? String == "llama3.1")

        let full = try extractor(.openAICompatible, baseURL: "https://openrouter.ai/api/v1/chat/completions").makeRequest(offerText: "offer", today: today)
        #expect(full.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")

        #expect(throws: AIError.invalidBaseURL) {
            try extractor(.openAICompatible, baseURL: "not a url").makeRequest(offerText: "offer", today: today)
        }
    }

    @Test func anthropic() throws {
        let request = try extractor(.anthropic).makeRequest(offerText: "offer", today: today)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let json = body(of: request)
        #expect(json["model"] as? String == "claude-opus-5-5")
        #expect((json["tool_choice"] as? [String: String])?["name"] == "record_offer")
        let tool = (json["tools"] as? [[String: Any]])?.first
        #expect((tool?["input_schema"] as? [String: Any])?["type"] as? String == "object")
        #expect((json["system"] as? String)?.contains("JSON Schema") == false, "Claude gets the schema as a tool, not in the prompt")
    }

    @Test func gemini() throws {
        let request = try extractor(.gemini, model: "gemini-2.5-pro").makeRequest(offerText: "offer", today: today)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        #expect((body(of: request)["generationConfig"] as? [String: String])?["responseMimeType"] == "application/json")
    }
}

@Suite("AI responses")
struct AIResponseTests {
    @Test func openAIReplyWithProseAndFences() async throws {
        let reply = jsonString(["choices": [["message": ["content": "Here you go:\n```json\n\(offerJSON)\n```"]]]])
        let result = try await extractor(.openAI, reply: reply).extract(fromOfferText: "offer")
        #expect(result.bankName == "Maple Bank")
        #expect(result.bonusAmount == 300)
    }

    @Test func reasoningModelThinkBlock() async throws {
        let reply = jsonString(["choices": [["message": ["content": "<think>maybe {\"bankName\": \"wrong\"}</think>\(offerJSON)"]]]])
        let result = try await extractor(.openAICompatible, baseURL: "http://localhost:1234/v1", reply: reply).extract(fromOfferText: "offer")
        #expect(result.bankName == "Maple Bank")
    }

    @Test func anthropicToolUse() async throws {
        let reply = jsonString(["content": [["type": "tool_use", "name": "record_offer", "input": ["bankName": "Maple Bank", "bonusAmount": 300]]]])
        let result = try await extractor(.anthropic, reply: reply).extract(fromOfferText: "offer")
        #expect(result.bankName == "Maple Bank")
    }

    @Test func geminiParts() async throws {
        let reply = jsonString(["candidates": [["content": ["parts": [["text": offerJSON]]]]]])
        let result = try await extractor(.gemini, reply: reply).extract(fromOfferText: "offer")
        #expect(result.bonusAmount == 300)
    }

    @Test func errors() async {
        let unauthorized = #"{"error": {"message": "Invalid API key", "type": "authentication_error"}}"#
        await #expect(throws: AIError.http(provider: "Claude", status: 401, message: "Invalid API key")) {
            try await extractor(.anthropic, reply: unauthorized, status: 401).extract(fromOfferText: "offer")
        }
        let empty = jsonString(["choices": [["message": ["content": ""]]]])
        await #expect(throws: AIError.emptyAnswer(provider: "OpenAI")) {
            try await extractor(.openAI, reply: empty).extract(fromOfferText: "offer")
        }
        await #expect(throws: AIError.noOfferText) {
            try await extractor(.openAI).extract(fromOfferText: "  ")
        }
        await #expect(throws: AIError.pageUnavailable(status: 403)) {
            try await extractor(.openAI, reply: "<html>blocked</html>", status: 403).fetchPageText(from: URL(string: "https://example.com")!)
        }
    }
}

@Suite("AI extraction mapping")
struct ExtractionMappingTests {
    let sample = #"""
    {
      "bankName": "Maple Bank", "productName": "Everyday Checking", "accountType": "Checking",
      "bonusAmount": "$400", "expirationDate": "2026-12-31", "promoCode": 12345,
      "requirements": [
        {"kind": "directDeposit", "amount": 1000, "count": "2", "within": {"value": 90, "unit": "days"}},
        {"kind": "maintainBalance", "amount": 15000, "within": {"value": 30, "unit": "days"}, "holdFor": {"value": 3, "unit": "months"}, "holdStart": "afterDepositWindow"},
        {"kind": "debit card purchases", "count": 10, "within": {"value": 2, "unit": "weeks"}},
        "not an object"
      ],
      "payoutBasis": "afterRequirementsMet", "payoutWithin": {"value": 30, "unit": "days"},
      "minimumOpen": {"value": 6, "unit": "months"}, "bonusClawback": "yes",
      "monthlyFee": 12, "feeWaivers": [{"kind": "monthlyDirectDeposit", "amount": 500}],
      "taxForm": "1099-INT",
      "eligibilityRules": [
        {"kind": "notCurrentCustomer", "scope": "sameAccountType"},
        {"kind": "noBonusWithin", "lookback": {"value": 2, "unit": "years"}, "measuredFrom": "accountOpenDate"},
        {"kind": "stateRestriction", "states": ["ny", "NJ", "Narnia"]},
        {"kind": "something new"}
      ],
      "notes": null
    }
    """#

    @Test("A deposit that has to stay put keeps its hold")
    func depositHold() throws {
        let json = #"""
        {"requirements": [
          {"kind": "deposit", "amount": 15000, "within": {"value": 30, "unit": "days"}, "holdFor": {"value": 90, "unit": "days"}, "holdStart": "afterFunding"},
          {"kind": "deposit", "amount": 500},
          {"kind": "deposit", "amount": 500, "holdFor": {"value": 0, "unit": "days"}}
        ]}
        """#
        let requirements = try JSONDecoder().decode(OfferExtraction.self, from: Data(json.utf8)).requirementValues
        #expect(requirements.map(\.hasHold) == [true, false, false])
        #expect(requirements[0].holdPeriod == .days(90))
        #expect(requirements[0].holdStart == .afterFunding)
    }

    @Test func mapsEverything() throws {
        let extraction = try JSONDecoder().decode(OfferExtraction.self, from: Data(sample.utf8))
        #expect(extraction.accountTypeValue == .checking)
        #expect(extraction.promoCode == "12345")
        #expect(extraction.notes == nil)
        #expect(extraction.expirationDateValue(calendar: utc) == day(2026, 12, 31))

        var terms = OfferTerms()
        let filled = extraction.apply(to: &terms)
        #expect(terms.bonusAmount == 400)
        #expect(terms.requirements.map(\.kind) == [.directDeposit, .maintainBalance, .debitPurchases])
        #expect(terms.requirements[0].count == 2)
        #expect(terms.requirements[1].holdPeriod == .months(3))
        #expect(terms.requirements[1].holdStart == .afterDepositWindow)
        #expect(terms.requirements[2].window == .days(14))
        #expect(terms.earlyClosure == EarlyClosurePolicy(minimumOpen: .months(6), basis: .fromOpening, fee: 0, bonusClawback: true))
        #expect(terms.maintenanceFee.monthlyFee == 12)
        #expect(terms.maintenanceFee.waivers.first?.kind == .directDeposit)
        #expect(terms.taxForm == .form1099INT)
        #expect(filled.contains("$400 bonus"))
        #expect(filled.contains("3 requirements"))

        let rules = extraction.ruleValues
        #expect(rules.map(\.kind) == [.notCurrentCustomer, .noBonusWithin, .stateRestriction, .manual])
        #expect(rules[1].span == .years(2))
        #expect(rules[1].measuredFrom == .accountOpenDate)
        #expect(rules[2].states == ["NY", "NJ"])
        #expect(rules[3].note == "something new")
    }

    @Test func missingFieldsLeaveTermsAlone() throws {
        let extraction = try JSONDecoder().decode(OfferExtraction.self, from: Data(#"{"bankName": "Maple Bank"}"#.utf8))
        var terms = OfferTerms(bonusAmount: 100, requirements: [.template(.deposit)])
        #expect(extraction.apply(to: &terms).isEmpty)
        #expect(terms.bonusAmount == 100)
        #expect(terms.requirements.count == 1)
    }
}

@Suite("HTML to text")
struct HTMLTextTests {
    @Test func stripsMarkup() {
        let html = """
        <html><head><title>x</title><style>p { color: red }</style></head>
        <body><script>var bonus = 999;</script><h1>Get $300</h1><p>Earn&nbsp;a bonus &amp; more&#8212;fast.</p>
        <ul><li>Open by 12/31</li><li>Direct deposit &#x24;500</li></ul><!-- hidden --></body></html>
        """
        let text = HTMLText.plainText(from: html)
        #expect(!text.contains("999"))
        #expect(!text.contains("color"))
        #expect(!text.contains("hidden"))
        #expect(text.contains("Get $300"))
        #expect(text.contains("Earn a bonus & more\u{2014}fast."))
        #expect(text.contains("Open by 12/31\n"))
        #expect(text.contains("Direct deposit $500"))
    }
}
