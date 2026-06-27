import Foundation

/// Available LLM providers in the app.
enum ProviderType: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple"
    case litertLM = "litertlm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .litertLM: return "LiteRT-LM (Local)"
        }
    }

    var icon: String {
        switch self {
        case .appleIntelligence: return "apple.logo"
        case .litertLM: return "cpu"
        }
    }
}

/// Manages the active LLM provider. Persists selection via UserDefaults.
@MainActor
final class ProviderManager {
    static let shared = ProviderManager()

    @AppStorage("selectedProvider") var selectedProvider: ProviderType = .appleIntelligence

    /// Model path for LiteRT-LM (stored in UserDefaults).
    var litertLMModelPath: String? {
        get { UserDefaults.standard.string(forKey: "litertLMModelPath") }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMModelPath") }
    }

    /// Whether to use GPU acceleration for LiteRT-LM.
    var litertLMUseGPU: Bool {
        get { UserDefaults.standard.object(forKey: "litertLMUseGPU") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMUseGPU") }
    }

    func makeProvider() -> any LLMProvider {
        switch selectedProvider {
        case .appleIntelligence:
            return AppleIntelligenceProvider()
        case .litertLM:
            return LiteRTLMProvider(
                modelPath: litertLMModelPath,
                useGPU: litertLMUseGPU
            )
        }
    }
}
