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

    static let maxFileChars = 8_000
    static let maxSummaryChars = 8_000
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

    func build(
        messages: [ChatMessage],
        systemPrompt: String,
        networkAvailable: Bool
    ) async throws -> LiteRTLM.Conversation {
        let pm = ProviderManager.shared

        var augmentedPrompt = systemPrompt
        augmentedPrompt += Self.currentTimeBlock(messageCount: messages.count)

        let samplerConfig = try buildSamplerConfig()
        var allTools: [LiteRTLM.Tool] = []
        if AppDefaults.toolGetLocation.wrappedValue { allTools.append(GetLocationTool()) }
        if AppDefaults.toolWeather.wrappedValue { allTools.append(WeatherTool()) }
        if AppDefaults.toolCalendar.wrappedValue { allTools.append(CalendarTool()) }
        if AppDefaults.memoryEnabled.wrappedValue { allTools.append(UpdateMemoryTool()) }
        if networkAvailable {
            if AppDefaults.toolWebSearch.wrappedValue { allTools.append(WebSearchTool()) }
            if AppDefaults.toolFetchURL.wrappedValue { allTools.append(FetchUrlTool()) }
        }

        var unavailable: [String] = []
        if !AppDefaults.toolGetLocation.wrappedValue { unavailable.append("get_location") }
        if !AppDefaults.toolWeather.wrappedValue { unavailable.append("weather") }
        if !AppDefaults.toolCalendar.wrappedValue { unavailable.append("calendar") }
        if !AppDefaults.memoryEnabled.wrappedValue { unavailable.append("update_memory") }
        if !networkAvailable || !AppDefaults.toolWebSearch.wrappedValue { unavailable.append("web_search") }
        if !networkAvailable || !AppDefaults.toolFetchURL.wrappedValue { unavailable.append("fetch_url") }
        if !unavailable.isEmpty {
            augmentedPrompt += "\n\n<tool_availability>\nUnavailable this turn: \(unavailable.joined(separator: ", ")). Do NOT call them. If the user needs one, say it is unavailable instead of fabricating.\n</tool_availability>"
        }
        if ProviderManager.shared.thinkingMode {
            augmentedPrompt += "\n\n<reasoning>\nThink step by step for complex problems. Keep reasoning concise. For simple Q&A answer directly without overthinking.\n</reasoning>"
        }

        let toolKey = [
            AppDefaults.toolGetLocation.wrappedValue,
            AppDefaults.toolWeather.wrappedValue,
            AppDefaults.toolCalendar.wrappedValue,
            AppDefaults.memoryEnabled.wrappedValue,
            networkAvailable,
            AppDefaults.toolWebSearch.wrappedValue,
            AppDefaults.toolFetchURL.wrappedValue,
        ].map(String.init).joined(separator: "-")
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

        let effectiveMaxTokens = maxNumTokens ?? pm.maxNumTokens
        let systemTokensBeforeSummary = await pm.tokenizeCount(augmentedPrompt)

        let messageTokenCounts = await pm.tokenizeMessages(messages)
        let budgetResult = ContextTracker.calculateIncluded(
            messages: messages,
            tokenCounts: messageTokenCounts,
            systemPromptTokens: systemTokensBeforeSummary,
            memoryTokens: 0,
            toolTokens: toolDefTokens,
            maxNumTokens: effectiveMaxTokens
        )

        let includedMessages = budgetResult.included
        if budgetResult.needsSummary,
           !budgetResult.dropped.isEmpty {
            if let summary = await summarizeOldContext(dropped: budgetResult.dropped) {
                LamoLogger.engine.info("Auto-summary: \(budgetResult.dropped.count) messages → \(summary.count) chars")
                augmentedPrompt += "\n\n<earlier_context_summary>\n\(summary)\n</earlier_context_summary>"
                let conversationID = messages.first?.conversationID
                if let conversationID {
                    await MemoryService.shared.updateConversationSummary(summary, conversationID: conversationID)
                }
            }
        }
        let systemTokens = await pm.tokenizeCount(augmentedPrompt)

        await AgenticLoopBudget.shared.reset()

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

        let conversationTokens = includedMessages.reduce(0) { acc, msg in
            acc + (messageTokenCounts[msg.id] ?? AgenticLoopBudget.estimateTokens(of: msg.content))
        }
        await AgenticLoopBudget.shared.configure(
            totalBudget: effectiveMaxTokens,
            systemOverhead: systemTokens + toolDefTokens,
            conversationSkeletonTokens: conversationTokens,
            maxIterations: 5
        )

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

    static func currentTimeBlock(messageCount: Int, now: Date = Date()) -> String {
        Self.formatterLock.lock()
        defer { Self.formatterLock.unlock() }
        let todayStr = Self.dateFormatter.string(from: now)
        let timeStr = Self.timeFormatter.string(from: now)
        let weekdayStr = Self.weekdayFormatter.string(from: now)
        if messageCount <= 1 {
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

            <current_time>
              iso_date: \(todayStr)
              time: \(timeStr)
              weekday: \(weekdayStr)
            </current_time>
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

    func summarizeOldContext(dropped: [ChatMessage]) async -> String? {
        guard !dropped.isEmpty else { return nil }

        let capped = Array(dropped.suffix(20))
        var conversationText = capped.map { msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.prefix(500)
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
            let guardrails = GenerationGuardrails.summarization
            var summaryText = ""
            for try await chunk in summaryConv.sendMessageStream(
                LiteRTLM.Message(""),
                repetitionPenaltyConfig: guardrails.repetitionPenaltyConfig,
                noRepeatNgramConfig: guardrails.noRepeatNgramConfig,
                maxOutputTokens: guardrails.maxOutputTokens
            ) {
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
