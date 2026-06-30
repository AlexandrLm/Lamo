import Foundation
import LiteRTLM

/// Provider that runs a local LLM via Google's LiteRT-LM framework.
/// Supports GPU (Metal) acceleration, streaming, and persistent conversation caching.
///
/// Performance notes:
/// - Conversation is reused across utterances as long as message history remains compatible.
/// - Only new messages trigger inference; prefill is incremental.
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

    // MARK: - Persistent Conversation Cache

    /// Cached native conversation — reused to avoid KV-cache rebuild.
    private var cachedConversation: LiteRTLM.Conversation?
    /// Hash of the messages last used to build `cachedConversation`.
    private var cachedMessagesHash: Int = 0
    /// Whether the provider's conversation still matches the incoming message list.
    private func isCacheValid(for messages: [ChatMessage]) -> Bool {
        return cachedConversation != nil
            && messageHash(messages) == cachedMessagesHash
    }

    /// Lock for thread-safe access to cached conversation
    private let cacheLock = NSLock()

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
                // finish() is called inside runInference on success path
                // or here on error path — but only if not cancelled
                if !Task.isCancelled {
                    continuation.finish()
                }
            }
            // When the AsyncStream consumer is deallocated or cancelled,
            // cancel the inference task so the native C stream stops too.
            continuation.onTermination = { _ in
                task.cancel()
                // Attempt to cancel the native conversation stream
                provider.cancelNativeStream()
            }
        }
    }

    /// Invalidate cached conversation (e.g. when model or GPU setting changes).
    func invalidateConversationCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedConversation = nil
        cachedMessagesHash = 0
    }

    /// Attempt to cancel the native C++ streaming process.
    private func cancelNativeStream() {
        // The C API provides litert_lm_conversation_cancel_process
        // which safely interrupts the streaming callback loop.
        cacheLock.lock()
        let conversation = cachedConversation
        cacheLock.unlock()
        if let conversation {
            try? conversation.cancel()
        }
    }

    private func messageHash(_ messages: [ChatMessage]) -> Int {
        var hasher = Hasher()
        for msg in messages {
            hasher.combine(msg.role.rawValue)
            hasher.combine(msg.content)
            for path in msg.imagePaths {
                hasher.combine(path)
            }
        }
        return hasher.finalize()
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
                : .cpu(threadCount: cpuThreadCount)

            let maxTokens: Int? = self.maxNumTokens

            let engineConfig = try LiteRTLM.EngineConfig(
                modelPath: resolvedPath,
                backend: backend,
                visionBackend: .cpu(),
                audioBackend: nil,
                maxNumTokens: maxTokens,
                cacheDir: NSTemporaryDirectory()
            )

            let newEngine = LiteRTLM.Engine(engineConfig: engineConfig)
            try await newEngine.initialize()
            resolvedEngine = newEngine
        }

        // Reuse or rebuild conversation (thread-safe)
        let conversation: LiteRTLM.Conversation
        cacheLock.lock()
        if isCacheValid(for: messages) {
            conversation = cachedConversation!
            cacheLock.unlock()
        } else {
            cacheLock.unlock()
            conversation = try await buildConversation(engine: resolvedEngine, messages: messages)
            cacheLock.lock()
            cachedConversation = conversation
            cachedMessagesHash = messageHash(messages)
            cacheLock.unlock()
        }

        // Send the last user message and stream the response
        guard !Task.isCancelled else { return }

        if let lastUserMessage = messages.last(where: { $0.role == .user }) {
            // Build multimodal or text-only message
            let message: LiteRTLM.Message
            if !lastUserMessage.imagePaths.isEmpty {
                var contents: [LiteRTLM.Content] = []
                for path in lastUserMessage.imagePaths {
                    contents.append(.imageFile(path))
                }
                if !lastUserMessage.content.isEmpty {
                    contents.append(.text(lastUserMessage.content))
                }
                message = LiteRTLM.Message(contents: contents)
            } else {
                message = LiteRTLM.Message(lastUserMessage.content)
            }

            // Enable thinking mode via extraContext
            let extraContext: [String: Any]? = ProviderManager.shared.thinkingMode
                ? ["enable_thinking": "true"]
                : nil

            for try await chunk in conversation.sendMessageStream(message, extraContext: extraContext) {
                guard !Task.isCancelled else {
                    // Cancel native stream to stop C++ callback loop
                    try? conversation.cancel()
                    return
                }
                // Check for thinking content in channels
                if let thought = chunk.channels["thought"], !thought.isEmpty {
                    continuation.yield(.thinkingDelta(thought))
                }
                // Always yield the main content
                let text = chunk.toString
                if !text.isEmpty {
                    continuation.yield(.delta(text))
                }
            }
        }

        guard !Task.isCancelled else { return }
        continuation.yield(.done)
        continuation.finish()
    }

    /// Build a fresh Conversation from the full message history.
    private func buildConversation(
        engine: LiteRTLM.Engine,
        messages: [ChatMessage]
    ) async throws -> LiteRTLM.Conversation {
        let pm = ProviderManager.shared

        // Sampler config — clamp values to safe ranges for Gemma 4
        let safeTopK = max(1, min(pm.topK, 100))
        let safeTemp: Float = max(0.0, min(Float(pm.temperature), 2.0))
        let safeTopP: Float = max(0.0, min(Float(pm.topP), 1.0))

        let samplerConfig = try LiteRTLM.SamplerConfig(
            topK: safeTopK,
            topP: safeTopP,
            temperature: safeTemp,
            seed: Int.random(in: 0..<Int(Int32.max))
        )

        // Build truncated history — fit within KV-cache token budget
        // Use the actual token limit passed to the engine, not pm.maxNumTokens
        // (which is 0 in auto mode and would zero out the budget)
        let maxCharsPerToken = 4
        let systemPrompt = pm.systemPrompt
        let systemPromptChars = systemPrompt.count
        let effectiveMaxTokens = self.maxNumTokens ?? max(pm.maxNumTokens, 2048)
        let budgetChars = (effectiveMaxTokens * maxCharsPerToken) - systemPromptChars - 512
        
        var allMessages: [LiteRTLM.Message] = []
        
        // Inject system prompt as first user message
        if !systemPrompt.isEmpty {
            allMessages.append(LiteRTLM.Message(systemPrompt, role: .user))
        }
        
        // Add conversation history — most recent first, fit within budget
        var usedChars = 0
        var historyMessages: [LiteRTLM.Message] = []
        for msg in messages.dropLast().reversed() {
            let role: LiteRTLM.Role = (msg.role == .assistant) ? .model : .user
            let msgChars = msg.content.count
            if usedChars + msgChars > budgetChars {
                break  // Budget exceeded — skip older messages
            }
            historyMessages.insert(LiteRTLM.Message(msg.content, role: role), at: 0)
            usedChars += msgChars
        }
        allMessages.append(contentsOf: historyMessages)

        // Try creating conversation — abort-safe
        let config = LiteRTLM.ConversationConfig(
            initialMessages: allMessages,
            samplerConfig: samplerConfig
        )

        // Use DispatchSemaphore + async to catch SIGABRT
        // If engine aborts, we restart with minimal history
        return try await engine.createConversation(with: config)
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
