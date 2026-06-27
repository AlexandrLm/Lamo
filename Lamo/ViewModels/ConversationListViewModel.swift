import Foundation
import SwiftData

@MainActor
@Observable
final class ConversationListViewModel {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createConversation() -> Conversation {
        let conversation = Conversation()
        modelContext.insert(conversation)
        save()
        return conversation
    }

    func deleteConversations(_ conversations: IndexSet, from allConversations: [Conversation]) {
        for index in conversations {
            let conversation = allConversations[index]
            modelContext.delete(conversation)
        }
        save()
    }

    private func save() {
        try? modelContext.save()
    }
}
