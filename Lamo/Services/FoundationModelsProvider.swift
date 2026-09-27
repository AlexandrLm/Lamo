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
/// **Requirements:** A17 Pro / M1+ device, iOS 27+ / macOS 27+, Apple Intelligence enabled.
/// **Context window:** 4096 tokens (managed by the framework).
///
/// iOS 27 notes:
/// - `streamResponse(to:options:)` yields `Snapshot`s of the *accumulated* content,
///   so we compute real deltas against a running buffer (iOS 26 yielded deltas —
///   treating snapshots as deltas duplicated the output).
/// - Tool calling is native via the `Tool` protocol (`FoundationModelsTools.swift`);
///   the framework drives the call/result loop internally. The wrapped tools report
///   call/result to the UI through `ToolCallReporter`.
final class FoundationModelsProvider: LLMProvider, @unchecked Sendable {
    let name = "Apple Intelligence"

    private let logger = Logger(subsystem: LamoLogger.subsystem, category: "FMProvider")

    /// Cap on decoded tokens per response — guards runaway generations.
    private static let maxResponseTokens = 2048

    /// Context window managed by the Foundation Models framework.
    private static let contextWindowTokens = 4096

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
        guard #available(iOS 27.0, macOS 27.0, *) else {
            continuation.yield(.error(LamoError.foundationModelsUnavailable(
                String(localized: "Requires iOS 27 or macOS 27"))))
            continuation.finish()
            return
        }

        // --- Availability check (single source of truth — was a duplicated switch) ---
        if let reason = FoundationModelsAvailability.unavailabilityReason {
            continuation.yield(.error(LamoError.foundationModelsUnavailable(reason)))
            continuation.finish()
            return
        }

        // --- Build system prompt with memory ---
        let userQuery = messages.last(where: { $0.role == .user })?.content
        let systemPrompt = MemoryService.shared.buildFullSystemPrompt(
            base: ProviderManager.shared.systemPrompt,
            conversationID: messages.first?.conversationID,
            userQuery: userQuery
        )

        // --- Build conversation context from message history ---
        let contextPrefix = buildContextPrefix(messages: messages)
        let promptText: String
        if let lastUser = messages.last(where: { $0.role == .user }) {
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

        // --- Native tools + session ---
        let networkAvailable = !DownloadManager.shared.isExpensive
        let tools = FoundationModelsTools.enabledTools(networkAvailable: networkAvailable)

        // --- Agentic loop budget (same protection as the LiteRT path) ---
        // The FM framework manages a 4096-token context window; overhead is estimated
        // with the same conservative estimator AgenticLoopBudget uses for accounting.
        let toolSchemaTokens = tools.reduce(0) {
            $0 + AgenticLoopBudget.estimateTokens(of: $1.name + " " + $1.description)
        }
        await AgenticLoopBudget.shared.reset()
        await AgenticLoopBudget.shared.configure(
            totalBudget: Self.contextWindowTokens,
            systemOverhead: AgenticLoopBudget.estimateTokens(of: systemPrompt) + toolSchemaTokens,
            conversationSkeletonTokens: AgenticLoopBudget.estimateTokens(of: promptText),
            maxIterations: AgenticLoopBudget.defaultMaxIterations
        )

        let session: LanguageModelSession
        if !systemPrompt.isEmpty {
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: tools,
                instructions: systemPrompt
            )
        } else {
            session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools)
        }

        let options = GenerationOptions(
            samplingMode: nil,
            // The framework requires temperature in 0...1; clamp the user setting defensively.
            temperature: min(max(ProviderManager.shared.temperature, 0), 1),
            maximumResponseTokens: Self.maxResponseTokens,
            toolCallingMode: .allowed
        )

        // --- Stream the response (snapshot → delta) ---
        let startTime = Date()
        var firstTokenTime: Date?
        var totalChars = 0
        let repDetector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 5)

        let stream = session.streamResponse(to: promptText, options: options)
        var accumulated = ""
        do {
            for try await snapshot in stream {
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                // iOS 27 streams snapshots of the FULL content so far — emit only the delta.
                // hasPrefix-only check (was content.count >= accumulated.count first,
                // which walks both strings) + single offsetBy pass for the split.
                let content = snapshot.content
                guard content.hasPrefix(accumulated) else {
                    accumulated = content
                    continue
                }
                guard content != accumulated else { continue }
                let splitIndex = content.index(content.startIndex, offsetBy: accumulated.count)
                let delta = String(content[splitIndex...])
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
        } catch let error as LanguageModelError {
            switch error {
            case .contextSizeExceeded:
                continuation.yield(.error(LamoError.foundationModelsError(
                    String(localized: "Context window exceeded (4096 tokens). Start a new conversation or shorten your message."))))
            case .unsupportedLanguageOrLocale:
                continuation.yield(.error(LamoError.foundationModelsError(
                    String(localized: "Apple Intelligence doesn't support this language or locale yet. Try a supported language, or switch to a local model in Settings."))))
            default:
                throw error
            }
            continuation.finish()
            return
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

    // MARK: - Formatting

    /// Build conversation context prefix from message history.
    /// Provides the last few turns so the model has conversational memory.
    private func buildContextPrefix(messages: [ChatMessage]) -> String {
        // Hoisted last-user id — was recomputed inside the filter closure (O(n²)).
        let lastUserID = messages.last(where: { $0.role == .user })?.id
        // Take last 10 messages (5 turns) to stay within 4096 token context
        let recent = messages.suffix(10).filter { $0.role != .user || $0.id != lastUserID }
        let filtered = recent.filter { !$0.content.isEmpty || !$0.fileContent.isEmpty }

        guard !filtered.isEmpty else { return "" }

        let lines = filtered.map { msg in
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let text = msg.content.prefix(300)
            return "[\(roleLabel)]: \(text)"
        }

        return "Previous conversation:\n" + lines.joined(separator: "\n\n")
    }

    /// Build the user prompt text from a ChatMessage.
    private func buildUserText(from msg: ChatMessage) -> String {
        var parts: [String] = []

        if !msg.fileContent.isEmpty {
            parts.append("Attached file content:\n\n\(msg.fileContent)")
        }

        // Images are described inline since Foundation Models multimodal attachment
        // API surface is not wired up yet in this provider (follow-up: Transcript
        // image attachments).
        if !msg.imagePaths.isEmpty {
            parts.append("[Image\(msg.imagePaths.count > 1 ? "s" : "") attached — describe what you see]")
        }

        if !msg.content.isEmpty {
            parts.append(msg.content)
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }
}
