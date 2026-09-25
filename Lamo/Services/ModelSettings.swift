import Foundation

/// Pure data holder for all settings backed by AppDefaults.
/// No side effects — invalidation and validation are handled by ProviderManager.
@MainActor
final class ModelSettings {
    var providerType: ProviderType {
        get { ProviderType(rawValue: AppDefaults.providerType.wrappedValue) ?? .litertLM }
        set { AppDefaults.providerType.wrappedValue = newValue.rawValue }
    }

    var litertLMModelPath: String? {
        get { AppDefaults.modelPath.wrappedValue }
        set { AppDefaults.modelPath.wrappedValue = newValue }
    }

    var litertLMUseGPU: Bool {
        get { AppDefaults.useGPU.wrappedValue }
        set { AppDefaults.useGPU.wrappedValue = newValue }
    }

    var cpuThreadCount: Int {
        get { AppDefaults.cpuThreadCount.wrappedValue }
        set { AppDefaults.cpuThreadCount.wrappedValue = newValue }
    }

    var topK: Int {
        get { AppDefaults.topK.wrappedValue }
        set { AppDefaults.topK.wrappedValue = newValue }
    }

    var topP: Double {
        get { AppDefaults.topP.wrappedValue }
        set { AppDefaults.topP.wrappedValue = newValue }
    }

    var temperature: Double {
        get { AppDefaults.temperature.wrappedValue }
        set { AppDefaults.temperature.wrappedValue = newValue }
    }

    var maxNumTokens: Int {
        get { AppDefaults.maxNumTokens.wrappedValue }
        set { AppDefaults.maxNumTokens.wrappedValue = newValue }
    }

    var kvCacheAuto: Bool {
        get { AppDefaults.kvCacheAuto.wrappedValue }
        set { AppDefaults.kvCacheAuto.wrappedValue = newValue }
    }

    var speculativeDecoding: Bool {
        get { AppDefaults.speculativeDecoding.wrappedValue }
        set { AppDefaults.speculativeDecoding.wrappedValue = newValue }
    }

    var visualTokenBudget: Int {
        get { AppDefaults.visualTokenBudget.wrappedValue }
        set { AppDefaults.visualTokenBudget.wrappedValue = newValue }
    }

    var systemPrompt: String {
        get { AppDefaults.systemPrompt.wrappedValue }
        set { AppDefaults.systemPrompt.wrappedValue = newValue }
    }

    var thinkingMode: Bool {
        get { AppDefaults.thinkingMode.wrappedValue }
        set { AppDefaults.thinkingMode.wrappedValue = newValue }
    }

    /// Canonical default system prompt — single source of truth is AppDefaults.
    /// Tool details live in the tool schemas, not here.
    var defaultSystemPrompt: String {
        AppDefaults.systemPrompt.defaultValue
    }
}
