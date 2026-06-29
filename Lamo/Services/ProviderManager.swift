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
    /// Uses os_proc_available_memory() for real-time data.
    /// Adaptive: scales KV-cache to fit available RAM with safety margin.
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

        // Safety factor: leave headroom for engine internals + system pressure
        // < 1.5 GB: critical → 25%
        // < 3 GB:   tight   → 35%
        // < 5 GB:   normal  → 45%
        // >= 5 GB:  comfort → 55%
        let safetyFactor: Double
        if availableMB < 1500 {
            safetyFactor = 0.25
        } else if availableMB < 3000 {
            safetyFactor = 0.35
        } else if availableMB < 5000 {
            safetyFactor = 0.45
        } else {
            safetyFactor = 0.55
        }

        // Each 1024 tokens of KV-cache ≈ 300 MB for Gemma-4-class models
        let usableMB = availableMB * safetyFactor
        let maxTokensFromMemory = max(256, Int(usableMB / 300.0 * 1024))

        let requested: Int
        if kvCacheAuto {
            // Auto: use as much as memory allows (no fixed cap)
            requested = maxTokensFromMemory
        } else {
            requested = maxNumTokens > 0 ? maxNumTokens : 1024
        }

        let capped = min(requested, maxTokensFromMemory)

        // Round down to nearest 256 (clean KV-cache blocks)
        let result = (capped / 256) * 256
        print("[Lamo] safeMaxTokens: available=\(String(format: "%.0f", availableMB))MB, safety=\(Int(safetyFactor * 100))%, usable=\(String(format: "%.0f", usableMB))MB, maxFromMem=\(maxTokensFromMemory), requested=\(requested), result=\(result)")
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

        // Free up memory before loading — model is mmap'd but engine still
        // needs working RAM for KV-cache, tokenizer, and execution buffers.
        performPreloadCleanup()

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
        // Use os_proc_available_memory() instead of physicalMemory — accounts for other apps.
        // Thresholds are conservative but realistic for mmap'd models:
        // the engine maps the file into virtual address space, only loading
        // pages on demand — so we don't need the full model size in RAM.
        let filename = (resolvedPath as NSString).lastPathComponent
        if let preset = PresetModel.allCases.first(where: { $0.filename == filename }) {
            #if os(iOS)
            let availableMB = Double(os_proc_available_memory()) / 1_048_576
            #else
            let availableMB = Double(ProcessInfo.processInfo.physicalMemory) / 2.0 / 1_048_576
            #endif
            let requiredMB: Double
            switch preset {
            case .gemma4E4B: requiredMB = 2000  // 2 GB — mmap'd model, only KV-cache + buffers loaded
            case .gemma4E2B: requiredMB = 1200  // 1.2 GB — smaller model, less KV-cache
            }
            if availableMB < requiredMB {
                // Try to free memory before giving up
                print("[Lamo] Low memory (\(String(format: "%.0f", availableMB))MB), attempting cleanup...")
                performPreloadCleanup()
                // Re-check after cleanup
                let newAvailableMB = Double(os_proc_available_memory()) / 1_048_576
                if newAvailableMB < requiredMB {
                    let availGB = String(format: "%.1f", newAvailableMB / 1024)
                    let reqGB = String(format: "%.1f", requiredMB / 1024)
                    engineError = "Only \(availGB) GB RAM available but \(preset.displayName) needs ~\(reqGB) GB.\n\nTry:\n• Close other apps (especially Safari, Instagram, games)\n• Restart Lamo after closing apps\n• Use \(PresetModel.gemma4E2B.displayName) instead"
                    return
                }
                print("[Lamo] Cleanup freed memory: \(String(format: "%.0f", newAvailableMB))MB now available")
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
            visionBackend: .cpu(),
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
        // Release existing engine memory before invalidating
        if let provider = cachedProvider as? LiteRTLMProvider {
            provider.invalidateConversationCache()
        }
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

    // MARK: - Memory Cleanup

    /// Aggressive cleanup before engine load — frees everything we can
    /// so the OS has maximum contiguous memory for the mmap'd model.
    private func performPreloadCleanup() {
        // 1. Release URL cache (Safari, image downloads, etc.)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0

        // 2. Release any cached conversation data
        if let provider = cachedProvider as? LiteRTLMProvider {
            provider.invalidateConversationCache()
        }

        // 3. Release the old engine (if switching models)
        cachedEngine = nil
        cachedProvider = nil

        // 4. Drain autorelease pools
        autoreleasepool { }

        // 5. Clear any temporary files that might hold memory
        let tmp = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ) {
            for file in contents where file.lastPathComponent.hasPrefix("litert") {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // 6. Memory pressure trick: allocate a large block to force iOS
        //    to evict cached pages from other apps, then release it.
        //    The freed physical RAM is now available for our model.
        #if os(iOS)
        let availableBefore = os_proc_available_memory() / 1_048_576
        let targetMB = max(500, Int(availableBefore) / 3)  // Try to reclaim ~33% of available
        performMemoryPressureTrunc(targetMB: min(targetMB, 2000))  // Cap at 2 GB
        let availableAfter = os_proc_available_memory() / 1_048_576
        print("[Lamo] Preload cleanup: \(availableBefore)MB → \(availableAfter)MB (freed \(availableAfter - availableBefore)MB)")
        #else
        print("[Lamo] Preload cleanup done (macOS — pressure trick skipped)")
        #endif
    }

    /// Allocate a large anonymous block, touch every page, then release it.
    /// This forces iOS to evict cached pages from other apps (Safari, etc.)
    /// to make room for our allocation. When we free it, that physical RAM
    /// becomes available for the model.
    ///
    /// Uses madvise(MADV_DONTNEED) before munmap to ensure pages are
    /// actually released rather than kept in the free list.
    private func performMemoryPressureTrunc(targetMB: Int) {
        let targetBytes = targetMB * 1024 * 1024
        guard let ptr = mmap(nil, targetBytes, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0),
              ptr != MAP_FAILED else {
            print("[Lamo] Pressure trick: mmap failed for \(targetMB)MB")
            return
        }

        // Touch every page to force it into physical RAM
        // (mmap pages are lazy — they don't consume RAM until touched)
        let buffer = ptr.bindMemory(to: UInt8.self, capacity: targetBytes)
        let pageSize = 4096
        for offset in stride(from: 0, to: targetBytes, by: pageSize) {
            buffer[offset] = 1
        }

        // Tell the kernel we no longer need these pages
        // MADV_DONTNEED: pages are discarded immediately (not just marked lazy)
        madvise(ptr, targetBytes, MADV_DONTNEED)

        // Free the virtual address space
        munmap(ptr, targetBytes)
        print("[Lamo] Pressure trick: allocated/touched/released \(targetMB)MB")
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
