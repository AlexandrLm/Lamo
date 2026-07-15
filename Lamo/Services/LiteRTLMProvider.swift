import Foundation
@preconcurrency import LiteRTLM
import SwiftData
import os

/// Provider that runs a local LLM via Google's LiteRT-LM framework.
/// Supports GPU (Metal) acceleration, streaming, and persistent conversation caching.
///
/// Performance notes:
/// - Conversation is rebuilt each turn, but tokenization is cached for speed.
/// - When context fills up, old messages are auto-summarized via the model.
/// - Budget is calculated using the real tokenizer, not char/4 approximation.
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

    /// Lock for thread-safe access to cached conversation
    private let cacheLock = OSAllocatedUnfairLock(initialState: ())

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
                do {
                    try await provider.runInference(messages: messages, continuation: continuation)
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.error(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Invalidate cached conversation (e.g. when model or GPU setting changes).
    func invalidateConversationCache() {
        // No persistent conversation cache to clear — conversations are rebuilt each turn.
        // This is called by ProviderManager on memory pressure; the next inference
        // will build a fresh conversation which is the default behavior.
    }

    // MARK: - Private

    private func runInference(
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
        // Resolve engine
        let resolvedEngine: LiteRTLM.Engine
        if let cached = engine {
            resolvedEngine = cached
        } else {
            let resolvedPath = try resolveModelPath()
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

        // Build conversation with smart context management
        let conversation = try await buildConversation(
            engine: resolvedEngine, messages: messages
        )

        // Send the last user message and stream the response
        guard !Task.isCancelled else { return }
        try await streamLastMessage(
            conversation: conversation,
            messages: messages,
            continuation: continuation
        )
    }

    /// Build a conversation with token-accurate budget and auto-summarization.
    private func buildConversation(
        engine: LiteRTLM.Engine,
        messages: [ChatMessage]
    ) async throws -> LiteRTLM.Conversation {
        let pm = ProviderManager.shared

        // --- System prompt + memory ---
        var systemPrompt = pm.systemPrompt
        let memoryContext = MemoryService.shared.buildMemoryContext()
        var extraSummaryContext = ""

        if MemoryService.shared.isEnabled {
            systemPrompt += "\n\nRemember important user facts via update_memory tool. Summarize long conversations via summary parameter."

            // Inject existing conversation summary (from previous summarizations)
            if let convID = MemoryService.shared.currentConversationID,
               let summary = fetchConversationSummary(convID: convID), !summary.isEmpty {
                extraSummaryContext = "\n\n<conversation_summary>\n\(summary)\n</conversation_summary>"
            }
            if !memoryContext.isEmpty {
                systemPrompt += "\n\n" + memoryContext
            }
        }
        systemPrompt += extraSummaryContext

        // --- Token budget calculation (real tokenizer, not char/4) ---
        let effectiveMaxTokens = self.maxNumTokens ?? max(pm.maxNumTokens, 2048)
        let systemTokens = await pm.tokenizeCount(systemPrompt)
        let memoryTokens = await pm.tokenizeCount(memoryContext + extraSummaryContext)

        // Use ContextTracker for accurate message selection
        let budgetResult = ContextTracker.calculateIncluded(
            messages: messages,
            tokenCounts: await pm.tokenizeMessages(messages),
            systemPromptTokens: systemTokens,
            memoryTokens: memoryTokens,
            maxNumTokens: effectiveMaxTokens
        )

        // --- Auto-summarization when context is full ---
        var includedMessages = budgetResult.included
        if budgetResult.needsSummary,
           !budgetResult.dropped.isEmpty,
           let sumEngine = self.engine ?? pm.engineForSummarization {
            if let summary = await summarizeOldContext(
                dropped: budgetResult.dropped,
                engine: sumEngine
            ) {
                LamoLogger.engine.info("Auto-summary: \(budgetResult.dropped.count) messages → \(summary.count) chars")
                // Inject summary into system prompt
                systemPrompt += "\n\n<earlier_context_summary>\n\(summary)\n</earlier_context_summary>"
                // Persist summary for future conversations
                if let convID = MemoryService.shared.currentConversationID {
                    await MemoryService.shared.updateConversationSummary(summary)
                }
            }
        }

        // --- Build LiteRT-LM messages ---
        let systemMessage = LiteRTLM.Message(systemPrompt, role: .user)
        var allMessages: [LiteRTLM.Message] = [systemMessage]

        for msg in includedMessages {
            let role: LiteRTLM.Role = (msg.role == .assistant) ? .model : .user
            if msg.role == .user && !msg.fileContent.isEmpty {
                let fileContext = "Содержимое прикреплённых файлов:\n\n\(msg.fileContent)"
                allMessages.append(LiteRTLM.Message(fileContext, role: .user))
                if !msg.content.isEmpty {
                    allMessages.append(LiteRTLM.Message(msg.content, role: .user))
                }
            } else {
                allMessages.append(LiteRTLM.Message(msg.content, role: role))
            }
        }

        // --- Create conversation ---
        let samplerConfig = try buildSamplerConfig()
        let tools: [LiteRTLM.Tool] = MemoryService.shared.isEnabled
            ? [UpdateMemoryTool(), WebSearchTool(), FetchUrlTool(), DeepResearchTool()]
            : [WebSearchTool(), FetchUrlTool(), DeepResearchTool()]

        let config = LiteRTLM.ConversationConfig(
            initialMessages: allMessages,
            tools: tools,
            samplerConfig: samplerConfig
        )

        do {
            return try await engine.createConversation(with: config)
        } catch {
            // Fallback: minimal history (system prompt + last user message only)
            LamoLogger.engine.warning("Conversation creation failed, falling back to minimal: \(error)")
            var minimal: [LiteRTLM.Message] = [systemMessage]
            if let last = allMessages.last, last.role == .user {
                minimal.append(last)
            }
            let fallbackConfig = LiteRTLM.ConversationConfig(
                initialMessages: minimal,
                samplerConfig: samplerConfig
            )
            return try await engine.createConversation(with: fallbackConfig)
        }
    }

    /// Summarize old context via a temporary conversation.
    /// The temporary conversation is destroyed after getting the summary,
    /// freeing its KV-cache allocation.
    private func summarizeOldContext(
        dropped: [ChatMessage],
        engine: LiteRTLM.Engine
    ) async -> String? {
        guard !dropped.isEmpty else { return nil }

        let summaryRequest = """
        Summarize the following conversation history into a concise context block. Preserve: \
        key facts, decisions, user preferences, code changes, file names, and important conclusions. \
        Be brief but complete — this summary replaces the original messages.
        """

        let samplerConfig = try? buildSamplerConfig()

        // Old messages as initial context (prefilled into KV-cache)
        var initialMessages: [LiteRTLM.Message] = []
        for msg in dropped {
            let role: LiteRTLM.Role = (msg.role == .assistant) ? .model : .user
            initialMessages.append(LiteRTLM.Message(msg.content, role: role))
        }

        let config = LiteRTLM.ConversationConfig(
            initialMessages: initialMessages,
            samplerConfig: samplerConfig
        )

        do {
            let summaryConv = try await engine.createConversation(with: config)
            // Send summary request as the final message — model responds with summary
            var summaryText = ""
            let summaryMsg = LiteRTLM.Message(summaryRequest)
            for try await chunk in summaryConv.sendMessageStream(summaryMsg) {
                let text = chunk.toString
                if !text.isEmpty {
                    summaryText += text
                }
            }
            // Temporary conversation is released here, freeing its KV-cache
            if !summaryText.isEmpty {
                return summaryText
            }
        } catch {
            LamoLogger.engine.warning("Summarization failed: \(error)")
        }
        return nil
    }

    /// Build the sampler config with safe ranges for Gemma 4.
    private func buildSamplerConfig() throws -> LiteRTLM.SamplerConfig {
        let pm = ProviderManager.shared
        let safeTopK = max(1, min(pm.topK, 100))
        let safeTemp: Float = max(0.0, min(Float(pm.temperature), 2.0))
        let safeTopP: Float = max(0.0, min(Float(pm.topP), 1.0))
        return try LiteRTLM.SamplerConfig(
            topK: safeTopK,
            topP: safeTopP,
            temperature: safeTemp,
            seed: Int.random(in: 0..<Int(Int32.max))
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

        let repDetector = RepetitionDetector()

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
                contents.append(.text("Содержимое прикреплённых файлов:\n\n\(msg.fileContent)"))
            }
            if !msg.content.isEmpty {
                contents.append(.text(msg.content))
            }
            return LiteRTLM.Message(contents: contents)
        } else if !msg.fileContent.isEmpty {
            let fullText: String
            if msg.content.isEmpty {
                fullText = "Проанализируй содержимое прикреплённых файлов:\n\n\(msg.fileContent)"
            } else {
                fullText = "Содержимое прикреплённых файлов:\n\n\(msg.fileContent)\n\n---\n\n\(msg.content)"
            }
            return LiteRTLM.Message(fullText)
        } else {
            return LiteRTLM.Message(msg.content)
        }
    }

    /// Fetch conversation summary from SwiftData.
    private func fetchConversationSummary(convID: UUID) -> String? {
        guard let context = MemoryService.shared.modelContext else { return nil }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == convID }
        )
        return try? context.fetch(descriptor).first?.summary
    }

    private func resolveModelPath() throws -> String {
        if let path = ProviderManager.resolveModelPath(custom: modelPath) {
            return path
        }
        if modelPath != nil {
            throw LiteRTLMError.modelNotFound(modelPath!)
        } else if !FileManager.default.fileExists(atPath: ProviderManager.modelsDirectory.path) {
            throw LiteRTLMError.modelsDirectoryMissing
        } else {
            throw LiteRTLMError.noModelFound
        }
    }
}

// MARK: - Errors

enum LiteRTLMError: LocalizedError {
    case modelNotFound(String)
    case modelsDirectoryMissing
    case noModelFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found at: \(path)"
        case .modelsDirectoryMissing:
            return "Models directory not found. Create ~/Documents/models/ and place a .litertlm file there."
        case .noModelFound:
            return "No .litertlm files found in ~/Documents/models/. Download a model first."
        }
    }
}
