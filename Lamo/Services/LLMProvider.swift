import Foundation

enum StreamingToken: Sendable {
    case delta(String)
    case done
    case error(Error)
}

struct ChatMessage: Sendable {
    let role: MessageRole
    let content: String
}

protocol LLMProvider: Sendable {
    var name: String { get }
    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken>
}
