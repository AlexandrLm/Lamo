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
    /// Whether the device is under memory pressure.
    @Published var isMemoryPressure: Bool = false

    // MARK: - Memory Pressure
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Available physical RAM in GB.
    private var physicalRAMGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    /// Safe max tokens based on model size and available RAM.
    /// Always applies a cap to prevent OOM, even when kvCacheAuto is on.
    private func safeMaxTokens(modelPath: String) -> Int? {
        let modelFileSize: Double
        if let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath),
           let size = attrs[.size] as? Int64 {
            modelFileSize = Double(size) / 1_073_741_824
        } else {
            modelFileSize = 2.0 // conservative default
        }

        // Rough heuristic: KV-cache ≈ 0.3 GB per 1024 tokens for E4B-class models
        // Leave 1.5 GB headroom for iOS + app overhead
        let availableForCache = physicalRAMGB - modelFileSize - 1.5
        let maxSafeTokens = max(1024, Int(availableForCache / 0.3 * 1024))

        let requested: Int
        if kvCacheAuto {
            // Auto mode: use a reasonable default, but still cap by memory
            requested = 4096
        } else {
            requested = maxNumTokens > 0 ? maxNumTokens : 4096
        }

        let capped = min(requested, maxSafeTokens)

        // Round down to nearest 256 for cleaner allocation
        return (capped / 256) * 256
    }

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

    var kvCacheAuto: Bool {
        get { UserDefaults.standard.object(forKey: "litertLMKvCacheAuto") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "litertLMKvCacheAuto")
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
            // If it's a full path, check directly
            if FileManager.default.fileExists(atPath: custom) {
                resolvedPath = custom
            } else {
                // If it's just a filename, look in ~/Documents/models/
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modelsDir = documents.appendingPathComponent("models")
                let fullPath = modelsDir.appendingPathComponent(custom).path
                guard FileManager.default.fileExists(atPath: fullPath) else {
                    engineError = "Model file not found: \(custom)"
                    return
                }
                resolvedPath = fullPath
            }
        } else {
            guard let path = Self.findFirstModel() else {
                engineError = "No .litertlm model found in ~/Documents/models/"
                return
            }
            resolvedPath = path
        }

        // Pre-flight: check available disk space (model needs ~2x file size for temp files)
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? UInt64 {
            let freeGB = Double(freeBytes) / 1_073_741_824
            if freeGB < 1.0 {
                engineError = "Not enough storage. Free up at least 1 GB."
                return
            }
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

        // Use safe token limit to prevent OOM on larger models
        let maxTokens = safeMaxTokens(modelPath: resolvedPath)

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

        // Start monitoring memory pressure after engine loads
        startMemoryPressureMonitoring()
    }

    // MARK: - Memory Pressure

    private func startMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isMemoryPressure = true
                // Release conversation cache to free memory
                if let provider = self.cachedProvider as? LiteRTLMProvider {
                    provider.invalidateConversationCache()
                }
            }
        }
        source.resume()
        memoryPressureSource = source
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
