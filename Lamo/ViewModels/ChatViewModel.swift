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

    private let modelContext: ModelContext
    private let conversation: Conversation
    private var streamingMessageID: UUID?

    private let chatService: ChatService

    init(conversation: Conversation, modelContext: ModelContext) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
        self.chatService = ChatService(provider: ProviderManager.shared.currentProvider)
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 1) Add user message
        let userMessage = Message(content: text, role: .user, conversation: conversation)
        addMessage(userMessage)
        inputText = ""
        updateConversationTitleIfNeeded(firstMessage: text)

        // 2) Add empty assistant message (streaming placeholder)
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        // 3) Build chat history for the provider (snapshot before streaming starts)
        let chatMessages = messages.filter { !$0.content.isEmpty || $0.role == .user }
            .map { ChatMessage(role: $0.role, content: $0.content) }

        // 4) Stream response
        let service = chatService
        service.sendMessage(
            messages: chatMessages,
            onDelta: { [weak self] delta in
                guard let self, let id = self.streamingMessageID,
                      let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
                self.messages[index].content += delta
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
                self.messages[index].content = "Error: \(error.localizedDescription)"
                self.messages[index].isStreaming = false
                self.streamingMessageID = nil
                self.isStreaming = false
                self.save()
            }
        )
    }

    func sendDirect(_ text: String) async {
        inputText = text
        await send()
    }

    func retryLastMessage() async {
        guard let lastMsg = messages.last, lastMsg.role == .assistant else { return }

        messages.removeLast()
        modelContext.delete(lastMsg)

        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        let chatMessages = messages.filter { !$0.content.isEmpty || $0.role == .user }
            .map { ChatMessage(role: $0.role, content: $0.content) }

        let service = chatService
        service.sendMessage(
            messages: chatMessages,
            onDelta: { [weak self] delta in
                guard let self, let id = self.streamingMessageID,
                      let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
                self.messages[index].content += delta
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
                self.messages[index].content = "Error: \(error.localizedDescription)"
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
        // message.conversation is already set in Message.init,
        // so SwiftData handles the inverse relationship automatically.
        // Do NOT also append to conversation.messages — that double-adds.
        messages.append(message)
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
        do {
            try modelContext.save()
        } catch {
            print("[Lamo] SwiftData save error: \\(error)")
        }
    }
}
