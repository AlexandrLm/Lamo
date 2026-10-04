import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os

// MARK: - Foundation Models Provider

/// Provider that uses Apple's on-device Foundation Models (Apple Intelligence).
///
/// Uses `SystemLanguageModel` via `LanguageModelSession` for streaming text generation.
///
/// **Requirements:** A17 Pro / M1+ device, iOS 26+ / macOS 26+, Apple Intelligence enabled.
/// **Context window:** read from `SystemLanguageModel.contextSize` (4096 on current OSes).
///
/// OS-version behavior:
/// - iOS 26: text-only prompts, 3-arg `GenerationOptions` (no `toolCallingMode`),
///   errors surface as `LanguageModelSession.GenerationError`.
/// - iOS 27: image input via `Attachment`, `toolCallingMode: .allowed`,
///   `ContextOptions(reasoningLevel:)` for thinking mode, `LanguageModelError` taxonomy.
///
/// Tool calling is native via the `Tool` protocol (`FoundationModelsTools.swift`);
/// the framework drives the call/result loop internally. The wrapped tools report
/// call/result to the UI through `ToolCallReporter`.
///
/// Streaming yields snapshots of the *accumulated* content, so deltas are computed
/// against a running buffer (treating snapshots as deltas duplicates the output).
final class FoundationModelsProvider: LLMProvider, @unchecked Sendable {
    let name = "Apple Intelligence"

    private let logger = Logger(subsystem: LamoLogger.subsystem, category: "FMProvider")

    /// Fallback context window when the model doesn't report one.
    static let fallbackContextWindowTokens = 4096

    /// Reads the real context window from the system model (iOS 26+ API,
    /// back-deployed). Falls back to 4096 when unavailable (e.g. no SDK).
    static var contextWindowTokens: Int {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.contextSize
        }
#endif
        return fallbackContextWindowTokens
    }

    /// Cap on decoded tokens per response — guards runaway generations.
    /// Kept at half the window so history + system prompt still fit.
    private static var maxResponseTokens: Int {
        max(512, min(2048, contextWindowTokens / 2))
    }

    // MARK: - LLMProvider

    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken> {
        return ProviderStream.makeStream(messages: messages) { [self] msgs, continuation in
            try await self.runInference(messages: msgs, continuation: continuation)
        }
    }

    // MARK: - Inference Pipeline

    private func runInference(
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            continuation.yield(.error(LamoError.foundationModelsUnavailable(
                String(localized: "Requires iOS 26 or macOS 26"))))
            continuation.finish()
            return
        }

        // --- Availability check (single source of truth) ---
        if let reason = FoundationModelsAvailability.unavailabilityReason {
            continuation.yield(.error(LamoError.foundationModelsUnavailable(reason)))
            continuation.finish()
            return
        }

        // --- Build system prompt with memory ---
        let userQuery = messages.last(where: { $0.role == .user })?.content
        let lastUserMessage = messages.last(where: { $0.role == .user })
        let systemPrompt = MemoryService.shared.buildFullSystemPrompt(
            base: ProviderManager.shared.systemPrompt,
            conversationID: messages.first?.conversationID,
            userQuery: userQuery
        )

        // --- Build conversation context from message history ---
        let contextWindow = Self.contextWindowTokens
        let contextPrefix = buildContextPrefix(messages: messages, tokenCap: 800)
        let promptText: String
        if let lastUser = lastUserMessage {
            let userText = buildUserText(from: lastUser)
            promptText = contextPrefix.isEmpty ? userText : contextPrefix + "\n\n" + userText
        } else {
            continuation.yield(.error(LamoError.foundationModelsError(
                String(localized: "No user message found"))))
            continuation.finish(); return
        }

        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            continuation.yield(.error(LamoError.foundationModelsError(
                String(localized: "Empty message — nothing to respond to."))))
            continuation.finish(); return
        }

        // --- Tools: register every enabled tool, let the model decide ---
        let networkAvailable = !DownloadManager.shared.isExpensive
        let tools = FoundationModelsTools.enabledTools(networkAvailable: networkAvailable)

        // Tell the model exactly which capabilities are on/off this turn
        // (settings/offline/routing), so it calls what's available and says
        // "unavailable" instead of fabricating an answer for the rest.
        var unavailable: [String] = []
        if !AppDefaults.toolGetLocation.wrappedValue { unavailable.append("get_location") }
        if !AppDefaults.toolWeather.wrappedValue { unavailable.append("weather") }
        if !AppDefaults.toolCalendar.wrappedValue { unavailable.append("calendar") }
        if !AppDefaults.memoryEnabled.wrappedValue { unavailable.append("update_memory") }
        if !networkAvailable || !AppDefaults.toolWebSearch.wrappedValue { unavailable.append("web_search") }
        if !networkAvailable || !AppDefaults.toolFetchURL.wrappedValue { unavailable.append("fetch_url") }
        let effectiveSystemPrompt = systemPrompt + "\n\n" + ToolPromptSection.build(
            available: tools.map { $0.name },
            unavailable: unavailable
        )

        let toolSchemaTokens = tools.reduce(0) {
            $0 + AgenticLoopBudget.estimateTokens(of: $1.name + " " + $1.description)
        }
        await AgenticLoopBudget.shared.reset()
        await AgenticLoopBudget.shared.configure(
            totalBudget: contextWindow,
            systemOverhead: AgenticLoopBudget.estimateTokens(of: effectiveSystemPrompt) + toolSchemaTokens,
            conversationSkeletonTokens: AgenticLoopBudget.estimateTokens(of: promptText),
            maxIterations: AgenticLoopBudget.defaultMaxIterations
        )

        let session: LanguageModelSession
        if !effectiveSystemPrompt.isEmpty {
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: tools,
                instructions: effectiveSystemPrompt
            )
        } else {
            session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools)
        }

        // toolCallingMode is iOS 27+; the 3-arg init is identical on iOS 26.
        // Temperature is clamped to 0–1 (the FM-supported range; the app's
        // 0–2 slider targets LiteRT — see the Inference settings footnote).
        let temperature = min(max(ProviderManager.shared.temperature, 0), 1)
        let options: GenerationOptions
        if #available(iOS 27.0, macOS 27.0, *) {
            options = GenerationOptions(
                samplingMode: nil,
                temperature: temperature,
                maximumResponseTokens: Self.maxResponseTokens,
                toolCallingMode: .allowed
            )
        } else {
            options = GenerationOptions(
                samplingMode: nil,
                temperature: temperature,
                maximumResponseTokens: Self.maxResponseTokens
            )
        }

        let startTime = Date()
        var firstTokenTime: Date?
        var totalChars = 0
        let repDetector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 5)

        // iOS 27+: real image attachments + optional reasoning level for
        // thinking mode. iOS 26: text-only prompt (model can't see images —
        // buildUserText() already warns it, so it won't hallucinate).
        // ContextOptions overloads are iOS 27+; the plain overloads are iOS 26.
        let stream: LanguageModelSession.ResponseStream<String>
        if #available(iOS 27.0, macOS 27.0, *) {
            let attachments = Self.imageAttachments(for: lastUserMessage)
            if ProviderManager.shared.thinkingMode {
                let contextOptions = ContextOptions(reasoningLevel: .moderate)
                if attachments.isEmpty {
                    stream = session.streamResponse(
                        to: promptText, options: options, contextOptions: contextOptions)
                } else {
                    stream = session.streamResponse(
                        options: options, contextOptions: contextOptions) {
                            for attachment in attachments { attachment }
                            promptText
                        }
                }
            } else if attachments.isEmpty {
                stream = session.streamResponse(to: promptText, options: options)
            } else {
                stream = session.streamResponse(options: options) {
                    for attachment in attachments { attachment }
                    promptText
                }
            }
        } else {
            stream = session.streamResponse(to: promptText, options: options)
        }

        var accumulated = ""
        do {
            for try await snapshot in stream {
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                // The framework streams snapshots of the FULL content so far —
                // emit only the delta. Fast path first (common case), then a
                // longest-common-prefix diff so a mid-stream rewrite neither
                // duplicates nor silently drops text.
                let content = snapshot.content
                guard content != accumulated else { continue }
                let delta: String
                if content.hasPrefix(accumulated) {
                    delta = String(content.dropFirst(accumulated.count))
                } else {
                    let commonLen = content.commonPrefix(with: accumulated).count
                    guard commonLen < content.count, content.count > accumulated.count else {
                        accumulated = content
                        continue
                    }
                    delta = String(content.dropFirst(commonLen))
                }
                accumulated = content
                if delta.isEmpty { continue }

                if firstTokenTime == nil { firstTokenTime = Date() }
                totalChars += delta.utf8.count

                continuation.yield(.delta(delta))

                if repDetector.feed(delta) {
                    continuation.yield(.loopDetected)
                    continuation.finish()
                    return
                }
            }
        } catch {
            if let mapped = Self.mapGenerationError(error, contextWindow: contextWindow) {
                continuation.yield(.error(mapped))
                continuation.finish()
                return
            }
            throw error
        }

        // --- Benchmark ---
        let ttft = firstTokenTime?.timeIntervalSince(startTime) ?? 0
        let elapsed = max(Date().timeIntervalSince(startTime), 0.001)
        continuation.yield(.benchmark(BenchmarkData(
            timeToFirstToken: ttft,
            decodeTokensPerSec: Double(totalChars / 4) / elapsed,
            decodeTokenCount: totalChars / 4,
            prefillTokensPerSec: 0,
            prefillTokenCount: 0
        )))

        continuation.yield(.done)
        continuation.finish()
#else
        continuation.yield(.error(LamoError.foundationModelsUnavailable(
            String(localized: "FoundationModels framework not available in this SDK"))))
        continuation.finish()
#endif
    }

    // MARK: - Error mapping (iOS 26 + iOS 27 taxonomies)

    /// Maps framework generation errors to actionable `LamoError`s.
    /// Returns nil for unknown errors (caller rethrows them).
    /// - iOS 27+: `LanguageModelError` (contextSizeExceeded, guardrailViolation, …)
    /// - iOS 26: `LanguageModelSession.GenerationError` (exceededContextWindowSize, …)
#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    nonisolated static func mapGenerationError(_ error: any Error, contextWindow: Int) -> LamoError? {
        if #available(iOS 27.0, macOS 27.0, *) {
            if let fmError = error as? LanguageModelError {
                switch fmError {
                case .contextSizeExceeded:
                    return .foundationModelsError(String(localized:
                        "Context window exceeded (\(contextWindow) tokens). Start a new conversation or shorten your message."))
                case .unsupportedLanguageOrLocale:
                    return .foundationModelsError(String(localized:
                        "Apple Intelligence doesn't support this language or locale yet. Try a supported language, or switch to a local model in Settings."))
                case .guardrailViolation:
                    return .foundationModelsError(String(localized:
                        "The request was blocked by the model's safety guardrails. Try rephrasing your message."))
                case .refusal:
                    return .foundationModelsError(String(localized:
                        "The model declined to answer that. Try rephrasing your message."))
                case .rateLimited:
                    return .foundationModelsError(String(localized:
                        "Apple Intelligence is rate-limited right now. Wait a bit and try again."))
                default:
                    return nil
                }
            }
            if error is SystemLanguageModel.Error {
                return .foundationModelsError(String(localized:
                    "Apple Intelligence assets are unavailable — the model may still be downloading. Try again later."))
            }
        }
        if let genError = error as? LanguageModelSession.GenerationError {
            switch genError {
            case .exceededContextWindowSize:
                return .foundationModelsError(String(localized:
                    "Context window exceeded (\(contextWindow) tokens). Start a new conversation or shorten your message."))
            case .unsupportedLanguageOrLocale:
                return .foundationModelsError(String(localized:
                    "Apple Intelligence doesn't support this language or locale yet. Try a supported language, or switch to a local model in Settings."))
            case .guardrailViolation:
                return .foundationModelsError(String(localized:
                    "The request was blocked by the model's safety guardrails. Try rephrasing your message."))
            case .refusal:
                return .foundationModelsError(String(localized:
                    "The model declined to answer that. Try rephrasing your message."))
            case .rateLimited:
                return .foundationModelsError(String(localized:
                    "Apple Intelligence is rate-limited right now. Wait a bit and try again."))
            case .assetsUnavailable:
                return .foundationModelsError(String(localized:
                    "Apple Intelligence assets are unavailable — the model may still be downloading. Try again later."))
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - Image attachments (iOS 27+ only)

    /// Loads local image files as FM `Attachment`s. `Attachment` (image input)
    /// is iOS 27+ — on iOS 26 the model is text-only (see `buildUserText`).
    @available(iOS 27.0, macOS 27.0, *)
    nonisolated static func imageAttachments(
        for message: ChatMessage?
    ) -> [Attachment<ImageAttachmentContent>] {
        guard let paths = message?.imagePaths, !paths.isEmpty else { return [] }
        // Cap the batch: each image costs context in a 4K window.
        return paths.prefix(4).compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return Attachment<ImageAttachmentContent>(imageURL: url)
        }
    }
#endif

    // MARK: - Formatting

    private func buildContextPrefix(messages: [ChatMessage], tokenCap: Int = 1500) -> String {
        let lastUserID = messages.last(where: { $0.role == .user })?.id
        let recent = messages.suffix(20).filter { $0.role != .user || $0.id != lastUserID }
        let filtered = recent.filter { !$0.content.isEmpty || !$0.fileContent.isEmpty }

        guard !filtered.isEmpty else { return "" }

        var lines: [String] = []
        var usedTokens = 0
        for msg in filtered.reversed() {
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let text = String(msg.content.prefix(500))
            let line = "[\(roleLabel)]: \(text)"
            usedTokens += AgenticLoopBudget.estimateTokens(of: line)
            if usedTokens > tokenCap { break }
            lines.append(line)
        }
        guard !lines.isEmpty else { return "" }

        return "Previous conversation:\n" + lines.reversed().joined(separator: "\n\n")
    }

    /// File text is capped tighter than LiteRT's 8000 chars: the FM window is
    /// ~4K tokens, so the full file budget goes to the most recent content.
    private static let maxFileChars = 4_000

    private func buildUserText(from msg: ChatMessage) -> String {
        var parts: [String] = []

        if !msg.fileContent.isEmpty {
            parts.append("Attached file content:\n\n\(msg.fileContent.prefix(Self.maxFileChars))")
        }

        if !msg.imagePaths.isEmpty {
            if #available(iOS 27.0, macOS 27.0, *) {
                // Real image bytes travel as Attachments (see runInference);
                // the caption just points the model at them.
                parts.append("[\(msg.imagePaths.count) image\(msg.imagePaths.count > 1 ? "s" : "") attached — look at them]")
            } else {
                // iOS 26 is text-only: forbid hallucinated descriptions.
                parts.append("[\(msg.imagePaths.count) image\(msg.imagePaths.count > 1 ? "s" : "") attached which you CANNOT see (needs iOS 27). Say so briefly, then handle the text.]")
            }
        }

        if !msg.content.isEmpty {
            parts.append(msg.content)
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }
}
