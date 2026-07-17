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
    case toolCall(name: String, params: String)
    case toolResult(name: String, result: String)
    case benchmark(BenchmarkData)
    case loopDetected
    case done
    case error(any Error & Sendable)
}

struct ChatMessage: Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let imagePaths: [String]
    let attachedFilePaths: [String]
    let attachedFileNames: [String]
    let attachedFileSizes: [String]
    /// Extracted text from attached files, sent as separate context to the model.
    let fileContent: String

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        imagePaths: [String] = [],
        attachedFilePaths: [String] = [],
        attachedFileNames: [String] = [],
        attachedFileSizes: [String] = [],
        fileContent: String = ""
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePaths = imagePaths
        self.attachedFilePaths = attachedFilePaths
        self.attachedFileNames = attachedFileNames
        self.attachedFileSizes = attachedFileSizes
        self.fileContent = fileContent
    }
}

protocol LLMProvider: Sendable {
    var name: String { get }
    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken>
}
