import Foundation
import Observation
import Security
import BankTrackerCore

/// The AI provider settings. The provider, model and base URL live in UserDefaults;
/// API keys live in the Keychain, one per provider.
@Observable
final class AISettings {
    private enum Keys {
        static let provider = "ai.provider"
        static let baseURL = "ai.baseURL"
        static func model(_ provider: AIProvider) -> String { "ai.model.\(provider.rawValue)" }
        static func hasKey(_ provider: AIProvider) -> String { "ai.hasKey.\(provider.rawValue)" }
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// True while values are being read from UserDefaults, so reading never writes them back.
    @ObservationIgnored private var isLoading = true

    var provider: AIProvider? {
        didSet {
            guard !isLoading else { return }
            defaults.set(provider?.rawValue ?? "", forKey: Keys.provider)
            loadProviderSettings()
        }
    }

    var model = "" {
        didSet {
            guard !isLoading, let provider else { return }
            defaults.set(model, forKey: Keys.model(provider))
        }
    }

    var baseURL = "" {
        didSet {
            guard !isLoading else { return }
            defaults.set(baseURL, forKey: Keys.baseURL)
        }
    }

    /// Whether a key is saved for the current provider. Tracked separately so checking
    /// doesn't need to read the Keychain.
    private(set) var hasAPIKey = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = AIProvider(rawValue: defaults.string(forKey: Keys.provider) ?? "")
        baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        loadProviderSettings()
        isLoading = false
    }

    private func loadProviderSettings() {
        let wasLoading = isLoading
        isLoading = true
        defer { isLoading = wasLoading }
        guard let provider else {
            model = ""
            hasAPIKey = false
            return
        }
        model = defaults.string(forKey: Keys.model(provider)) ?? ""
        hasAPIKey = defaults.bool(forKey: Keys.hasKey(provider))
    }

    /// Reads the saved key from the Keychain.
    func apiKey() -> String {
        guard let provider else { return "" }
        return Keychain.read(account: provider.rawValue) ?? ""
    }

    func setAPIKey(_ key: String) {
        guard let provider else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(trimmed, account: provider.rawValue)
        defaults.set(!trimmed.isEmpty, forKey: Keys.hasKey(provider))
        hasAPIKey = !trimmed.isEmpty
    }

    /// What's missing before AI filling can run, or nil when it's ready.
    var setupProblem: String? {
        guard let provider else { return "Choose an AI provider." }
        if provider.requiresAPIKey, !hasAPIKey {
            return "Add your \(provider.shortName) API key."
        }
        if provider == .openAICompatible {
            if baseURL.trimmingCharacters(in: .whitespaces).isEmpty { return "Add your AI service's base URL." }
            if model.trimmingCharacters(in: .whitespaces).isEmpty { return "Add a model name." }
        }
        return nil
    }

    /// A configuration ready to use, reading the key from the Keychain; nil until setup is complete.
    func makeConfiguration() -> AIConfiguration? {
        guard let provider, setupProblem == nil else { return nil }
        return AIConfiguration(provider: provider, apiKey: apiKey(), model: model, baseURL: baseURL)
    }
}

/// Generic-password items in the Keychain, scoped to this app.
nonisolated enum Keychain {
    static let service = "com.zibin.BankTracker.ai"

    static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `value`, or deletes the item when `value` is empty.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let query = baseQuery(account: account)
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var item = query
        item[kSecValueData as String] = data
        #if os(iOS)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
