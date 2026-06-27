import Foundation
import SwiftData
import UIKit

@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isStreaming: Bool = false

    var conversationTitle: String { conversation.title }

    private let chatService: ChatService
    private let modelContext: ModelContext
    private let conversation: Conversation
    private var streamingMessageID: UUID?

    init(conversation: Conversation, modelContext: ModelContext) {
        self.conversation = conversation
        self.modelContext = modelContext
        // Provider is resolved from ProviderManager each time we send,
        // so settings changes take effect immediately.
        self.chatService = ChatService(provider: ProviderManager.shared.makeProvider())
        self.messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = Message(content: text, role: .user, conversation: conversation)
        addMessage(userMessage)
        inputText = ""
        updateConversationTitleIfNeeded(firstMessage: text)

        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        let chatMessages = messages.map { ChatMessage(role: $0.role, content: $0.content) }

        // Resolve fresh provider from settings on every send
        let provider = ProviderManager.shared.makeProvider()
        let service = ChatService(provider: provider)

        service.sendMessage(
            messages: chatMessages,
            onToken: { [weak self] accumulated in
                guard let self, let id = self.streamingMessageID,
                      let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
                self.messages[index].content = accumulated
            },
            onComplete: { [weak self] in
                guard let self, let id = self.streamingMessageID,
                      let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
                self.messages[index].isStreaming = false
                self.streamingMessageID = nil
                self.isStreaming = false
                self.conversation.updatedAt = .now
                self.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            },
            onError: { [weak self] error in
                guard let self, let id = self.streamingMessageID,
                      let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
                self.messages[index].content = "Ошибка: \(error.localizedDescription)"
                self.messages[index].isStreaming = false
                self.streamingMessageID = nil
                self.isStreaming = false
                self.save()
            }
        )
    }

    func stopGeneration() {
        chatService.stopGeneration()
        if let id = streamingMessageID,
           let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isStreaming = false
        }
        streamingMessageID = nil
        isStreaming = false
    }

    private func addMessage(_ message: Message) {
        messages.append(message)
        conversation.messages.append(message)
        conversation.updatedAt = .now
        save()
    }

    private func updateConversationTitleIfNeeded(firstMessage: String) {
        if conversation.title == "New Chat" {
            let title = String(firstMessage.prefix(40))
            conversation.title = title
        }
    }

    private func save() {
        try? modelContext.save()
    }
}
