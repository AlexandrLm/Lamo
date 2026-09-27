import Foundation
import LiteRTLM
import os

@MainActor
final class EngineLifecycle {
    private let settings: ModelSettings
    private let tokenBudget: TokenBudget
    private let onEngineReadyChanged: @MainActor (Bool) -> Void
    private let onEngineErrorChanged: @MainActor (LamoError?) -> Void
    private let onMemoryPressureChanged: @MainActor (Bool) -> Void
    private var cachedEngine: LiteRTLM.Engine?
    private var cachedProvider: (any LLMProvider)?
    private var invalidateTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var savedURLCacheMemory: Int = 0
    private var savedURLCacheDisk: Int = 0
    /// Coalesces memory-pressure bursts — while active, further events are
    /// ignored instead of spawning a 30s reset task per event.
    private var pressureActive = false
    var engineForSummarization: LiteRTLM.Engine? { cachedEngine }
    private(set) var currentMaxTokens: Int?
    var suppressInvalidation = false
    var currentProvider: any LLMProvider {
        if let cached = cachedProvider { return cached }
        return makeProvider()
    }

    /// Available memory in MB — two platform implementations.
    /// (Was a single #if with an unconditional os_proc_available_memory()
    /// re-read after cleanup, which is wrong on macOS.)
    private func availableMemoryMB() -> Double {
#if os(iOS)
        Double(os_proc_available_memory()) / 1_048_576
#else
        Double(ProcessInfo.processInfo.physicalMemory) / 2.0 / 1_048_576
#endif
    }

    /// Blocking filesystem preflight (stat + magic-byte read + directory
    /// scan). Runs in Task.detached so the MainActor never blocks on I/O.
    private nonisolated func preflightChecks(resolvedPath: String) async -> LamoError? {
        await Task.detached(priority: .utility) {
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let freeBytes = attrs[.systemFreeSize] as? UInt64,
               Double(freeBytes) / 1_073_741_824 < 1.0 {
                return LamoError.insufficientDiskSpace
            }
            if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
               let fileSize = fileAttrs[.size] as? Int64 {
                let gb = Double(fileSize) / 1_073_741_824
                if gb < 0.5 {
                    return LamoError.modelTooSmall(gb)
                }
            }
            if let fh = FileHandle(forReadingAtPath: resolvedPath) {
                defer { fh.closeFile() }
                let magic = fh.readData(ofLength: 4)
                if magic.count == 4, [UInt8](magic) == [0x00, 0x00, 0x00, 0x00] {
                    return LamoError.modelCorrupted(resolvedPath)
                }
            }
            return nil as LamoError?
        }.value
    }

    /// Creates the appropriate provider based on the current `providerType` setting.
    private func makeProvider() -> any LLMProvider {
        switch settings.providerType {
        case .litertLM:
            return LiteRTLMProvider(modelPath: settings.litertLMModelPath)
#if canImport(FoundationModels)
        case .foundationModels:
            return FoundationModelsProvider()
#endif
        }
    }
    init(settings: ModelSettings, tokenBudget: TokenBudget,
         onEngineReadyChanged: @escaping @MainActor (Bool) -> Void,
         onEngineErrorChanged: @escaping @MainActor (LamoError?) -> Void,
         onMemoryPressureChanged: @escaping @MainActor (Bool) -> Void) {
        self.settings = settings
        self.tokenBudget = tokenBudget
        self.onEngineReadyChanged = onEngineReadyChanged
        self.onEngineErrorChanged = onEngineErrorChanged
        self.onMemoryPressureChanged = onMemoryPressureChanged
    }
    func initializeEngineIfNeeded() async {
        // Foundation Models doesn't need engine initialization — just check availability
        if settings.providerType == .foundationModels {
            guard #available(iOS 27.0, macOS 27.0, *) else {
                onEngineErrorChanged(.foundationModelsUnavailable(String(localized: "Requires iOS 27 or macOS 27")))
                return
            }
            if FoundationModelsAvailability.isReady {
                cachedProvider = FoundationModelsProvider()
                onEngineReadyChanged(true)
            } else {
                onEngineErrorChanged(.foundationModelsUnavailable(FoundationModelsAvailability.unavailabilityReasonOrUnknown))
            }
            return
        }

        // LiteRT-LM initialization (unchanged logic below)
        guard cachedEngine == nil else {
            onEngineReadyChanged(true)
            return
        }
        onEngineErrorChanged(nil)
        onEngineReadyChanged(false)
        startMemoryPressureMonitoring()
        performPreloadCleanup()
        let resolvedPath: String
        if let path = ModelDiscovery.resolveModelPath(custom: settings.litertLMModelPath) {
            resolvedPath = path
        } else if settings.litertLMModelPath != nil {
            onEngineErrorChanged(.modelNotFound(settings.litertLMModelPath ?? String(localized: "(unknown)")))
            return
        } else {
            onEngineErrorChanged(.noModelAvailable)
            return
        }
        // Filesystem preflight off the MainActor (stat + magic read block).
        if let preflightError = await preflightChecks(resolvedPath: resolvedPath) {
            onEngineErrorChanged(preflightError)
            restoreURLCache()
            return
        }
        let filename = (resolvedPath as NSString).lastPathComponent
        if let preset = PresetModel.allCases.first(where: { $0.filename == filename }) {
            var availMB = availableMemoryMB()
            let requiredMB: Double = preset == .gemma4E4B ? 2000 : 1200
            if availMB < requiredMB {
                LamoLogger.engine.warning("Low memory (\(String(format: "%.0f", availMB))MB), attempting cleanup...")
                performPreloadCleanup()
                availMB = availableMemoryMB()
                if availMB < requiredMB {
                    onEngineErrorChanged(.insufficientMemory(available: availMB / 1024, required: requiredMB / 1024))
                    restoreURLCache()
                    return
                }
                LamoLogger.engine.info("Cleanup freed memory: \(String(format: "%.0f", availMB))MB now available")
            }
        }
        LiteRTLM.ExperimentalFlags.optIntoExperimentalAPIs()
        if settings.speculativeDecoding { LiteRTLM.ExperimentalFlags.enableSpeculativeDecoding = true }
        LiteRTLM.ExperimentalFlags.enableBenchmark = true
        let backend: LiteRTLM.Backend = settings.litertLMUseGPU
            ? .gpu : .cpu(threadCount: settings.cpuThreadCount)
        let maxTokens = tokenBudget.safeMaxTokens(
            modelPath: resolvedPath, useGPU: settings.litertLMUseGPU,
            kvCacheAuto: settings.kvCacheAuto, maxNumTokens: settings.maxNumTokens)
        currentMaxTokens = maxTokens
        // URLCache stays zeroed until the engine is up; defer guarantees the
        // restore runs on success AND on every failure path below.
        defer { restoreURLCache() }
        let maxAttempts = 3
        var lastError = LamoError.noModelAvailable
        for attempt in 1...maxAttempts {
            // Cooperative cancellation between attempts (invalidation races init).
            if Task.isCancelled { return }
            if attempt > 1 {
                // Exponential backoff: 1s, 2s (was a fixed 1s, no cancellation).
                let backoffNs: UInt64 = 1_000_000_000 * UInt64(1 << (attempt - 2))
                LamoLogger.engine.info("Engine init retry attempt \(attempt)/\(maxAttempts)...")
                try? await Task.sleep(nanoseconds: backoffNs)
                if Task.isCancelled { return }
            }
            guard let config = try? LiteRTLM.EngineConfig(
                modelPath: resolvedPath, backend: backend, visionBackend: .cpu(),
                audioBackend: nil, maxNumTokens: maxTokens, cacheDir: NSTemporaryDirectory()
            ) else {
                lastError = .engineInitFailed("config creation")
                LamoLogger.engine.error("\(lastError.errorDescription ?? "config error") (attempt \(attempt)/\(maxAttempts))")
                continue
            }
            let engine = LiteRTLM.Engine(engineConfig: config)
            do {
                let backend = self.settings.litertLMUseGPU ? "GPU" : "CPU"
                LamoLogger.engine.info(
                    "Initializing engine for: \(filename), backend=\(backend), maxTokens=\(maxTokens ?? -1) (attempt \(attempt)/\(maxAttempts))"
                )
                try await engine.initialize()
                // Check cancellation before publishing a potentially stale engine.
                try Task.checkCancellation()
                LamoLogger.engine.info("Engine initialized successfully")
                cachedEngine = engine
                cachedProvider = LiteRTLMProvider(
                    modelPath: settings.litertLMModelPath,
                    useGPU: settings.litertLMUseGPU, maxNumTokens: maxTokens, engine: engine)
                onEngineReadyChanged(true)
                return
            } catch is CancellationError {
                return
            } catch {
                lastError = .engineInitFailed(error.localizedDescription)
                LamoLogger.engine.error("\(lastError.errorDescription ?? "init failed") (attempt \(attempt)/\(maxAttempts))")
            }
        }
        onEngineErrorChanged(lastError)
    }
    func invalidateEngine() {
        cachedEngine = nil
        cachedProvider = nil
        onEngineReadyChanged(false)
        currentMaxTokens = nil
        tokenBudget.clearTokenCache()
        // Only LiteRT needs re-initialization after invalidation
        guard settings.providerType == .litertLM else { return }
        invalidateTask?.cancel()
        invalidateTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await initializeEngineIfNeeded()
        }
    }
    func switchModel(modelPath: String) {
        suppressInvalidation = true
        settings.litertLMModelPath = modelPath
        suppressInvalidation = false
        invalidateEngine()
    }
    func reloadEngine() { invalidateEngine() }
    private func startMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                // Debounce: coalesce bursts while a pressure window is active
                // (was one 30s reset task per event, stacking indefinitely).
                guard !self.pressureActive else { return }
                self.pressureActive = true
                self.onMemoryPressureChanged(true)
                self.tokenBudget.clearTokenCache()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30))
                    self.pressureActive = false
                    self.onMemoryPressureChanged(false)
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }
    private func performPreloadCleanup() {
        savedURLCacheMemory = URLCache.shared.memoryCapacity
        savedURLCacheDisk = URLCache.shared.diskCapacity
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.diskCapacity = 0
        cachedEngine = nil
        cachedProvider = nil
        tokenBudget.clearTokenCache()
        autoreleasepool { }
        let tmp = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for file in contents where file.lastPathComponent.hasPrefix("litert") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        LamoLogger.engine.info("Preload cleanup done")
    }
    private func restoreURLCache() {
        URLCache.shared.memoryCapacity = savedURLCacheMemory
        URLCache.shared.diskCapacity = savedURLCacheDisk
    }
}
