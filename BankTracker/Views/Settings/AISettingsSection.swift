import SwiftUI
import BankTrackerCore

/// Settings for filling offers with AI: provider, key, model and a connection test.
struct AISettingsSection: View {
    @State private var settings = AISettings()
    @State private var apiKey = ""
    @State private var savedKey = ""
    @State private var isTesting = false
    @State private var testResult: AIFillStatus?

    var body: some View {
        Section {
            Picker(selection: $settings.provider) {
                Text("Off").tag(AIProvider?.none)
                Divider()
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(Optional(provider))
                }
            } label: {
                Label("Provider", systemImage: "sparkles")
            }

            if let provider = settings.provider {
                if provider == .openAICompatible {
                    LabeledTextField(title: "Base URL", text: $settings.baseURL, prompt: "e.g. http://localhost:11434/v1")
                }
                LabeledContent("API key") {
                    SecureField("API key", text: $apiKey, prompt: Text(provider.requiresAPIKey ? "Required" : "Optional"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                LabeledTextField(
                    title: "Model",
                    text: $settings.model,
                    prompt: provider.defaultModel.isEmpty ? "Required, e.g. llama3.1" : provider.defaultModel
                )
                HStack {
                    Button("Test Connection", systemImage: "bolt.horizontal") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || settings.setupProblem != nil)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                }
                if let testResult {
                    AIFillStatusView(status: testResult)
                }
            }
        } header: {
            Text("Fill offers with AI")
        } footer: {
            Text(footer)
        }
        .onAppear { loadKey() }
        .onChange(of: settings.provider) {
            loadKey()
            testResult = nil
        }
        .onChange(of: apiKey) { _, newKey in
            guard newKey != savedKey else { return }
            settings.setAPIKey(newKey)
            savedKey = newKey
            testResult = nil
        }
    }

    private var footer: String {
        guard let provider = settings.provider else {
            return "When you add an offer, paste its terms or a link and AI fills in the form. Choose a provider and add your API key to turn it on."
        }
        var text = "\(provider.keyHint) When you fill an offer with AI, only the text you paste (or the offer page at the link) is sent to \(provider.shortName). Your key is stored in the Keychain on this device."
        if let problem = settings.setupProblem {
            text = "Still needed: \(problem) " + text
        }
        return text
    }

    private func loadKey() {
        savedKey = settings.apiKey()
        apiKey = savedKey
    }

    private func testConnection() async {
        guard let configuration = settings.makeConfiguration() else { return }
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let result = try await OfferExtractor(configuration: configuration).extract(fromOfferText: OfferExtractor.sampleOffer)
            let bonus = result.bonusAmount.map { "a \(Money.format($0)) bonus" } ?? "the test offer"
            let bank = result.bankName.map { " at \($0)" } ?? ""
            testResult = .success("Connected. \(configuration.provider.shortName) read \(bonus)\(bank).")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}

/// The outcome of an AI request, shown under the button that started it.
enum AIFillStatus: Equatable {
    case success(String)
    case failure(String)
}

struct AIFillStatusView: View {
    let status: AIFillStatus

    var body: some View {
        Group {
            switch status {
            case .success(let text):
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
                }
            case .failure(let text):
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical)
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}
