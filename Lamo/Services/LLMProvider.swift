import Foundation

enum StreamingToken: Sendable {
    case delta(String)
    case thinkingDelta(String)
    case done
    case error(Error)
}

struct ChatMessage: Sendable {
    let role: MessageRole
    let content: String
    let imagePaths: [String]

    init(role: MessageRole, content: String, imagePaths: [String] = []) {
        self.role = role
        self.content = content
        self.imagePaths = imagePaths
    }
}

protocol LLMProvider: Sendable {
    var name: String { get }
    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken>
}
