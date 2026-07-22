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
    var engineForSummarization: LiteRTLM.Engine? { cachedEngine }
    private(set) var currentMaxTokens: Int?
    var suppressInvalidation = false
    var currentProvider: any LLMProvider {
        if let cached = cachedProvider { return cached }
        return LiteRTLMProvider(modelPath: settings.litertLMModelPath)
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
            onEngineErrorChanged(.modelNotFound(settings.litertLMModelPath ?? "(unknown)"))
            return
        } else {
            onEngineErrorChanged(.noModelAvailable)
            return
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeBytes = attrs[.systemFreeSize] as? UInt64,
           Double(freeBytes) / 1_073_741_824 < 1.0 {
            onEngineErrorChanged(.insufficientDiskSpace)
            return
        }
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
           let fileSize = fileAttrs[.size] as? Int64 {
            let gb = Double(fileSize) / 1_073_741_824
            if gb < 0.5 {
                onEngineErrorChanged(.modelTooSmall(gb))
                return
            }
        }
        if let fh = FileHandle(forReadingAtPath: resolvedPath) {
            defer { fh.closeFile() }
            let magic = fh.readData(ofLength: 4)
            if magic.count == 4, [UInt8](magic) == [0x00, 0x00, 0x00, 0x00] {
                onEngineErrorChanged(.modelCorrupted(resolvedPath))
                return
            }
        }
        let filename = (resolvedPath as NSString).lastPathComponent
        if let preset = PresetModel.allCases.first(where: { $0.filename == filename }) {
            #if os(iOS)
            var availMB = Double(os_proc_available_memory()) / 1_048_576
            #else
            var availMB = Double(ProcessInfo.processInfo.physicalMemory) / 2.0 / 1_048_576
            #endif
            let requiredMB: Double = preset == .gemma4E4B ? 2000 : 1200
            if availMB < requiredMB {
                LamoLogger.engine.warning("Low memory (\(String(format: "%.0f", availMB))MB), attempting cleanup...")
                performPreloadCleanup()
                availMB = Double(os_proc_available_memory()) / 1_048_576
                if availMB < requiredMB {
                    onEngineErrorChanged(.insufficientMemory(available: availMB / 1024, required: requiredMB / 1024))
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
        let maxAttempts = 3
        var lastError = LamoError.noModelAvailable
        for attempt in 1...maxAttempts {
            if attempt > 1 {
                LamoLogger.engine.info("Engine init retry attempt \(attempt)/\(maxAttempts)...")
                try? await Task.sleep(for: .seconds(1))
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
                LamoLogger.engine.info("Initializing engine for: \(filename), backend=\(self.settings.litertLMUseGPU ? "GPU" : "CPU"), maxTokens=\(maxTokens ?? -1) (attempt \(attempt)/\(maxAttempts))")
                try await engine.initialize()
                LamoLogger.engine.info("Engine initialized successfully")
                cachedEngine = engine
                cachedProvider = LiteRTLMProvider(
                    modelPath: settings.litertLMModelPath,
                    useGPU: settings.litertLMUseGPU, maxNumTokens: maxTokens, engine: engine)
                onEngineReadyChanged(true)
                restoreURLCache()
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
                self.onMemoryPressureChanged(true)
                self.tokenBudget.clearTokenCache()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30))
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
