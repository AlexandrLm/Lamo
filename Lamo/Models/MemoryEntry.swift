import Foundation
import SwiftData

@Model
final class MemoryEntry {
    var id: UUID
    var text: String
    var conversationID: UUID
    var timestamp: Date
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
