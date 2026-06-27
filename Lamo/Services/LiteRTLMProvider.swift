import Foundation
import LiteRTLM

/// Provider that runs a local LLM via Google's LiteRT-LM framework.
/// Supports GPU (Metal) acceleration, streaming, and persistent conversation caching.
///
/// Performance notes:
/// - Conversation is reused across utterances as long as message history remains compatible.
/// - Only new messages trigger inference; prefill is incremental.
final class LiteRTLMProvider: LLMProvider {
    let name = "LiteRT-LM"

    /// Path to the .litertlm model file.
    private let modelPath: String?

    /// Backend selection
    private let useGPU: Bool

    /// Max tokens for KV-cache. nil = model default.
    private let maxNumTokens: Int?

    /// Cached engine — injected by ProviderManager to avoid reloading.
    private let engine: LiteRTLM.Engine?

    // MARK: - Persistent Conversation Cache

    /// Cached native conversation — reused to avoid KV-cache rebuild.
    private var cachedConversation: LiteRTLM.Conversation?
    /// Hash of the messages last used to build `cachedConversation`.
    private var cachedMessagesHash: Int = 0
    /// Whether the provider's conversation still matches the incoming message list.
    private func isCacheValid(for messages: [ChatMessage]) -> Bool {
        return cachedConversation != nil
            && messages.hashValue == cachedMessagesHash
    }

    init(
        modelPath: String? = nil,
        useGPU: Bool = true,
        maxNumTokens: Int? = 4096,
        engine: LiteRTLM.Engine? = nil
    ) {
        self.modelPath = modelPath
        self.useGPU = useGPU
        self.maxNumTokens = maxNumTokens
        self.engine = engine
    }

    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken> {
        AsyncStream { continuation in
            Task {
                do {
                    try await runInference(messages: messages, continuation: continuation)
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }

    /// Invalidate cached conversation (e.g. when model or GPU setting changes).
    func invalidateConversationCache() {
        cachedConversation = nil
        cachedMessagesHash = 0
    }

    // MARK: - Private

    private func runInference(
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
        // Reuse cached engine, or create new one
        let resolvedEngine: LiteRTLM.Engine
        if let cached = engine {
            resolvedEngine = cached
        } else {
            let resolvedPath = try resolveModelPath()
            let backend: LiteRTLM.Backend = useGPU
                ? .gpu
                : .cpu(threadCount: autoThreadCount)

            let engineConfig = try LiteRTLM.EngineConfig(
                modelPath: resolvedPath,
                backend: backend,
                visionBackend: nil,
                audioBackend: nil,
                maxNumTokens: maxNumTokens,
                cacheDir: NSTemporaryDirectory()
            )

            let newEngine = LiteRTLM.Engine(engineConfig: engineConfig)
            try await newEngine.initialize()
            resolvedEngine = newEngine
        }

        // Reuse or rebuild conversation
        let conversation: LiteRTLM.Conversation
        if isCacheValid(for: messages) {
            conversation = try cachedConversation.unwrap()
        } else {
            conversation = try await buildConversation(engine: resolvedEngine, messages: messages)
            cachedConversation = conversation
            cachedMessagesHash = messages.hashValue
        }

        // Send the last user message and stream the response
        if let lastUserMessage = messages.last(where: { $0.role == .user }) {
            let message = LiteRTLM.Message(lastUserMessage.content)

            for try await chunk in conversation.sendMessageStream(message) {
                if Task.isCancelled { break }
                continuation.yield(.text(chunk.toString))
            }
        }

        continuation.yield(.done)
        continuation.finish()
    }

    /// Build a fresh Conversation from the full message history.
    private func buildConversation(
        engine: LiteRTLM.Engine,
        messages: [ChatMessage]
    ) async throws -> LiteRTLM.Conversation {
        var initialMessages: [LiteRTLM.Message] = []
        for msg in messages.dropLast() {
            let role: LiteRTLM.Role = (msg.role == .assistant) ? .model : .user
            initialMessages.append(LiteRTLM.Message(msg.content, role: role))
        }

        let samplerConfig = try LiteRTLM.SamplerConfig(
            topK: 40,
            topP: 0.95,
            temperature: 0.7,
            seed: Int.random(in: 0..<Int(Int32.max))
        )

        let conversationConfig = LiteRTLM.ConversationConfig(
            systemMessage: LiteRTLM.Message(
                "You are a helpful, concise assistant. Answer in the same language the user writes in.",
                role: .system
            ),
            initialMessages: initialMessages,
            tools: [],
            samplerConfig: samplerConfig
        )

        return try await engine.createConversation(with: conversationConfig)
    }

    /// Auto-select sensible CPU thread count.
    private var autoThreadCount: Int? {
        let cores = ProcessInfo.processInfo.processorCount
        return min(cores, 8) // Cap at 8 to keep UI responsive
    }

    private func resolveModelPath() throws -> String {
        if let custom = modelPath {
            guard FileManager.default.fileExists(atPath: custom) else {
                throw LiteRTLMError.modelNotFound(custom)
            }
            return custom
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")

        guard FileManager.default.fileExists(atPath: modelsDir.path) else {
            throw LiteRTLMError.modelsDirectoryMissing
        }

        let models = try FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "litertlm" }

        guard let first = models.first else {
            throw LiteRTLMError.noModelFound
        }

        return first.path
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
