import Foundation
import SwiftData

/// A single fact extracted from a conversation.
/// Stored as plain text — no vectors, no embedding model needed.
@Model
final class MemoryEntry {
    var id: UUID
    /// The fact itself, e.g. "User is an iOS developer"
    var text: String
    /// Which conversation this fact came from.
    var conversationID: UUID
    /// When this fact was extracted.
    var timestamp: Date
    /// How many times this fact was injected into context.
    var usageCount: Int

    init(
        id: UUID = UUID(),
        text: String,
        conversationID: UUID,
        timestamp: Date = .now,
        usageCount: Int = 0
    ) {
        self.id = id
        self.text = text
        self.conversationID = conversationID
        self.timestamp = timestamp
        self.usageCount = usageCount
    }
}
