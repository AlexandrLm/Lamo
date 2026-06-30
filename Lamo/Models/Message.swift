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

    @Relationship(inverse: \Conversation.messages)
    var conversation: Conversation?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        content: String,
        thinkingContent: String = "",
        role: MessageRole,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        conversation: Conversation? = nil
    ) {
        self.id = id
        self.content = content
        self.thinkingContent = thinkingContent
        self.roleRaw = role.rawValue
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.conversation = conversation
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}
