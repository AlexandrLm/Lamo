import Foundation
import LiteRTLM
import Combine
import os


/// Manages the active LLM provider and engine lifecycle.
///
/// Responsibilities:
/// - Caches the LiteRT-LM engine (loaded once, reused across conversations)
/// - Invalidates cache when model path or GPU setting changes
/// - Notifies observers when engine state changes
@MainActor
final class ProviderManager: ObservableObject {
    static let shared = ProviderManager()

    // MARK: - Published State
    /// Whether the engine is currently loaded and ready.
    @Published var isEngineReady: Bool = false
    /// Current engine error (set after failed init).
    @Published var engineError: String?

    /// Brave Search API key (optional, falls back to DuckDuckGo).
    var braveAPIKey: String? {
        KeychainHelper.load(key: "brave_search_api_key")
    }
    /// Whether the device is under memory pressure.
    @Published var isMemoryPressure: Bool = false

    /// The actual safeMaxTokens value used for the current engine.
    /// Tracks the real KV-cache budget (not UserDefaults which may be 0 in auto mode).
    private(set) var currentMaxTokens: Int?

    // MARK: - Memory Pressure
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Tokenization cache — avoids re-tokenizing unchanged messages.
    /// Key: message content (String), Value: token count.
    /// State is held inside OSAllocatedUnfairLock for async-safe access.
    private let tokenCacheLock = OSAllocatedUnfairLock(initialState: [String: Int]())

    private func safeMaxTokens(modelPath: String) -> Int? {
        let availableBytes: UInt64
        #if os(iOS)
        availableBytes = UInt64(os_proc_available_memory())
        #else
        availableBytes = ProcessInfo.processInfo.physicalMemory / 2
        #endif

        let availableMB = Double(availableBytes) / (1024 * 1024)

        // Detect model size to estimate KV-cache memory per token
        let kvMBPer1K: Double
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: modelPath),
           let fileSize = fileAttrs[.size] as? Int64 {
            let fileSizeGB = Double(fileSize) / 1_073_741_824
            if litertLMUseGPU {
                // GPU: model weights loaded into GPU memory, KV-cache extra
                // E2B (2.6GB): ~280 MB/1K, E4B (3.7GB): ~600 MB/1K
                kvMBPer1K = fileSizeGB < 3.0 ? 280.0 : 600.0
            } else {
                // CPU: model heavily memory-mapped, more room for KV-cache
                kvMBPer1K = 150.0
            }
        } else {
            // Fallback: conservative GPU estimate
            kvMBPer1K = litertLMUseGPU ? 500.0 : 200.0
        }

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

        let usableMB = availableMB * safetyFactor
        let maxTokensFromMemory = max(512, Int(usableMB / kvMBPer1K * 1024))

        let requested: Int
        if kvCacheAuto {
            requested = maxTokensFromMemory
        } else {
            requested = maxNumTokens > 0 ? maxNumTokens : 1024
        }

        let capped = min(requested, maxTokensFromMemory)
        let result = (capped / 256) * 256
        LamoLogger.engine.debug("safeMaxTokens: kv=\(String(format: "%.0f", kvMBPer1K))MB/1K, available=\(String(format: "%.0f", availableMB))MB, safety=\(Int(safetyFactor*100))%, usable=\(String(format: "%.0f", usableMB))MB, maxFromMem=\(maxTokensFromMemory), requested=\(requested), result=\(result)")
        return result
    }

    // MARK: - Settings (persisted via AppDefaults)

    var litertLMModelPath: String? {
        get { AppDefaults.modelPath.wrappedValue }
        set {
            // #8: Validate model path before setting
            if let newValue = newValue {
                if newValue.contains("/") {
                    // Full path — must end in .litertlm and file should exist
                    if !newValue.hasSuffix(".litertlm") {
                        LamoLogger.engine.warning("Model path '\(newValue)' doesn't end in .litertlm")
                    } else if !FileManager.default.fileExists(atPath: newValue) {
                        LamoLogger.engine.warning("Model file not found at '\(newValue)'")
                    }
                } else {
                    // Filename (no slashes) — check in modelsDirectory
                    let fullPath = Self.modelsDirectory.appendingPathComponent(newValue).path
                    if !FileManager.default.fileExists(atPath: fullPath) {
                        LamoLogger.engine.warning("Model '\(newValue)' not found in models directory")
                    }
                }
            }
            AppDefaults.modelPath.wrappedValue = newValue
            if !suppressInvalidation { invalidateEngine() }
        }
    }

    var litertLMUseGPU: Bool {
        get { AppDefaults.useGPU.wrappedValue }
        set {
            AppDefaults.useGPU.wrappedValue = newValue
            invalidateEngine()
        }
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
        set {
            AppDefaults.maxNumTokens.wrappedValue = newValue
            invalidateEngine()
        }
    }

    var kvCacheAuto: Bool {
        get { AppDefaults.kvCacheAuto.wrappedValue }
        set {
            AppDefaults.kvCacheAuto.wrappedValue = newValue
            invalidateEngine()
        }
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

    /// Default system prompt that teaches the model to use markdown formatting.
    var defaultSystemPrompt: String {
        "You are a helpful assistant. Answer in the user's language. Use markdown formatting when appropriate. You have tools: web_search, fetch_url, update_memory. When you need information — call tools immediately, never promise to check later. When the user shares a URL — always fetch it first."
    }

    // MARK: - Internal State

    /// Cached engine. Nil when invalidated or not yet loaded.
    private var cachedEngine: LiteRTLM.Engine?

    /// Public read-only access to the cached engine (used by LiteRTLMProvider for summarization).
    var engineForSummarization: LiteRTLM.Engine? { cachedEngine }

    /// The provider wrapping the cached engine.
    private var cachedProvider: (any LLMProvider)?

    /// Tokenize a string using the engine's real tokenizer.
    /// Uses tokenization cache to avoid re-tokenizing identical strings.
    func tokenizeCount(_ text: String) async -> Int {
        let cached = tokenCacheLock.withLock { $0[text] }
        if let cached { return cached }

        guard let engine = cachedEngine else { return text.count / 4 }
        let count = (try? await engine.tokenize(text))?.count ?? (text.count / 4)

        tokenCacheLock.withLock { $0[text] = count }

        return count
    }

    /// Tokenize all messages and return per-message token counts.
    /// Uses cached token counts for unchanged messages.
    func tokenizeMessages(_ messages: [ChatMessage]) async -> [UUID: Int] {
        guard let engine = cachedEngine else {
            var fallback: [UUID: Int] = [:]
            for msg in messages { fallback[msg.id] = msg.content.count / 4 }
            return fallback
        }

        var counts: [UUID: Int] = [:]
        for msg in messages {
            let cached = tokenCacheLock.withLock { $0[msg.content] }
            if let cached {
                counts[msg.id] = cached
                continue
            }

            if let tokens = try? await engine.tokenize(msg.content) {
                let count = tokens.count
                counts[msg.id] = count
                tokenCacheLock.withLock { $0[msg.content] = count }
            } else {
                counts[msg.id] = msg.content.count / 4
            }
        }
        return counts
    }

    /// Clear tokenization cache (e.g., when engine changes).
    func clearTokenCache() {
        tokenCacheLock.withLock { $0.removeAll() }
    }

    /// Debounce: prevents rapid re-initialization when settings change quickly.
    private var invalidateTask: Task<Void, Never>?

    /// The currently active provider.
    /// Returns a cached provider if the engine is loaded, or a fallback
    /// that will produce a user-friendly error when no model is available.
    var currentProvider: any LLMProvider {
        if let cached = cachedProvider {
            return cached
        }
        // No engine loaded — return a stub that will yield .noModelAvailable.
        return LiteRTLMProvider(modelPath: litertLMModelPath)
    }

    // MARK: - Engine Lifecycle

    /// Initializes and caches the engine. Safe to call multiple times —
    /// subsequent calls return immediately if already loaded.
    func initializeEngineIfNeeded() async {
        guard cachedEngine == nil else {
            isEngineReady = true
            return
        }

        engineError = nil
        isEngineReady = false

        // #9: Start monitoring memory pressure BEFORE engine load
        // so memory pressure events during loading are caught immediately.
        startMemoryPressureMonitoring()

        // Free up memory before loading — model is mmap'd but engine still
        // needs working RAM for KV-cache, tokenizer, and execution buffers.
        performPreloadCleanup()

        let resolvedPath: String
        if let path = Self.resolveModelPath(custom: litertLMModelPath) {
            resolvedPath = path
        } else if litertLMModelPath != nil {
            engineError = LamoError.modelNotFound(litertLMModelPath!).errorDescription
            return
        } else {
            engineError = LamoError.noModelAvailable.errorDescription
            return
        }

        // Pre-flight: check available disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? UInt64 {
            let freeGB = Double(freeBytes) / 1_073_741_824
            if freeGB < 1.0 {
                engineError = LamoError.insufficientDiskSpace.errorDescription
                return
            }
        }

        // Pre-flight: validate model file size (corrupted files cause C++ null crashes)
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
           let fileSize = fileAttrs[.size] as? Int64 {
            let fileSizeGB = Double(fileSize) / 1_073_741_824
            if fileSizeGB < 0.5 {
                engineError = LamoError.modelTooSmall(fileSizeGB).errorDescription
                return
            }
            // E4B should be ~3.66 GB, E2B ~2 GB — flag if suspiciously small
            if fileSizeGB < 1.5 {
                engineError = LamoError.modelTooSmall(fileSizeGB).errorDescription
                return
            }
        }

        // #4: Pre-flight: validate model file magic bytes (detect corrupted/truncated files)
        if let fileHandle = FileHandle(forReadingAtPath: resolvedPath) {
            defer { fileHandle.closeFile() }
            let magicData = fileHandle.readData(ofLength: 4)
            if magicData.count == 4 {
                let bytes = [UInt8](magicData)
                if bytes == [0x00, 0x00, 0x00, 0x00] {
                    engineError = LamoError.modelCorrupted(resolvedPath).errorDescription
                    return
                }
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
                LamoLogger.engine.warning("Low memory (\(String(format: "%.0f", availableMB))MB), attempting cleanup...")
                performPreloadCleanup()
                // Re-check after cleanup
                let newAvailableMB = Double(os_proc_available_memory()) / 1_048_576
                if newAvailableMB < requiredMB {
                    let availGB = String(format: "%.1f", newAvailableMB / 1024)
                    let reqGB = String(format: "%.1f", requiredMB / 1024)
                    engineError = "Only \(availGB) GB RAM available but \(preset.displayName) needs ~\(reqGB) GB.\n\nTry:\n• Close other apps (especially Safari, Instagram, games)\n• Restart Lamo after closing apps\n• Use \(PresetModel.gemma4E2B.displayName) instead"
                    return
                }
                LamoLogger.engine.info("Cleanup freed memory: \(String(format: "%.0f", newAvailableMB))MB now available")
            }
        }

        // Enable experimental flags
        LiteRTLM.ExperimentalFlags.optIntoExperimentalAPIs()
        if speculativeDecoding {
            LiteRTLM.ExperimentalFlags.enableSpeculativeDecoding = true
        }
        LiteRTLM.ExperimentalFlags.enableBenchmark = true

        let backend: LiteRTLM.Backend
        if litertLMUseGPU {
            backend = .gpu
        } else {
            backend = .cpu(threadCount: cpuThreadCount)
        }

        let maxTokens = safeMaxTokens(modelPath: resolvedPath)
        currentMaxTokens = maxTokens

        // #2: Auto-retry engine creation + initialization (max 3 attempts)
        let maxAttempts = 3
        var lastEngineError = ""
        for attempt in 1...maxAttempts {
            if attempt > 1 {
                LamoLogger.engine.info("Engine init retry attempt \(attempt)/\(maxAttempts)...")
                try? await Task.sleep(for: .seconds(1))
            }

            guard let engineConfig = try? LiteRTLM.EngineConfig(
                modelPath: resolvedPath,
                backend: backend,
                visionBackend: .cpu(),
                audioBackend: nil,
                maxNumTokens: maxTokens,
                cacheDir: NSTemporaryDirectory()
            ) else {
                lastEngineError = LamoError.engineInitFailed("config creation").errorDescription ?? "Failed to create engine config"
                LamoLogger.engine.error("\(lastEngineError) (attempt \(attempt)/\(maxAttempts))")
                continue
            }

            let engine = LiteRTLM.Engine(engineConfig: engineConfig)
            do {
                LamoLogger.engine.info("Initializing engine for: \(filename), backend=\(self.litertLMUseGPU ? "GPU" : "CPU"), maxTokens=\(maxTokens ?? -1) (attempt \(attempt)/\(maxAttempts))")
                try await engine.initialize()
                LamoLogger.engine.info("Engine initialized successfully")

                cachedEngine = engine
                let provider = LiteRTLMProvider(
                    modelPath: litertLMModelPath,
                    useGPU: litertLMUseGPU,
                    maxNumTokens: maxTokens,
                    engine: engine
                )
                cachedProvider = provider
                isEngineReady = true
                // Restore URLCache that was cleared during preload cleanup
                restoreURLCache()
                return
            } catch {
                lastEngineError = LamoError.engineInitFailed(error.localizedDescription).errorDescription ?? "Engine init failed: \(error.localizedDescription)"
                LamoLogger.engine.error("\(lastEngineError) (attempt \(attempt)/\(maxAttempts))")
            }
        }
        engineError = lastEngineError
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
                self.clearTokenCache()
                // Auto-reset memory pressure after 30 seconds
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30))
                    self.isMemoryPressure = false
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
        currentMaxTokens = nil
        clearTokenCache()
        invalidateTask?.cancel()
        invalidateTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await initializeEngineIfNeeded()
        }
    }

    /// Atomically switch to a different model without double-invalidation.
    func switchModel(modelPath: String) {
        suppressInvalidation = true
        litertLMModelPath = modelPath
        suppressInvalidation = false
        invalidateEngine()
    }

    /// When true, property setters skip invalidation (used by switchModel).
    private var suppressInvalidation = false

    // MARK: - Memory Cleanup

    /// Original URLCache capacities — restored after engine loads.
    private var savedURLCacheMemory: Int = 0
    private var savedURLCacheDisk: Int = 0

    /// Aggressive cleanup before engine load — frees everything we can
    /// so the OS has maximum contiguous memory for the mmap'd model.
    private func performPreloadCleanup() {
        // Save and clear URLCache
        savedURLCacheMemory = URLCache.shared.memoryCapacity
        savedURLCacheDisk = URLCache.shared.diskCapacity
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0

        cachedEngine = nil
        cachedProvider = nil

        clearTokenCache()

        autoreleasepool { }

        let tmp = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ) {
            for file in contents where file.lastPathComponent.hasPrefix("litert") {
                try? FileManager.default.removeItem(at: file)
            }
        }

        #if os(iOS)
        let availableBefore = os_proc_available_memory() / 1_048_576
        let targetMB = max(500, Int(availableBefore) / 3)
        performMemoryPressureTrunc(targetMB: min(targetMB, 2000))
        let availableAfter = os_proc_available_memory() / 1_048_576
        LamoLogger.engine.info("Preload cleanup: \(availableBefore)MB → \(availableAfter)MB (freed \(availableAfter - availableBefore)MB)")
        #else
        LamoLogger.engine.info("Preload cleanup done (macOS — pressure trick skipped)")
        #endif
    }

    /// Restore URLCache after engine loads successfully.
    private func restoreURLCache() {
        if savedURLCacheMemory > 0 {
            URLCache.shared.memoryCapacity = savedURLCacheMemory
        }
        if savedURLCacheDisk > 0 {
            URLCache.shared.diskCapacity = savedURLCacheDisk
        }
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
            LamoLogger.engine.warning("Pressure trick: mmap failed for \(targetMB)MB")
            return
        }

        let buffer = ptr.bindMemory(to: UInt8.self, capacity: targetBytes)
        let pageSize = 4096
        for offset in stride(from: 0, to: targetBytes, by: pageSize) {
            buffer[offset] = 1
        }

        madvise(ptr, targetBytes, MADV_DONTNEED)

        munmap(ptr, targetBytes)
        LamoLogger.engine.info("Pressure trick: allocated/touched/released \(targetMB)MB")
    }

    /// Force-reload the engine (e.g., after model download completes).
    func reloadEngine() {
        invalidateEngine()
    }

    // MARK: - Model Discovery

    /// Human-readable name of the currently active model.
    var currentModelDisplayName: String {
        guard let path = litertLMModelPath ?? Self.findFirstModel() else {
            return ""
        }
        let filename = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".litertlm", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return filename
    }

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

    /// Finds the first model file (.litertlm, .bin, .tflite) in ~/Documents/models/.
    static func findFirstModel() -> String? {
        guard FileManager.default.fileExists(atPath: modelsDirectory.path) else { return nil }
        guard let first = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "litertlm" || $0.pathExtension == "bin" || $0.pathExtension == "tflite" }) else { return nil }
        return first.path
    }

    /// Lists all model files (.litertlm, .bin, .tflite) in ~/Documents/models/.
    static func listModels() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "litertlm" || $0.pathExtension == "bin" || $0.pathExtension == "tflite" }
            .map { $0.lastPathComponent }
    }
}
