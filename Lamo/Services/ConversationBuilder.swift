import Foundation
@preconcurrency import LiteRTLM
import os

// MARK: - Errors

enum LiteRTLMError: LocalizedError {
    case modelNotFound(String)
    case modelsDirectoryMissing
    case noModelFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return String(localized: "Model file not found at: \(path)")
        case .modelsDirectoryMissing:
            return String(localized: "Models directory not found. Create ~/Documents/models/ and place a .litertlm file there.")
        case .noModelFound:
            return String(localized: "No .litertlm files found in ~/Documents/models/. Download a model first.")
        }
    }
}

/// Builds LiteRT-LM conversations with token-accurate budget and auto-summarization.
/// Extracted from LiteRTLMProvider to reduce class complexity.
///
/// Performance notes:
/// - Conversation is rebuilt each turn, but tokenization is cached for speed.
/// - When context fills up, old messages are auto-summarized via the model.
/// - Budget is calculated using the real tokenizer, not char/4 approximation.
struct ConversationBuilder {
    let engine: LiteRTLM.Engine
    let modelPath: String?
    let useGPU: Bool
    let cpuThreadCount: Int
    let maxNumTokens: Int?

    // MARK: - Shared constants and caches

    /// Hard cap for file text injected into a single message.
    static let maxFileChars = 15_000
    /// Hard cap for the auto-summarization request payload.
    static let maxSummaryChars = 8_000
    /// Tool schema JSON per tool-set key. Tool sets change only in Settings,
    /// so caching avoids re-serializing every schema on each turn.
    private static let toolSchemaTextCache = OSAllocatedUnfairLock(initialState: [String: String]())

    /// Cached tool-schema text for one tool-set key.
    static func toolSchemaText(for key: String, build: () -> String) -> String {
        toolSchemaTextCache.withLock { cache in
            if let cached = cache[key] { return cached }
            let text = build()
            cache[key] = text
            // Settings can only produce a handful of distinct combinations;
            // a full reset is cheaper than maintaining LRU metadata here.
            if cache.count > 16 { cache.removeAll() }
            return text
        }
    }
    /// `DateFormatter` is not thread-safe; one lock guards all three instances.
    static let formatterLock = NSLock()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE"
        return f
    }()

    // MARK: - Conversation Building

    /// Build a conversation with token-accurate budget and auto-summarization.
    /// `systemPrompt` must already include memory context (buildFullSystemPrompt
    /// bakes it in) — memory tokens are NOT charged a second time.
    func build(
        messages: [ChatMessage],
        systemPrompt: String,
        networkAvailable: Bool
    ) async throws -> LiteRTLM.Conversation {
        let pm = ProviderManager.shared

        // --- System prompt (mutable copy for augmentation) ---
        var augmentedPrompt = systemPrompt

        // --- Inject current time into system prompt ---
        // Done BEFORE tokenizing so the budget matches what is actually sent.
        // The same block is counted by the tracker via currentTimeBlock().
        augmentedPrompt += Self.currentTimeBlock(messageCount: messages.count)

        // --- Build tool list (needed before budgeting: tool schemas occupy
        // context on every single turn) ---
        let samplerConfig = try buildSamplerConfig()
        // Web tools only included when network is available.
        var allTools: [LiteRTLM.Tool] = []
        if AppDefaults.toolGetLocation.wrappedValue { allTools.append(GetLocationTool()) }
        if AppDefaults.toolWeather.wrappedValue { allTools.append(WeatherTool()) }
        if AppDefaults.toolCalendar.wrappedValue { allTools.append(CalendarTool()) }
        if AppDefaults.memoryEnabled.wrappedValue { allTools.append(UpdateMemoryTool()) }
        // Internet-dependent tools
        if networkAvailable {
            if AppDefaults.toolWebSearch.wrappedValue { allTools.append(WebSearchTool()) }
            if AppDefaults.toolFetchURL.wrappedValue { allTools.append(FetchUrlTool()) }
        }

        // --- Tokenize tool schemas using real getSchema() output ---
        // Schema text cached per tool-set key; counts via TokenBudget cache.
        let toolKey = "\(AppDefaults.toolGetLocation.wrappedValue)-\(AppDefaults.toolWeather.wrappedValue)-\(AppDefaults.toolCalendar.wrappedValue)-\(AppDefaults.memoryEnabled.wrappedValue)-\(networkAvailable)-\(AppDefaults.toolWebSearch.wrappedValue)-\(AppDefaults.toolFetchURL.wrappedValue)"
        let toolSchemaText = Self.toolSchemaText(for: toolKey) {
            var text = ""
            for tool in allTools {
                let schema = tool.getSchema()
                if let data = try? JSONSerialization.data(withJSONObject: schema, options: []),
                   let json = String(data: data, encoding: .utf8) {
                    text += json + "\n"
                }
            }
            return text
        }
        let toolDefTokens = await pm.tokenizeCount(toolSchemaText)
        pm.lastToolTokens = toolDefTokens
        pm.lastToolCount = allTools.count
        pm.lastToolCountTotal = ToolDefinitions.allNames.count

        // --- Token budget calculation (real tokenizer, not char/4) ---
        let effectiveMaxTokens = maxNumTokens ?? max(pm.maxNumTokens, 2048)
        // systemPrompt already contains the memory context — counting memory
        // separately here would subtract the same tokens twice and shrink the
        // usable context (messages dropped earlier than needed).
        let systemTokens = await pm.tokenizeCount(augmentedPrompt)

        // Use ContextTracker for accurate message selection
        let messageTokenCounts = await pm.tokenizeMessages(messages)
        let budgetResult = ContextTracker.calculateIncluded(
            messages: messages,
            tokenCounts: messageTokenCounts,
            systemPromptTokens: systemTokens,
            // Memory is already inside systemTokens — never charge it twice.
            memoryTokens: 0,
            toolTokens: toolDefTokens,
            maxNumTokens: effectiveMaxTokens
        )

        // --- Auto-summarization when context is full ---
        let includedMessages = budgetResult.included
        if budgetResult.needsSummary,
           !budgetResult.dropped.isEmpty {
            if let summary = await summarizeOldContext(dropped: budgetResult.dropped) {
                LamoLogger.engine.info("Auto-summary: \(budgetResult.dropped.count) messages → \(summary.count) chars")
                // Inject summary into system prompt
                augmentedPrompt += "\n\n<earlier_context_summary>\n\(summary)\n</earlier_context_summary>"
                // Persist summary for future conversations
                let conversationID = messages.first?.conversationID
                if let conversationID {
                    await MemoryService.shared.updateConversationSummary(summary, conversationID: conversationID)
                }
            }
        }

        await AgenticLoopBudget.shared.reset()

        // --- Build LiteRT-LM messages ---
        let systemMessage = LiteRTLM.Message(augmentedPrompt, role: .system)
        var allMessages: [LiteRTLM.Message] = [systemMessage]

        for msg in includedMessages {
            let role: LiteRTLM.Role = (msg.role == .assistant) ? .model : .user
            if msg.role == .user && !msg.fileContent.isEmpty {
                let fileContext = "Content of attached files:\n\n\(msg.fileContent.prefix(Self.maxFileChars))"
                allMessages.append(LiteRTLM.Message(fileContext, role: .user))
                if !msg.content.isEmpty {
                    allMessages.append(LiteRTLM.Message(msg.content, role: .user))
                }
            } else {
                allMessages.append(LiteRTLM.Message(msg.content, role: role))
            }
        }

        // --- Accurate conversation tokens (real tokenizer, conservative fallback) ---
        // Fallback uses the shared estimator (ASCII ≈ 4 chars/token, CJK ≈ 1)
        // instead of count/4, matching the tracker and the budget.
        let conversationTokens = includedMessages.reduce(0) { acc, msg in
            acc + (messageTokenCounts[msg.id] ?? AgenticLoopBudget.estimateTokens(of: msg.content))
        }
        await AgenticLoopBudget.shared.configure(
            totalBudget: effectiveMaxTokens,
            systemOverhead: systemTokens + toolDefTokens,
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
            // Fallback: minimal history (system prompt + last user message only),
            // but KEEP tools — dropping them makes the model hallucinate tool calls.
            LamoLogger.engine.warning("Conversation creation failed, falling back to minimal: \(error)")
            var minimal: [LiteRTLM.Message] = [systemMessage]
            if let last = allMessages.last, last.role == .user {
                minimal.append(last)
            }
            let fallbackConfig = LiteRTLM.ConversationConfig(
                initialMessages: minimal,
                tools: allTools,
                samplerConfig: samplerConfig
            )
            return try await engine.createConversation(with: fallbackConfig)
        }
    }

    // MARK: - Current Time Block (shared with tracker)

    /// Current-time injection, shared with the context tracker so the menu
    /// counts exactly the string that is sent to the model.
    /// First message: full info (date, weekday, tz, unix). Subsequent: time only.
    static func currentTimeBlock(messageCount: Int, now: Date = Date()) -> String {
        Self.formatterLock.lock()
        defer { Self.formatterLock.unlock() }
        if messageCount <= 1 {
            let todayStr = Self.dateFormatter.string(from: now)
            let timeStr = Self.timeFormatter.string(from: now)
            let weekdayStr = Self.weekdayFormatter.string(from: now)
            let tz = TimeZone.current
            let utcOffset = tz.secondsFromGMT(for: now) / 3600
            return """

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
            return """

            <current_time>\(Self.timeFormatter.string(from: now))</current_time>
            """
        }
    }

    // MARK: - Sampler Config
    /// Build the sampler config with safe ranges for Gemma 4.
    /// A fresh random seed every call is deliberate: reusing a seed makes sampling
    /// deterministic, so a loop-detection retry would reproduce the exact same loop.
    func buildSamplerConfig() throws -> LiteRTLM.SamplerConfig {
        let pm = ProviderManager.shared
        let safeTopK = max(1, min(pm.topK, 100))
        let safeTopP: Float = max(0.0, min(Float(pm.topP), 1.0))
        let safeTemp: Float = max(0.0, min(Float(pm.temperature), 2.0))

        return try LiteRTLM.SamplerConfig(
            topK: safeTopK,
            topP: safeTopP,
            temperature: safeTemp,
            seed: Int.random(in: 0..<Int(Int32.max))
        )
    }

    // MARK: - Summarization

    /// Summarize old context via a single prompt (no expensive Conversation prefill).
    /// Concatenates dropped messages as text and asks the model for a summary,
    /// avoiding the full KV-cache rebuild that Conversation.createConversation() requires.
    func summarizeOldContext(dropped: [ChatMessage]) async -> String? {
        guard !dropped.isEmpty else { return nil }

        // Cap dropped history: only the newest 20 messages, 500 chars each,
        // 8000 chars total — unbounded concatenation blew the prefill on long
        // histories (the summary request itself overflowed).
        let capped = Array(dropped.suffix(20))
        // Concatenate dropped messages into a single text block
        var conversationText = capped.map { msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.prefix(500) // Truncate each to 500 chars
            return "[\(roleLabel)]: \(content)"
        }.joined(separator: "\n\n")
        if conversationText.count > Self.maxSummaryChars {
            conversationText = String(conversationText.prefix(Self.maxSummaryChars))
        }

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

}
