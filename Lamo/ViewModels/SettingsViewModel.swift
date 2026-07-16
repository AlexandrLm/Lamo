import Foundation
import LiteRTLM
import SwiftUI
import Combine

/// ViewModel for the settings screen. Manages all LiteRT-LM parameters.
@MainActor
final class SettingsViewModel: ObservableObject {
    private let defaults = UserDefaults.standard
    private let providerManager = ProviderManager.shared

    // MARK: - Engine Settings

    @Published var useGPU: Bool {
        didSet { defaults.set(useGPU, forKey: "litertLMUseGPU") }
    }

    @Published var cpuThreadCount: Int {
        didSet { defaults.set(cpuThreadCount, forKey: "litertLMCpuThreadCount") }
    }

    // MARK: - Model

    @Published var selectedModel: String? {
        didSet { providerManager.litertLMModelPath = selectedModel }
    }

    @Published var availableModels: [String] = []

    // MARK: - Sampler

    @Published var topK: Int {
        didSet { defaults.set(topK, forKey: "litertLMTopK") }
    }

    @Published var topP: Double {
        didSet { defaults.set(topP, forKey: "litertLMTopP") }
    }

    @Published var temperature: Double {
        didSet { defaults.set(temperature, forKey: "litertLMTemperature") }
    }

    // MARK: - KV-Cache

    @Published var maxNumTokens: Int {
        didSet { defaults.set(maxNumTokens, forKey: "litertLMMaxNumTokens") }
    }

    /// Whether KV-cache is set to auto (use model default).
    @Published var kvCacheAuto: Bool {
        didSet {
            defaults.set(kvCacheAuto, forKey: "litertLMKvCacheAuto")
            if kvCacheAuto {
                // Set a very high value to signal "unlimited"
                defaults.set(0, forKey: "litertLMMaxNumTokens")
            }
        }
    }

    // MARK: - Speculative Decoding

    @Published var speculativeDecoding: Bool {
        didSet { defaults.set(speculativeDecoding, forKey: "litertLMSpeculativeDecoding") }
    }

    // MARK: - Vision

    @Published var visualTokenBudget: Int {
        didSet { defaults.set(visualTokenBudget, forKey: "litertLMVisualTokenBudget") }
    }

    // MARK: - System Prompt

    @Published var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: "litertLMSystemPrompt") }
    }

    // MARK: - Memory

    @Published var memoryEnabled: Bool {
        didSet {
            MemoryService.shared.isEnabled = memoryEnabled
        }
    }

    // MARK: - Model Info

    @Published var modelInfo: ModelInfo?

    // MARK: - Init

    init() {
        self.useGPU = defaults.object(forKey: "litertLMUseGPU") as? Bool ?? true
        self.cpuThreadCount = defaults.object(forKey: "litertLMCpuThreadCount") as? Int ?? 4
        self.selectedModel = providerManager.litertLMModelPath
        self.topK = defaults.object(forKey: "litertLMTopK") as? Int ?? 64
        self.topP = defaults.object(forKey: "litertLMTopP") as? Double ?? 0.95
        self.temperature = defaults.object(forKey: "litertLMTemperature") as? Double ?? 1.0
        self.maxNumTokens = defaults.object(forKey: "litertLMMaxNumTokens") as? Int ?? 4096
        self.kvCacheAuto = defaults.object(forKey: "litertLMKvCacheAuto") as? Bool ?? true
        self.speculativeDecoding = defaults.object(forKey: "litertLMSpeculativeDecoding") as? Bool ?? true
        self.visualTokenBudget = defaults.object(forKey: "litertLMVisualTokenBudget") as? Int ?? 560
        self.systemPrompt = defaults.string(forKey: "litertLMSystemPrompt") ?? "You are a helpful assistant. Answer in the user's language. Use markdown formatting when appropriate. You have tools: web_search, fetch_url, deep_research, update_memory. When you need information — call tools immediately, never promise to check later. When the user shares a URL — always fetch it first."
        self.memoryEnabled = defaults.object(forKey: "memoryEnabled") as? Bool ?? true
        refreshModels()
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
        systemPrompt = "You are a helpful assistant. Answer in the user's language. Use markdown formatting when appropriate. You have tools: web_search, fetch_url, deep_research, update_memory. When you need information — call tools immediately, never promise to check later. When the user shares a URL — always fetch it first."
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
