import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Summary of older messages that were dropped from context.
    var summary: String
    var isPinned: Bool

    @Relationship(deleteRule: .cascade)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        summary: String = "",
        isPinned: Bool = false,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.summary = summary
        self.isPinned = isPinned
        self.messages = messages
    }
}
