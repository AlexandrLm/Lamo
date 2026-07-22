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

        let conversation = try await buildConversation(
            engine: resolvedEngine, messages: messages
        )

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

        // --- System prompt + memory (single source of truth: MemoryService) ---
        var systemPrompt = MemoryService.shared.buildFullSystemPrompt(
            base: pm.systemPrompt,
            conversationID: MemoryService.shared.currentConversationID
        )
        // Memory context is already embedded in systemPrompt via buildFullSystemPrompt.
        // We only tokenize it separately to measure token budget accurately.
        let memoryContext = MemoryService.shared.buildMemoryContext()

        // --- Token budget calculation (real tokenizer, not char/4) ---
        let effectiveMaxTokens = self.maxNumTokens ?? max(pm.maxNumTokens, 2048)
        let systemTokens = await pm.tokenizeCount(systemPrompt)
        let memoryTokens = await pm.tokenizeCount(memoryContext)

        // Use ContextTracker for accurate message selection
        let messageTokenCounts = await pm.tokenizeMessages(messages)
        let budgetResult = ContextTracker.calculateIncluded(
            messages: messages,
            tokenCounts: messageTokenCounts,
            systemPromptTokens: systemTokens,
            memoryTokens: memoryTokens,
            maxNumTokens: effectiveMaxTokens
        )

        // --- Auto-summarization when context is full ---
        let includedMessages = budgetResult.included
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
                if MemoryService.shared.currentConversationID != nil {
                    await MemoryService.shared.updateConversationSummary(summary)
                }
            }
        }

        // --- Inject plan progress scratchpad from previous turn (two-pass carryover) ---
        let planSummary = AgenticLoopState.shared.planSummary
        if !planSummary.isEmpty {
            systemPrompt += "\n\n\(planSummary)"
        }
        // Reset plan state for this new turn
        AgenticLoopState.shared.cancelPlan()

        // --- Inject current time into system prompt ---
        // First message: full info (date, weekday, tz, unix). Subsequent: time only.
        let now = Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        if messages.count <= 1 {
            // First message — full context so model knows all time-related facts
            df.dateFormat = "yyyy-MM-dd"
            let todayStr = df.string(from: now)
            df.dateFormat = "HH:mm:ss"
            let timeStr = df.string(from: now)
            df.dateFormat = "EEEE"
            let weekdayStr = df.string(from: now)
            let tz = TimeZone.current
            let utcOffset = tz.secondsFromGMT(for: now) / 3600
            systemPrompt += """

            <current_time>
              iso_date: \(todayStr)
              time: \(timeStr)
              weekday: \(weekdayStr)
              timezone: \(tz.identifier)
              utc_offset_hours: \(utcOffset >= 0 ? "+" : "")\(utcOffset)
              unix_timestamp: \(Int(now.timeIntervalSince1970))
            </current_time>
            """
        } else {
            // Subsequent messages — only time (date/tz/weekday don't change mid-session)
            df.dateFormat = "HH:mm:ss"
            systemPrompt += """

            <current_time>\(df.string(from: now))</current_time>
            """
        }
        await AgenticLoopBudget.shared.reset()

        // --- Build LiteRT-LM messages ---
        let systemMessage = LiteRTLM.Message(systemPrompt, role: .system)
        var allMessages: [LiteRTLM.Message] = [systemMessage]

        for msg in includedMessages {
            let role: LiteRTLM.Role = (msg.role == .assistant) ? .model : .user
            if msg.role == .user && !msg.fileContent.isEmpty {
                let fileContext = "Content of attached files:\n\n\(msg.fileContent)"
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
        // Build tool list. Web tools only included when network is available.
        let networkAvailable = Self.checkNetworkAvailable()
        var allTools: [LiteRTLM.Tool] = []
        if AppDefaults.toolGetLocation.wrappedValue { allTools.append(GetLocationTool()) }
        if AppDefaults.toolWeather.wrappedValue { allTools.append(WeatherTool()) }
        if AppDefaults.toolCalendar.wrappedValue { allTools.append(CalendarTool()) }
        if MemoryService.shared.isEnabled { allTools.append(UpdateMemoryTool()) }
        // Internet-dependent tools
        if networkAvailable {
            if AppDefaults.toolWebSearch.wrappedValue { allTools.append(WebSearchTool()) }
            if AppDefaults.toolFetchURL.wrappedValue { allTools.append(FetchUrlTool()) }
        }

        // --- Tokenize tool schemas using real getSchema() output ---
        var toolSchemaText = ""
        for tool in allTools {
            let schema = tool.getSchema()
            if let data = try? JSONSerialization.data(withJSONObject: schema, options: []),
               let json = String(data: data, encoding: .utf8) {
                toolSchemaText += json + "\n"
            }
        }
        let toolDefTokens = await pm.tokenizeCount(toolSchemaText)
        pm.lastToolTokens = toolDefTokens
        pm.lastToolCount = allTools.count
        pm.lastToolCountTotal = allTools.count

        // --- Accurate conversation tokens (real tokenizer, conservative fallback) ---
        let conversationTokens = includedMessages.reduce(0) { acc, msg in
            acc + (messageTokenCounts[msg.id] ?? max(1, msg.content.count / 2))
        }
        await AgenticLoopBudget.shared.configure(
            totalBudget: effectiveMaxTokens,
            systemOverhead: systemTokens + memoryTokens + toolDefTokens,
            conversationSkeletonTokens: conversationTokens,
            maxIterations: 5
        )

        // Enable constrained decoding to force valid tool calls (reduces hallucinations)
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableConversationConstrainedDecoding = true

        let config = LiteRTLM.ConversationConfig(
            initialMessages: allMessages,
            tools: allTools,
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

    /// Summarize old context via a single prompt (no expensive Conversation prefill).
    /// Concatenates dropped messages as text and asks the model for a summary,
    /// avoiding the full KV-cache rebuild that Conversation.createConversation() requires.
    private func summarizeOldContext(
        dropped: [ChatMessage],
        engine: LiteRTLM.Engine
    ) async -> String? {
        guard !dropped.isEmpty else { return nil }

        // Concatenate dropped messages into a single text block
        let conversationText = dropped.map { msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.prefix(500) // Truncate each to 500 chars
            return "[\(roleLabel)]: \(content)"
        }.joined(separator: "\n\n")

        guard !conversationText.isEmpty else { return nil }

        let summaryRequest = """
        Summarize the following conversation history into a concise context block. Preserve: \
        key facts, decisions, user preferences, code changes, file names, and important conclusions. \
        Be brief but complete — this summary replaces the original messages.

        \(conversationText)
        """

        do {
            let samplerConfig = try? buildSamplerConfig()
            let config = LiteRTLM.ConversationConfig(
                initialMessages: [LiteRTLM.Message(summaryRequest)],
                samplerConfig: samplerConfig
            )
            let summaryConv = try await engine.createConversation(with: config)
            var summaryText = ""
            for try await chunk in summaryConv.sendMessageStream(LiteRTLM.Message("")) {
                let text = chunk.toString
                if !text.isEmpty {
                    summaryText += text
                }
            }
            if !summaryText.isEmpty {
                return summaryText
            }
        } catch {
            LamoLogger.engine.warning("Summarization failed: \(error)")
        }
        return nil
    }

    /// Build the sampler config with safe ranges for Gemma 4.
    /// Results are cached and only recomputed when any parameter changes.
    private func buildSamplerConfig() throws -> LiteRTLM.SamplerConfig {
        let pm = ProviderManager.shared
        let safeTopK = max(1, min(pm.topK, 100))
        let safeTopP: Float = max(0.0, min(Float(pm.topP), 1.0))
        let safeTemp: Float = max(0.0, min(Float(pm.temperature), 2.0))

        // Return cached config if params are unchanged (seed excluded — changes every call).
        if let cached = cachedSamplerConfig,
           cached.topK == safeTopK,
           cached.topP == safeTopP,
           cached.temperature == safeTemp {
            return cached.config
        }

        let seed = Int.random(in: 0..<Int(Int32.max))
        let config = try LiteRTLM.SamplerConfig(
            topK: safeTopK,
            topP: safeTopP,
            temperature: safeTemp,
            seed: seed
        )
        cachedSamplerConfig = (topK: safeTopK, topP: safeTopP, temperature: safeTemp, seed: seed, config: config)
        return config
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
