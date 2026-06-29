import Foundation
import SwiftData

/// Service that coordinates streaming LLM responses.
///
/// Design:
/// - Provider yields token **deltas** (not accumulated strings).
/// - Consumers append deltas to build the final response. This avoids
///   per-token string copying and reduces GC / retain churn.
@MainActor
final class ChatService {
    let provider: any LLMProvider
    private var currentTask: Task<Void, Never>?

    init(provider: (any LLMProvider)? = nil) {
        self.provider = provider ?? AppleIntelligenceProvider()
    }

    /// Streaming method that emits **delta** strings.
    ///
    /// - Parameters:
    ///   - messages:   Full message history.
    ///   - onDelta:    Called for every new token chunk.
    ///   - onComplete: Called when the stream ends successfully.
    ///   - onError:    Called if an error occurs.
    func sendMessage(
        messages: [ChatMessage],
        onDelta: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        currentTask?.cancel()
        currentTask = Task {
            for await token in provider.streamResponse(messages: messages) {
                if Task.isCancelled { break }

                switch token {
                case .delta(let text):
                    onDelta(text)   // <- delta, not accumulated string
                case .done:
                    onComplete()
                case .error(let error):
                    onError(error)
                }
            }
        }
    }

    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
    }
}
