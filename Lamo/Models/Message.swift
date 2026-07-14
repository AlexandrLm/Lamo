import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var content: String
    var thinkingContent: String
    var roleRaw: String
    var timestamp: Date
    var isStreaming: Bool
    /// Paths to attached images (stored in app's tmp directory).
    var imagePaths: [String] = []
    /// JSON-encoded BenchmarkData for this response.
    var benchmarkJSON: String?

    @Relationship(inverse: \Conversation.messages)
    var conversation: Conversation?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var hasImages: Bool { !imagePaths.isEmpty }
    var benchmark: BenchmarkData? {
        get {
            guard let json = benchmarkJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(BenchmarkData.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue) else {
                benchmarkJSON = nil
                return
            }
            benchmarkJSON = String(data: data, encoding: .utf8)
        }
    }

    init(
        id: UUID = UUID(),
        content: String,
        thinkingContent: String = "",
        role: MessageRole,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        imagePaths: [String] = [],
        conversation: Conversation? = nil,
        benchmarkJSON: String? = nil
    ) {
        self.id = id
        self.content = content
        self.thinkingContent = thinkingContent
        self.roleRaw = role.rawValue
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.imagePaths = imagePaths
        self.conversation = conversation
        self.benchmarkJSON = benchmarkJSON
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}