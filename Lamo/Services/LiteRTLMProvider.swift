import Foundation
import LiteRTLM

/// Provider that runs a local LLM via Google's LiteRT-LM framework.
/// Supports GPU (Metal) acceleration, streaming, and configurable model path.
struct LiteRTLMProvider: LLMProvider {
    let name = "LiteRT-LM"

    /// Path to the .litertlm model file. If nil, uses default Documents location.
    private let modelPath: String?

    /// Backend selection
    private let useGPU: Bool

    /// Max tokens for KV-cache. nil = model default.
    private let maxNumTokens: Int?

    init(modelPath: String? = nil, useGPU: Bool = true, maxNumTokens: Int? = nil) {
        self.modelPath = modelPath
        self.useGPU = useGPU
        self.maxNumTokens = maxNumTokens
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

    // MARK: - Private

    private func runInference(
        messages: [ChatMessage],
        continuation: AsyncStream<StreamingToken>.Continuation
    ) async throws {
        // Resolve model path
        let resolvedPath = try resolveModelPath()

        // Build engine config
        let backend: Backend = useGPU ? .gpu : .cpu(threadCount: nil)

        let engineConfig = try EngineConfig(
            modelPath: resolvedPath,
            backend: backend,
            visionBackend: nil,
            audioBackend: nil,
            maxNumTokens: maxNumTokens,
            cacheDir: NSTemporaryDirectory(),
            loraRank: nil,
            audioLoraRank: nil
        )

        // Initialize engine (may take several seconds)
        let engine = Engine(engineConfig: engineConfig)
        try await engine.initialize()

        // Build conversation config from message history
        var initialMessages: [LiteRTLM.Message] = []
        for msg in messages {
            let role: Role = msg.role == .user ? .user : .assistant
            initialMessages.append(LiteRTLM.Message(msg.content, role: role))
        }

        let samplerConfig = try SamplerConfig(
            topK: 40,
            topP: 0.95,
            temperature: 0.7,
            seed: nil
        )

        let conversationConfig = ConversationConfig(
            systemMessage: LiteRTLM.Message(
                "You are a helpful, concise assistant. Answer in the same language the user writes in.",
                role: .system
            ),
            initialMessages: initialMessages,
            tools: [],
            samplerConfig: samplerConfig,
            loraPath: nil,
            audioLoraPath: nil,
            enableToolCallStreaming: false
        )

        let conversation = try await engine.createConversation(with: conversationConfig)

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

    private func resolveModelPath() throws -> String {
        // 1. Explicit path
        if let custom = modelPath {
            guard FileManager.default.fileExists(atPath: custom) else {
                throw LiteRTLMError.modelNotFound(custom)
            }
            return custom
        }

        // 2. Default location: Documents/models/*.litertlm
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
