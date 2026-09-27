import Foundation
import LiteRTLM
import SwiftUI
import os

/// ViewModel for the settings screen. Manages all LiteRT-LM parameters.
@MainActor
@Observable
final class SettingsViewModel {
    private let providerManager = ProviderManager.shared

    // MARK: - Provider

    var selectedProvider: ProviderType {
        get { providerManager.selectedProviderType }
        set { providerManager.selectedProviderType = newValue }
    }

    var availableProviders: [ProviderType] { providerManager.availableProviders }

    var isLiteRTSelected: Bool { selectedProvider == .litertLM }

    var foundationModelsUnavailableReason: String? {
        providerManager.foundationModelsUnavailableReason
    }

    // MARK: - Engine Settings

    var useGPU: Bool {
        get { providerManager.litertLMUseGPU }
        set { providerManager.litertLMUseGPU = newValue }
    }

    var cpuThreadCount: Int {
        get { providerManager.cpuThreadCount }
        set { providerManager.cpuThreadCount = newValue }
    }

    // MARK: - Model

    var selectedModel: String? {
        get { providerManager.litertLMModelPath }
        set { providerManager.litertLMModelPath = newValue }
    }

    var availableModels: [String] = []

    // MARK: - Sampler

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

    // MARK: - KV-Cache

    var maxNumTokens: Int {
        get { providerManager.maxNumTokens }
        set { providerManager.maxNumTokens = newValue }
    }

    var kvCacheAuto: Bool {
        get { providerManager.kvCacheAuto }
        set { providerManager.kvCacheAuto = newValue }
    }

    // MARK: - Speculative Decoding

    var speculativeDecoding: Bool {
        get { providerManager.speculativeDecoding }
        set { providerManager.speculativeDecoding = newValue }
    }

    // MARK: - Vision

    var visualTokenBudget: Int {
        get { AppDefaults.visualTokenBudget.wrappedValue }
        set { AppDefaults.visualTokenBudget.wrappedValue = newValue }
    }

    // MARK: - System Prompt

    var systemPrompt: String {
        get { AppDefaults.systemPrompt.wrappedValue }
        set { AppDefaults.systemPrompt.wrappedValue = newValue }
    }

    // MARK: - Memory

    var memoryEnabled: Bool {
        get { AppDefaults.memoryEnabled.wrappedValue }
        set {
            AppDefaults.memoryEnabled.wrappedValue = newValue
            MemoryService.shared.isEnabled = newValue
        }
    }

    // MARK: - Model Info

    var modelInfo: ModelInfo?

    /// Coalescing task for info loads — rapid model switches cancel the previous load.
    /// NOTE(debounce): callers fire loadModelInfo() on every selection tap; the guard
    /// below cancels the in-flight Task.detached before starting a new one.
    private var modelInfoTask: Task<Void, Never>?

    /// Shared cache — Capabilities(modelPath:) + stat hit disk + native init.
    /// Lock-protected value storage: `OSLock` is not callable from async contexts.
    private static let modelInfoCache = OSAllocatedUnfairLock(
        initialState: [String: ModelInfo]()
    )

    // MARK: - Init

    init() {
        availableModels = ProviderManager.listModels()
    }

    // MARK: - Actions

    func refreshModels() {
        availableModels = ProviderManager.listModels()
    }

    func loadModelInfo() {
        modelInfoTask?.cancel()
        guard let path = selectedModel else {
            modelInfo = nil
            return
        }
        let cached = Self.modelInfoCache.withLock { $0[path] }
        if let cached {
            modelInfo = cached
            return
        }
        // Heavy IO (stat + Capabilities init) off the main actor.
        // Outer Task inherits @MainActor (may touch self); inner detached
        // does only Sendable work (path String -> ModelInfo value).
        let pathCopy = path
        modelInfoTask = Task { [weak self] in
            let info = await Task.detached { ModelInfo.from(path: pathCopy) }.value
            guard let self, !Task.isCancelled else { return }
            guard let info else { return }
            Self.modelInfoCache.withLock { $0[pathCopy] = info }
            // Ignore stale results after a rapid re-selection.
            guard self.selectedModel == pathCopy else { return }
            self.modelInfo = info
        }
    }

    func resetSamplerDefaults() {
        topK = 64
        topP = 0.95
        temperature = 1.0
    }

    func resetAllDefaults() {
        AppDefaults.resetAll()
        // Sync instance state that mirrors AppDefaults via ProviderManager
        useGPU = true
        cpuThreadCount = 4
        kvCacheAuto = true
        maxNumTokens = 4096
        speculativeDecoding = true
        memoryEnabled = true
        // Reload model info after path reset
        loadModelInfo()
    }


    /// Human-readable model name from path.
    func displayName(for path: String) -> String {
        ProviderManager.displayName(forModelPath: path)
    }
}

// MARK: - Model Info

nonisolated struct ModelInfo: Hashable, Sendable {
    let name: String
    let fileSize: Int64
    let hasSpeculativeDecoding: Bool

    nonisolated static func from(path: String) -> ModelInfo? {
        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        let caps = LiteRTLM.Capabilities(modelPath: path)
        let hasSpecDecoding = caps?.hasSpeculativeDecodingSupport() ?? false

        return ModelInfo(
            name: ModelDiscovery.displayName(forModelPath: path),
            fileSize: fileSize,
            hasSpeculativeDecoding: hasSpecDecoding
        )
    }

    var fileSizeString: String {
        let gb = Double(fileSize) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: String(localized: "%.2f GB"), gb)
        }
        let mb = Double(fileSize) / 1_048_576
        return String(format: String(localized: "%.0f MB"), mb)
    }
}
