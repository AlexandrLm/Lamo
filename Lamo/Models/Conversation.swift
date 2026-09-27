import Foundation
import SwiftData

@Model
final class Conversation {
    #Index<Conversation>([\.updatedAt])

    /// Hard cap for summary length — summaries grow via LLM compression.
    static let maxSummaryChars = 2000

    var id: UUID
    var title: String
    var updatedAt: Date
    /// Summary of older messages that were dropped from context.
    var summary: String
    var isPinned: Bool

    @Relationship(deleteRule: .cascade)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        updatedAt: Date = .now,
        summary: String = "",
        isPinned: Bool = false,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.summary = String(summary.prefix(Self.maxSummaryChars))
        self.isPinned = isPinned
        self.messages = messages
    }
}
