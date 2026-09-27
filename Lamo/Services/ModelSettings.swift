import Foundation

/// Pure data holder for all settings backed by AppDefaults.
/// No side effects — invalidation and validation are handled by ProviderManager.
@MainActor
final class ModelSettings {
    /// In-memory cache for hot UserDefaults reads (temperature is read per
    /// inference turn, systemPrompt per message build). Invalidated on set.
    private var cachedTemperature: Double?
    private var cachedSystemPrompt: String?
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
        get {
            if let cached = cachedTemperature { return cached }
            let value = AppDefaults.temperature.wrappedValue
            cachedTemperature = value
            return value
        }
        set {
            cachedTemperature = newValue
            AppDefaults.temperature.wrappedValue = newValue
        }
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
        get {
            if let cached = cachedSystemPrompt { return cached }
            let value = AppDefaults.systemPrompt.wrappedValue
            cachedSystemPrompt = value
            return value
        }
        set {
            cachedSystemPrompt = newValue
            AppDefaults.systemPrompt.wrappedValue = newValue
        }
    }

    /// Batch KV-cache update — writes both defaults together so callers
    /// (ProviderManager.kvCacheAuto) don't trigger two separate invalidations.
    /// Returns true if either value actually changed.
    @discardableResult
    func setKVCache(auto: Bool, maxTokens: Int) -> Bool {
        let autoChanged = AppDefaults.kvCacheAuto.wrappedValue != auto
        let tokensChanged = AppDefaults.maxNumTokens.wrappedValue != maxTokens
        guard autoChanged || tokensChanged else { return false }
        AppDefaults.kvCacheAuto.wrappedValue = auto
        AppDefaults.maxNumTokens.wrappedValue = maxTokens
        return true
    }

    /// Drop in-memory caches (e.g. after AppDefaults.resetAll()).
    func invalidateCache() {
        cachedTemperature = nil
        cachedSystemPrompt = nil
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
