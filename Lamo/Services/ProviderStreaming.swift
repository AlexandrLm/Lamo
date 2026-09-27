import Foundation

/// Shared AsyncStream wrapper for LLM providers.
///
/// Both `FoundationModelsProvider` and `LiteRTLMProvider` had an identical
/// `streamResponse` body (register reporter → run inference → error mapping →
/// reset reporter → cancel on termination). A single helper removes the
/// duplication and guarantees `finish()` is always delivered, even when the
/// inference task is cancelled mid-stream.
enum ProviderStream {
    /// Build a stream that runs `run` and always finishes the continuation.
    static func makeStream(
        messages: [ChatMessage],
        run: @Sendable @escaping (
            [ChatMessage],
            AsyncStream<StreamingToken>.Continuation
        ) async throws -> Void
    ) -> AsyncStream<StreamingToken> {
        AsyncStream { continuation in
            let task = Task {
                await ToolCallReporter.shared.register(continuation: continuation)
                await ToolCallReporter.shared.setConversationID(messages.first?.conversationID)
                do {
                    try await run(messages, continuation)
                } catch {
                    // Cancellation is silent; every other error reaches the UI.
                    if !Task.isCancelled {
                        continuation.yield(.error(error))
                    }
                }
                // finish() is idempotent — safe even if run() already finished.
                continuation.finish()
                await ToolCallReporter.shared.reset()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
