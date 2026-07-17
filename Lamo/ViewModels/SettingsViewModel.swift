import Foundation
import LiteRTLM
import SwiftUI

/// ViewModel for the settings screen. Manages all LiteRT-LM parameters.
@MainActor
@Observable
final class SettingsViewModel {
    private let providerManager = ProviderManager.shared

    // MARK: - Engine Settings

    var useGPU: Bool {
        get { AppDefaults.useGPU.wrappedValue }
        set { AppDefaults.useGPU.wrappedValue = newValue }
    }

    var cpuThreadCount: Int {
        get { AppDefaults.cpuThreadCount.wrappedValue }
        set { AppDefaults.cpuThreadCount.wrappedValue = newValue }
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
        get { AppDefaults.maxNumTokens.wrappedValue }
        set { AppDefaults.maxNumTokens.wrappedValue = newValue }
    }

    /// Whether KV-cache is set to auto (use model default).
    var kvCacheAuto: Bool {
        get { AppDefaults.kvCacheAuto.wrappedValue }
        set {
            AppDefaults.kvCacheAuto.wrappedValue = newValue
            if newValue {
                // Set a very high value to signal "unlimited"
                AppDefaults.maxNumTokens.wrappedValue = 0
            }
        }
    }

    // MARK: - Speculative Decoding

    var speculativeDecoding: Bool {
        get { AppDefaults.speculativeDecoding.wrappedValue }
        set { AppDefaults.speculativeDecoding.wrappedValue = newValue }
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

    // MARK: - Init

    init() {
        availableModels = ProviderManager.listModels()
    }

    // MARK: - Actions

    func refreshModels() {
        availableModels = ProviderManager.listModels()
    }

    func loadModelInfo() {
        guard let path = selectedModel else {
            modelInfo = nil
            return
        }
        modelInfo = ModelInfo.from(path: path)
    }

    func resetSamplerDefaults() {
        topK = 64
        topP = 0.95
        temperature = 1.0
    }

    func resetAllDefaults() {
        useGPU = true
        cpuThreadCount = 4
        kvCacheAuto = true
        topK = 64
        topP = 0.95
        temperature = 1.0
        maxNumTokens = 4096
        speculativeDecoding = true
        visualTokenBudget = 560
        memoryEnabled = true
        systemPrompt = AppDefaults.systemPrompt.defaultValue
    }

    /// Current SamplerConfig built from published values.
    func makeSamplerConfig() throws -> LiteRTLM.SamplerConfig {
        try LiteRTLM.SamplerConfig(
            topK: topK,
            topP: Float(topP),
            temperature: Float(temperature),
            seed: Int.random(in: 0..<Int(Int32.max))
        )
    }

    /// Human-readable model name from path.
    func displayName(for path: String) -> String {
        (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".litertlm", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Model Info

struct ModelInfo {
    let name: String
    let fileSize: Int64
    let hasSpeculativeDecoding: Bool

    static func from(path: String) -> ModelInfo? {
        let fileName = (path as NSString).lastPathComponent
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
            name: fileName.replacingOccurrences(of: ".litertlm", with: "")
                .replacingOccurrences(of: "-", with: " "),
            fileSize: fileSize,
            hasSpeculativeDecoding: hasSpecDecoding
        )
    }

    var fileSizeString: String {
        let gb = Double(fileSize) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(fileSize) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
