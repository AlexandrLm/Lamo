import Foundation
@preconcurrency import LiteRTLM
import SwiftData
import Network
import os

/// Provider that runs a local LLM via Google's LiteRT-LM framework.
/// Supports GPU (Metal) acceleration, streaming, and persistent conversation caching.
///
/// Performance notes:
/// - Conversation is rebuilt each turn, but tokenization is cached for speed.
/// - When context fills up, old messages are auto-summarized via the model.
/// - Budget is calculated using the real tokenizer, not char/4 approximation.
///
/// @unchecked Sendable: required because LiteRTLM.Engine is imported via
/// @preconcurrency and Swift cannot verify its Sendable conformance. All
/// stored properties are `let` constants — no mutable state to protect.
final class LiteRTLMProvider: LLMProvider, @unchecked Sendable {
    let name = "LiteRT-LM"

    /// Path to the .litertlm model file.
    private let modelPath: String?
    /// Backend selection
    private let useGPU: Bool
    /// CPU thread count (only used when useGPU is false)
    private let cpuThreadCount: Int
    /// Max tokens for KV-cache. nil = model default.
    private let maxNumTokens: Int?
    /// Cached engine — injected by ProviderManager to avoid reloading.
    private let engine: LiteRTLM.Engine?

    /// Cached SamplerConfig — avoids redundant UserDefaults reads.
    /// Cache key excludes seed (changes every call). Uses Float for comparison accuracy.
    private var cachedSamplerConfig: (topK: Int, topP: Float, temperature: Float, seed: Int, config: LiteRTLM.SamplerConfig)?

    /// Cached network availability — checked once per conversation build.
    /// Uses NWPathMonitor for a one-shot synchronous check via semaphore.
    private static var _networkAvailable = true
    private static let networkLock = NSLock()
    private static var networkMonitorStarted = false

    private static func checkNetworkAvailable() -> Bool {
        networkLock.lock()
        defer { networkLock.unlock() }
        if !networkMonitorStarted {
            networkMonitorStarted = true
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                networkLock.lock()
                _networkAvailable = path.status == .satisfied
                networkLock.unlock()
            }
            monitor.start(queue: .global(qos: .background))
        }
        return _networkAvailable
    }

    init(
        modelPath: String? = nil,
        useGPU: Bool = true,
        cpuThreadCount: Int = 4,
        maxNumTokens: Int? = nil,
        engine: LiteRTLM.Engine? = nil
    ) {
        self.modelPath = modelPath
        self.useGPU = useGPU
        self.cpuThreadCount = cpuThreadCount
        self.maxNumTokens = maxNumTokens
        self.engine = engine
    }

    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken> {
        AsyncStream { continuation in
            let provider = self
            let task = Task {
                await ToolCallReporter.shared.register(continuation: continuation)
                do {
                    try await provider.runInference(messages: messages, continuation: continuation)
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.error(error))
                }
                await ToolCallReporter.shared.reset()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }



    // MARK: - Private

    private func runInference(
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
        let resolvedEngine: LiteRTLM.Engine
        if let cached = engine {
            resolvedEngine = cached
        } else {
            let resolvedPath: String
            if let path = ProviderManager.resolveModelPath(custom: modelPath) {
                resolvedPath = path
            } else if modelPath != nil {
                throw LiteRTLMError.modelNotFound(modelPath!)
            } else if !FileManager.default.fileExists(atPath: ProviderManager.modelsDirectory.path) {
                throw LiteRTLMError.modelsDirectoryMissing
            } else {
                throw LiteRTLMError.noModelFound
            }
            let backend: LiteRTLM.Backend = useGPU ? .gpu : .cpu(threadCount: cpuThreadCount)
            let engineConfig = try LiteRTLM.EngineConfig(
                modelPath: resolvedPath,
                backend: backend,
                visionBackend: .cpu(),
                audioBackend: nil,
                maxNumTokens: self.maxNumTokens,
                cacheDir: NSTemporaryDirectory()
            )
            let newEngine = LiteRTLM.Engine(engineConfig: engineConfig)
            try await newEngine.initialize()
            resolvedEngine = newEngine
        }

        let systemPrompt = MemoryService.shared.buildFullSystemPrompt(
            base: ProviderManager.shared.systemPrompt,
            conversationID: MemoryService.shared.currentConversationID
        )
        let memoryContext = MemoryService.shared.buildMemoryContext()
        let networkAvailable = Self.checkNetworkAvailable()

        var builder = ConversationBuilder(
            engine: resolvedEngine,
            modelPath: modelPath,
            useGPU: useGPU,
            cpuThreadCount: cpuThreadCount,
            maxNumTokens: maxNumTokens
        )
        builder.samplerConfigCache = cachedSamplerConfig

        let conversation = try await builder.build(
            messages: messages,
            systemPrompt: systemPrompt,
            memoryContext: memoryContext,
            networkAvailable: networkAvailable
        )
        cachedSamplerConfig = builder.samplerConfigCache

        guard !Task.isCancelled else { return }
        try await streamLastMessage(
            conversation: conversation,
            messages: messages,
            continuation: continuation
        )
    }

    /// Stream the last user message and yield tokens.
    private func streamLastMessage(
        conversation: LiteRTLM.Conversation,
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            continuation.yield(.done)
            continuation.finish()
            return
        }

        let message = buildLiteMessage(from: lastUserMessage, role: .user)
        let extraContext: [String: Any]? = ProviderManager.shared.thinkingMode
            ? ["enable_thinking": "true"] : nil

        let repDetector = RepetitionDetector(windowSize: 2000, minBufferSize: 100, checkFrequency: 5)

        for try await chunk in conversation.sendMessageStream(message, extraContext: extraContext) {
            guard !Task.isCancelled else {
                try? conversation.cancel()
                return
            }
            if let thought = chunk.channels["thought"], !thought.isEmpty {
                continuation.yield(.thinkingDelta(thought))
            }
            let text = chunk.toString
            if !text.isEmpty {
                continuation.yield(.delta(text))
                if repDetector.feed(text) {
                    try? conversation.cancel()
                    continuation.yield(.loopDetected)
                    break
                }
            }
        }

        guard !Task.isCancelled else { return }

        // Capture benchmark data
        if let benchmarkInfo = try? conversation.getBenchmarkInfo() {
            let data = BenchmarkData(
                timeToFirstToken: benchmarkInfo.timeToFirstTokenInSecond,
                decodeTokensPerSec: benchmarkInfo.lastDecodeTokensPerSecond,
                decodeTokenCount: benchmarkInfo.lastDecodeTokenCount,
                prefillTokensPerSec: benchmarkInfo.lastPrefillTokensPerSecond,
                prefillTokenCount: benchmarkInfo.lastPrefillTokenCount
            )
            continuation.yield(.benchmark(data))
        }

        continuation.yield(.done)
        continuation.finish()
    }

    /// Build a LiteRTLM.Message from a ChatMessage.
    private func buildLiteMessage(from msg: ChatMessage, role: LiteRTLM.Role) -> LiteRTLM.Message {
        if !msg.imagePaths.isEmpty {
            var contents: [LiteRTLM.Content] = msg.imagePaths.map { .imageFile($0) }
            if !msg.fileContent.isEmpty {
                contents.append(.text("Content of attached files:\n\n\(msg.fileContent)"))
            }
            if !msg.content.isEmpty {
                contents.append(.text(msg.content))
            }
            return LiteRTLM.Message(contents: contents)
        } else if !msg.fileContent.isEmpty {
            let fullText: String
            if msg.content.isEmpty {
                fullText = "Analyze the content of the attached files:\n\n\(msg.fileContent)"
            } else {
                fullText = "Content of attached files:\n\n\(msg.fileContent)\n\n---\n\n\(msg.content)"
            }
            return LiteRTLM.Message(fullText)
        } else {
            return LiteRTLM.Message(msg.content)
        }
    }

}
