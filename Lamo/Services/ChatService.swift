import Foundation
import SwiftData

@MainActor
final class ChatService {
    private let provider: LLMProvider
    private var currentTask: Task<Void, Never>?

    init(provider: LLMProvider = AppleIntelligenceProvider()) {
        self.provider = provider
    }

    func sendMessage(
        messages: [ChatMessage],
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        currentTask?.cancel()
        currentTask = Task {
            var accumulated = ""

            for await token in provider.streamResponse(messages: messages) {
                if Task.isCancelled { break }

                switch token {
                case .text(let text):
                    accumulated += text
                    onToken(accumulated)
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
