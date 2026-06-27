import Foundation
import LiteRTLM
import Combine

/// Available LLM providers in the app.
enum ProviderType: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple"
    case litertLM = "litertlm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .litertLM: return "On-Device AI"
        }
    }

    var icon: String {
        switch self {
        case .appleIntelligence: return "apple.logo"
        case .litertLM: return "cpu"
        }
    }
}

/// Manages the active LLM provider, engine lifecycle, and shared ChatService.
///
/// Responsibilities:
/// - Caches the LiteRT-LM engine (loaded once, reused across conversations)
/// - Invalidates cache when model path or GPU setting changes
/// - Provides a shared ChatService that reuses the same provider
/// - Notifies observers when engine state changes
@MainActor
final class ProviderManager: ObservableObject {
    static let shared = ProviderManager()

    // MARK: - Published State

    /// Whether the engine is currently loaded and ready.
    @Published var isEngineReady: Bool = false

    /// Error message if engine initialization failed.
    @Published var engineError: String?

    // MARK: - Settings (persisted via UserDefaults)

    var selectedProvider: ProviderType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "selectedProvider"),
                  let type = ProviderType(rawValue: raw) else { return .litertLM }
            return type
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedProvider")
            invalidateEngine()
        }
    }

    var litertLMModelPath: String? {
        get { UserDefaults.standard.string(forKey: "litertLMModelPath") }
        set {
            UserDefaults.standard.set(newValue, forKey: "litertLMModelPath")
            invalidateEngine()
        }
    }

    var litertLMUseGPU: Bool {
        get { UserDefaults.standard.object(forKey: "litertLMUseGPU") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "litertLMUseGPU")
            invalidateEngine()
        }
    }

    var cpuThreadCount: Int {
        get { UserDefaults.standard.object(forKey: "litertLMCpuThreadCount") as? Int ?? 4 }
        set {
            UserDefaults.standard.set(newValue, forKey: "litertLMCpuThreadCount")
            invalidateEngine()
        }
    }

    var topK: Int {
        get { UserDefaults.standard.object(forKey: "litertLMTopK") as? Int ?? 40 }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMTopK") }
    }

    var topP: Double {
        get { UserDefaults.standard.object(forKey: "litertLMTopP") as? Double ?? 0.95 }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMTopP") }
    }

    var temperature: Double {
        get { UserDefaults.standard.object(forKey: "litertLMTemperature") as? Double ?? 0.7 }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMTemperature") }
    }

    var maxNumTokens: Int {
        get { UserDefaults.standard.object(forKey: "litertLMMaxNumTokens") as? Int ?? 4096 }
        set {
            UserDefaults.standard.set(newValue, forKey: "litertLMMaxNumTokens")
            invalidateEngine()
        }
    }

    var speculativeDecoding: Bool {
        get { UserDefaults.standard.object(forKey: "litertLMSpeculativeDecoding") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "litertLMSpeculativeDecoding")
            invalidateEngine()
        }
    }

    var visualTokenBudget: Int {
        get { UserDefaults.standard.object(forKey: "litertLMVisualTokenBudget") as? Int ?? 560 }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMVisualTokenBudget") }
    }

    var systemPrompt: String {
        get { UserDefaults.standard.string(forKey: "litertLMSystemPrompt") ?? "You are a helpful, concise assistant. Answer in the same language the user writes in." }
        set { UserDefaults.standard.set(newValue, forKey: "litertLMSystemPrompt") }
    }

    // MARK: - Internal State

    /// Cached engine. Nil when invalidated or not yet loaded.
    private var cachedEngine: LiteRTLM.Engine?

    /// The provider wrapping the cached engine.
    private var cachedProvider: (any LLMProvider)?

    /// Shared chat service that reuses the cached provider.
    private(set) lazy var chatService: ChatService = {
        ChatService(provider: currentProvider)
    }()

    /// Debounce: prevents rapid re-initialization when settings change quickly.
    private var invalidateTask: Task<Void, Never>?

    /// The currently active provider (Apple Intelligence or LiteRT-LM).
    var currentProvider: any LLMProvider {
        switch selectedProvider {
        case .appleIntelligence:
            return AppleIntelligenceProvider()
        case .litertLM:
            if let cached = cachedProvider {
                return cached
            }
            // Fallback: create provider without engine (will create engine on first inference)
            return LiteRTLMProvider(
                modelPath: litertLMModelPath,
                useGPU: litertLMUseGPU,
                engine: nil
            )
        }
    }

    // MARK: - Engine Lifecycle

    /// Initializes and caches the engine. Safe to call multiple times —
    /// subsequent calls return immediately if already loaded.
    func initializeEngineIfNeeded() async {
        guard selectedProvider == .litertLM else {
            isEngineReady = true  // Apple Intelligence doesn't need engine
            return
        }
        guard cachedEngine == nil else {
            isEngineReady = true
            return
        }

        engineError = nil
        isEngineReady = false

        let resolvedPath: String
        if let custom = litertLMModelPath {
            guard FileManager.default.fileExists(atPath: custom) else {
                engineError = "Model file not found: \(custom)"
                return
            }
            resolvedPath = custom
        } else {
            guard let path = Self.findFirstModel() else {
                engineError = "No .litertlm model found in ~/Documents/models/"
                return
            }
            resolvedPath = path
        }

        // Enable speculative decoding experimental flag if requested
        if speculativeDecoding {
            LiteRTLM.ExperimentalFlags.optIntoExperimentalAPIs()
            LiteRTLM.ExperimentalFlags.enableSpeculativeDecoding = true
        }

        let backend: LiteRTLM.Backend
        if litertLMUseGPU {
            backend = .gpu
        } else {
            backend = .cpu(threadCount: cpuThreadCount)
        }

        let maxTokens = maxNumTokens > 0 ? maxNumTokens : nil

        guard let engineConfig = try? LiteRTLM.EngineConfig(
            modelPath: resolvedPath,
            backend: backend,
            visionBackend: nil,
            audioBackend: nil,
            maxNumTokens: maxTokens,
            cacheDir: NSTemporaryDirectory()
        ) else {
            engineError = "Failed to create engine config"
            return
        }

        let engine = LiteRTLM.Engine(engineConfig: engineConfig)
        do {
            try await engine.initialize()
        } catch {
            engineError = "Engine init failed: \(error.localizedDescription)"
            return
        }

        cachedEngine = engine
        let provider = LiteRTLMProvider(
            modelPath: litertLMModelPath,
            useGPU: litertLMUseGPU,
            engine: engine
        )
        cachedProvider = provider
        chatService = ChatService(provider: provider)
        isEngineReady = true
    }

    /// Invalidates the cached engine. Next inference will reload from disk.
    /// Called automatically when model path or GPU setting changes.
    /// Debounced: rapid changes within 300ms are coalesced.
    func invalidateEngine() {
        cachedEngine = nil
        cachedProvider = nil
        isEngineReady = false
        // Cancel any pending re-initialization
        invalidateTask?.cancel()
        // Re-initialize after 300ms debounce
        invalidateTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await initializeEngineIfNeeded()
        }
    }

    /// Force-reload the engine (e.g., after model download completes).
    func reloadEngine() {
        invalidateEngine()
    }

    // MARK: - Model Discovery

    /// Finds the first .litertlm file in ~/Documents/models/.
    static func findFirstModel() -> String? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        guard FileManager.default.fileExists(atPath: modelsDir.path) else { return nil }
        guard let first = try? FileManager.default.contentsOfDirectory(
            at: modelsDir, includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "litertlm" }) else { return nil }
        return first.path
    }

    /// Lists all .litertlm files in ~/Documents/models/.
    static func listModels() -> [String] {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "litertlm" }
            .map { $0.lastPathComponent }
    }
}
