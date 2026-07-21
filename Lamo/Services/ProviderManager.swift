import Foundation
import LiteRTLM
import Combine
import os
/// Thin coordinator that delegates to focused sub-types.
///
/// - ModelSettings:  UserDefaults-backed settings
/// - TokenBudget:    safeMaxTokens, tokenization, token cache
/// - EngineLifecycle: engine init, retry, invalidation, memory pressure
/// - ModelDiscovery: model path resolution, listing, display names
@MainActor
final class ProviderManager: ObservableObject {
    static let shared = ProviderManager()

    // MARK: - Sub-components

    let settings = ModelSettings()
    let tokenBudget = TokenBudget()
    private lazy var lifecycle = EngineLifecycle(
        settings: settings,
        tokenBudget: tokenBudget,
        onEngineReadyChanged: { [weak self] in self?.isEngineReady = $0 },
        onEngineErrorChanged: { [weak self] in self?.engineError = $0 },
        onMemoryPressureChanged: { [weak self] in self?.isMemoryPressure = $0 }
    )

    // MARK: - Published State

    @Published var isEngineReady: Bool = false
    @Published var engineError: LamoError?
    var engineErrorMessage: String? { engineError?.errorDescription }

    var braveAPIKey: String? {
        KeychainHelper.load(key: "brave_search_api_key")
    }

    @Published var isMemoryPressure: Bool = false

    var currentMaxTokens: Int? { lifecycle.currentMaxTokens }

    @Published var lastToolTokens: Int = 0
    @Published var lastToolCount: Int = 0
    @Published var lastToolCountTotal: Int = 0

    // MARK: - Engine accessors

    var engineForSummarization: LiteRTLM.Engine? { lifecycle.engineForSummarization }
    var currentProvider: any LLMProvider { lifecycle.currentProvider }

    // MARK: - Token Budget (forwarding)

    func tokenizeCount(_ text: String) async -> Int {
        await tokenBudget.tokenizeCount(text, engine: lifecycle.engineForSummarization)
    }

    func tokenizeMessages(_ messages: [ChatMessage]) async -> [UUID: Int] {
        await tokenBudget.tokenizeMessages(messages, engine: lifecycle.engineForSummarization)
    }

    func clearTokenCache() {
        tokenBudget.clearTokenCache()
    }

    // MARK: - Lifecycle (forwarding)

    func initializeEngineIfNeeded() async {
        await lifecycle.initializeEngineIfNeeded()
    }

    func invalidateEngine() {
        lifecycle.invalidateEngine()
    }

    func reloadEngine() {
        lifecycle.reloadEngine()
    }

    func switchModel(modelPath: String) {
        lifecycle.switchModel(modelPath: modelPath)
    }

    // MARK: - Settings (with validation + invalidation)

    var litertLMModelPath: String? {
        get { settings.litertLMModelPath }
        set {
            if let newValue = newValue {
                if newValue.contains("/") {
                    if !newValue.hasSuffix(".litertlm") {
                        LamoLogger.engine.warning("Model path '\(newValue)' doesn't end in .litertlm")
                    } else if !FileManager.default.fileExists(atPath: newValue) {
                        LamoLogger.engine.warning("Model file not found at '\(newValue)'")
                    }
                } else {
                    let fullPath = ModelDiscovery.modelsDirectory.appendingPathComponent(newValue).path
                    if !FileManager.default.fileExists(atPath: fullPath) {
                        LamoLogger.engine.warning("Model '\(newValue)' not found in models directory")
                    }
                }
            }
            settings.litertLMModelPath = newValue
            if !lifecycle.suppressInvalidation { invalidateEngine() }
        }
    }

    var litertLMUseGPU: Bool {
        get { settings.litertLMUseGPU }
        set {
            settings.litertLMUseGPU = newValue
            invalidateEngine()
        }
    }

    var cpuThreadCount: Int {
        get { settings.cpuThreadCount }
        set {
            settings.cpuThreadCount = newValue
            invalidateEngine()
        }
    }

    var topK: Int {
        get { settings.topK }
        set { settings.topK = newValue }
    }

    var topP: Double {
        get { settings.topP }
        set { settings.topP = newValue }
    }

    var temperature: Double {
        get { settings.temperature }
        set { settings.temperature = newValue }
    }

    var maxNumTokens: Int {
        get { settings.maxNumTokens }
        set {
            settings.maxNumTokens = newValue
            invalidateEngine()
        }
    }

    var kvCacheAuto: Bool {
        get { settings.kvCacheAuto }
        set {
            settings.kvCacheAuto = newValue
            if newValue {
                settings.maxNumTokens = 0
            } else if settings.maxNumTokens == 0 {
                settings.maxNumTokens = 4096
            }
            invalidateEngine()
        }
    }

    var speculativeDecoding: Bool {
        get { settings.speculativeDecoding }
        set {
            settings.speculativeDecoding = newValue
            invalidateEngine()
        }
    }

    var visualTokenBudget: Int {
        get { settings.visualTokenBudget }
        set { settings.visualTokenBudget = newValue }
    }

    var systemPrompt: String {
        get { settings.systemPrompt }
        set { settings.systemPrompt = newValue }
    }

    @Published var thinkingMode: Bool = AppDefaults.thinkingMode.wrappedValue {
        didSet { settings.thinkingMode = thinkingMode }
    }

    var defaultSystemPrompt: String { settings.defaultSystemPrompt }

    // MARK: - Model Discovery (forwarding)

    var currentModelDisplayName: String {
        guard let path = litertLMModelPath ?? ModelDiscovery.findFirstModel() else { return "" }
        return ModelDiscovery.displayName(forModelPath: path)
    }

    static var modelsDirectory: URL { ModelDiscovery.modelsDirectory }
    static func displayName(forModelPath path: String) -> String { ModelDiscovery.displayName(forModelPath: path) }
    static func resolveModelPath(custom: String? = nil) -> String? { ModelDiscovery.resolveModelPath(custom: custom) }
    static func findFirstModel() -> String? { ModelDiscovery.findFirstModel() }
    static func listModels() -> [String] { ModelDiscovery.listModels() }
}
