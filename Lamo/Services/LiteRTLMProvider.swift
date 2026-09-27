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
///
/// @unchecked Sendable: required because LiteRTLM.Engine is imported via
/// @preconcurrency and Swift cannot verify its Sendable conformance. All
/// mutable state is protected by OSAllocatedUnfairLock.
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

    /// Cached network availability — checked once per conversation build.
    /// Reuses DownloadManager's NWPathMonitor instead of creating a second one.
    private static func checkNetworkAvailable() -> Bool {
        // DownloadManager runs a continuous NWPathMonitor; isExpensive=true means cellular.
        // We consider network "available" when not on a constrained/expensive connection
        // OR when the user has explicitly allowed cellular downloads.
        return !DownloadManager.shared.isExpensive
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
        let provider = self
        return ProviderStream.makeStream(messages: messages) { msgs, continuation in
            try await provider.runInference(messages: msgs, continuation: continuation)
        }
    }

    // MARK: - Private

    private func runInference(
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
        // The engine is owned by ProviderManager/EngineLifecycle. Lazily
        // creating + initializing one here blocked the streaming path on
        // model-load I/O and duplicated EngineLifecycle config — fail fast
        // instead so the UI can show the real engine state.
        guard let resolvedEngine = engine else {
            throw LamoError.engineNotReady
        }

        // Extract last user message for semantic memory retrieval (RAG).
        let userQuery = messages.last(where: { $0.role == .user })?.content
        // buildFullSystemPrompt already bakes the memory context into the prompt —
        // no separate buildMemoryContext call (avoids re-running RAG and
        // double-counting memory tokens in the budget).
        let systemPrompt = MemoryService.shared.buildFullSystemPrompt(
            base: ProviderManager.shared.systemPrompt,
            conversationID: messages.first?.conversationID,
            userQuery: userQuery
        )
        let networkAvailable = Self.checkNetworkAvailable()

        let builder = ConversationBuilder(
            engine: resolvedEngine,
            modelPath: modelPath,
            useGPU: useGPU,
            cpuThreadCount: cpuThreadCount,
            maxNumTokens: maxNumTokens
        )

        let conversation = try await builder.build(
            messages: messages,
            systemPrompt: systemPrompt,
            networkAvailable: networkAvailable
        )

        guard !Task.isCancelled else {
            continuation.finish()
            return
        }
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

        // Native decode-time guardrails: repetition penalties prevent loops before
        // RepetitionDetector would have to kill the stream, and maxOutputTokens
        // bounds runaway generations (protects the KV-cache budget).
        let guardrails = GenerationGuardrails.main
        for try await chunk in conversation.sendMessageStream(
            message,
            extraContext: extraContext,
            repetitionPenaltyConfig: guardrails.repetitionPenaltyConfig,
            noRepeatNgramConfig: guardrails.noRepeatNgramConfig,
            maxOutputTokens: guardrails.maxOutputTokens
        ) {
            guard !Task.isCancelled else {
                try? conversation.cancel()
                continuation.finish()
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
                    continuation.finish()
                    break
                }
            }
        }

        guard !Task.isCancelled else {
            continuation.finish()
            return
        }

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
    /// Attached-file text is capped at 8000 chars — uncapped PDFs previously
    /// blew the context window before the user prompt was even counted.
    private static let maxFileChars = 8000

    private func buildLiteMessage(from msg: ChatMessage, role: LiteRTLM.Role) -> LiteRTLM.Message {
        if !msg.imagePaths.isEmpty {
            var contents: [LiteRTLM.Content] = msg.imagePaths.map { .imageFile($0) }
            if !msg.fileContent.isEmpty {
                contents.append(.text("Content of attached files:\n\n\(msg.fileContent.prefix(Self.maxFileChars))"))
            }
            if !msg.content.isEmpty {
                contents.append(.text(msg.content))
            }
            return LiteRTLM.Message(contents: contents)
        } else if !msg.fileContent.isEmpty {
            let cappedFiles = String(msg.fileContent.prefix(Self.maxFileChars))
            let fullText: String
            if msg.content.isEmpty {
                fullText = "Analyze the content of the attached files:\n\n\(cappedFiles)"
            } else {
                fullText = "Content of attached files:\n\n\(cappedFiles)\n\n---\n\n\(msg.content)"
            }
            return LiteRTLM.Message(fullText)
        } else {
            return LiteRTLM.Message(msg.content)
        }
    }

}
