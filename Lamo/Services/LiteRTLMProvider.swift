import Foundation
@preconcurrency import LiteRTLM
import SwiftData
import os

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
        guard let resolvedEngine = engine else {
            throw LamoError.engineNotReady
        }

        let userQuery = messages.last(where: { $0.role == .user })?.content
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

        let guardrails = GenerationGuardrails.main
        let headroom = await AgenticLoopBudget.shared.headroom
        let maxOut = GenerationGuardrails.maxOutputTokens(headroom: max(headroom, 512))
        for try await chunk in conversation.sendMessageStream(
            message,
            extraContext: extraContext,
            repetitionPenaltyConfig: guardrails.repetitionPenaltyConfig,
            noRepeatNgramConfig: guardrails.noRepeatNgramConfig,
            maxOutputTokens: maxOut
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
