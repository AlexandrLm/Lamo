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

    /// Safe max tokens based on ACTUAL available memory at runtime.
    /// Uses os_proc_available_memory() for real-time data, not heuristics.
    private func safeMaxTokens(modelPath: String) -> Int? {
        // Get real available memory from the OS (iOS 13+)
        let availableBytes: UInt64
        #if os(iOS)
        availableBytes = UInt64(os_proc_available_memory())
        #else
        // Fallback for macOS/simulator: physical RAM minus conservative estimate
        availableBytes = ProcessInfo.processInfo.physicalMemory / 2
        #endif

        let availableMB = Double(availableBytes) / (1024 * 1024)

        // Each 1024 tokens of KV-cache ≈ 300 MB for Gemma-4-class models
        // Use 70% of available memory (conservative — leave room for system + engine)
        let usableMB = availableMB * 0.7
        let maxTokensFromMemory = max(256, Int(usableMB / 300.0 * 1024))

        let requested: Int
        if kvCacheAuto {
            requested = 4096
        } else {
            requested = maxNumTokens > 0 ? maxNumTokens : 4096
        }

        let capped = min(requested, maxTokensFromMemory)

        // Round down to nearest 256
        let result = (capped / 256) * 256
        print("[Lamo] safeMaxTokens: available=\(String(format: "%.0f", availableMB))MB, usable=\(String(format: "%.0f", usableMB))MB, maxFromMem=\(maxTokensFromMemory), result=\(result)")
        return result
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
    /// Always returns a **cached** provider — never creates a new one on the fly.
    /// Returns AppleIntelligenceProvider as fallback when LiteRT-LM engine isn't ready yet.
    var currentProvider: any LLMProvider {
        switch selectedProvider {
        case .appleIntelligence:
            return AppleIntelligenceProvider()
        case .litertLM:
            if let cached = cachedProvider {
                return cached
            }
            // Engine not ready yet — return Apple Intelligence as placeholder.
            // This prevents creating an engine-less LiteRTLMProvider that would
            // try to load the model synchronously on the first message send.
            return AppleIntelligenceProvider()
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
        if let path = Self.resolveModelPath(custom: litertLMModelPath) {
            resolvedPath = path
        } else if litertLMModelPath != nil {
            engineError = "Model file not found: \(litertLMModelPath!)"
            return
        } else {
            engineError = "No .litertlm model found in ~/Documents/models/"
            return
        }

        // Pre-flight: check available disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? UInt64 {
            let freeGB = Double(freeBytes) / 1_073_741_824
            if freeGB < 1.0 {
                engineError = "Not enough storage. Free up at least 1 GB."
                return
            }
        }

        // Pre-flight: validate model file size (corrupted files cause C++ null crashes)
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
           let fileSize = fileAttrs[.size] as? Int64 {
            let fileSizeGB = Double(fileSize) / 1_073_741_824
            if fileSizeGB < 0.5 {
                engineError = "Model file too small (\(String(format: "%.2f", fileSizeGB)) GB). Re-download the model."
                return
            }
            // E4B should be ~3.66 GB, E2B ~2 GB — flag if suspiciously small
            if fileSizeGB < 1.5 {
                engineError = "Model file appears incomplete (\(String(format: "%.2f", fileSizeGB)) GB). Re-download recommended."
                return
            }
        }

        // Pre-flight: check if device has enough AVAILABLE RAM for this model
        // Use os_proc_available_memory() instead of physicalMemory — accounts for other apps
        let filename = (resolvedPath as NSString).lastPathComponent
        if let preset = PresetModel.allCases.first(where: { $0.filename == filename }) {
            #if os(iOS)
            let availableMB = Double(os_proc_available_memory()) / 1_048_576
            #else
            let availableMB = Double(ProcessInfo.processInfo.physicalMemory) / 2.0 / 1_048_576
            #endif
            let requiredMB: Double
            switch preset {
            case .gemma4E4B: requiredMB = 5500  // 5.5 GB available needed
            case .gemma4E2B: requiredMB = 2500  // 2.5 GB available needed
            }
            if availableMB < requiredMB {
                let availGB = String(format: "%.1f", availableMB / 1024)
                let reqGB = String(format: "%.1f", requiredMB / 1024)
                engineError = "Only \(availGB) GB RAM available but \(preset.displayName) needs ~\(reqGB) GB. Close other apps or use \(PresetModel.gemma4E2B.displayName)."
                return
            }
        }

        // Enable speculative decoding experimental flag if requested
        if speculativeDecoding {
            do {
                LiteRTLM.ExperimentalFlags.optIntoExperimentalAPIs()
                LiteRTLM.ExperimentalFlags.enableSpeculativeDecoding = true
            } catch {
                // Non-fatal: continue without speculative decoding
                print("[Lamo] Failed to enable speculative decoding: \(error)")
            }
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
            print("[Lamo] Initializing engine for: \(filename), backend=\(litertLMUseGPU ? "GPU" : "CPU"), maxTokens=\(maxTokens ?? -1)")
            try await engine.initialize()
            print("[Lamo] Engine initialized successfully")
        } catch {
            print("[Lamo] Engine init FAILED: \(error)")
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

    /// The models directory: ~/Documents/models/
    static var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models")
    }

    /// Resolves a model path: checks the custom path directly, then in modelsDirectory, or falls back to first available model.
    static func resolveModelPath(custom: String? = nil) -> String? {
        if let custom = custom {
            // If it's a full path, check directly
            if FileManager.default.fileExists(atPath: custom) { return custom }
            // If it's just a filename, look in ~/Documents/models/
            let fullPath = modelsDirectory.appendingPathComponent(custom).path
            if FileManager.default.fileExists(atPath: fullPath) { return fullPath }
            return nil
        }
        return findFirstModel()
    }

    /// Finds the first .litertlm file in ~/Documents/models/.
    static func findFirstModel() -> String? {
        guard FileManager.default.fileExists(atPath: modelsDirectory.path) else { return nil }
        guard let first = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "litertlm" }) else { return nil }
        return first.path
    }

    /// Lists all .litertlm files in ~/Documents/models/.
    static func listModels() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "litertlm" }
            .map { $0.lastPathComponent }
    }
}
