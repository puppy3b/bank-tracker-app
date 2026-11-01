import Foundation

/// An AI service that can read offer terms.
public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case anthropic
    case gemini
    /// Any server that speaks the OpenAI chat completions API (Ollama, LM Studio, OpenRouter…).
    case openAICompatible

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Claude (Anthropic)"
        case .gemini: "Gemini (Google)"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    /// For messages such as "Filled in by Claude".
    public var shortName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .openAICompatible: "your AI service"
        }
    }

    /// Used when no model is entered. OpenAI-compatible servers have no sensible default.
    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-opus-5-5"
        case .gemini: "gemini-2.5-flash"
        case .openAICompatible: ""
        }
    }

    /// Local servers such as Ollama usually don't need a key.
    public var requiresAPIKey: Bool { self != .openAICompatible }

    public var keyHint: String {
        switch self {
        case .openAI: "Create a key at platform.openai.com."
        case .anthropic: "Create a key at console.anthropic.com."
        case .gemini: "Create a key at aistudio.google.com."
        case .openAICompatible: "Leave the key empty for local servers such as Ollama."
        }
    }
}

/// Everything needed to call a provider.
public struct AIConfiguration: Hashable, Sendable {
    public var provider: AIProvider
    public var apiKey: String
    public var model: String
    /// Only used by `.openAICompatible`, e.g. "http://localhost:11434/v1".
    public var baseURL: String

    public init(provider: AIProvider, apiKey: String, model: String = "", baseURL: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    public var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }
}

public enum AIError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case http(provider: String, status: Int, message: String)
    case emptyAnswer(provider: String)
    case unreadableAnswer(provider: String)
    case pageUnavailable(status: Int)
    case pageEmpty
    case noOfferText

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The base URL in Settings isn't a valid web address."
        case .http(let provider, let status, let message):
            message.isEmpty ? "\(provider) returned an error (HTTP \(status))." : "\(provider) returned an error (HTTP \(status)): \(message)"
        case .emptyAnswer(let provider):
            "\(provider) didn't return any offer details."
        case .unreadableAnswer(let provider):
            "\(provider)'s answer couldn't be read as offer details. Try again, or try another model."
        case .pageUnavailable(let status):
            "Couldn't load the offer page (HTTP \(status)). Paste the offer's terms instead."
        case .pageEmpty:
            "The offer page had no readable text. Paste the offer's terms instead."
        case .noOfferText:
            "Paste the offer's terms or a link to the offer first."
        }
    }
}
