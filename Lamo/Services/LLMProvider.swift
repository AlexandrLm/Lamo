import Foundation

/// Benchmark stats captured after each inference response.
struct BenchmarkData: Codable, Sendable {
    let timeToFirstToken: Double   // seconds
    let decodeTokensPerSec: Double // tok/s
    let decodeTokenCount: Int      // total decoded tokens
    let prefillTokensPerSec: Double // tok/s (for context)
    let prefillTokenCount: Int
}

enum StreamingToken: @unchecked Sendable {
    case delta(String)
    case thinkingDelta(String)
    case benchmark(BenchmarkData)
    case done
    case error(any Error & Sendable)
}

struct ChatMessage: Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let imagePaths: [String]

    init(id: UUID = UUID(), role: MessageRole, content: String, imagePaths: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePaths = imagePaths
    }
}

protocol LLMProvider: Sendable {
    var name: String { get }
    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken>
}
