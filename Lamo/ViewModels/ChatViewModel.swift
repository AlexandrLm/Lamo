import Foundation
import SwiftData

@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isStreaming: Bool = false

    private let chatService: ChatService
    private let modelContext: ModelContext
    private let conversation: Conversation
    private var streamingMessageIndex: Int?

    init(conversation: Conversation, modelContext: ModelContext, provider: LLMProvider = AppleIntelligenceProvider()) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.chatService = ChatService(provider: provider)
        self.messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = Message(content: text, role: .user)
        addMessage(userMessage)
        inputText = ""
        updateConversationTitleIfNeeded(firstMessage: text)

        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true)
        addMessage(assistantMessage)
        streamingMessageIndex = messages.count - 1
        isStreaming = true

        let chatMessages = messages.map { ChatMessage(role: $0.role, content: $0.content) }

        chatService.sendMessage(
            messages: chatMessages,
            onToken: { [weak self] accumulated in
                guard let self, let idx = self.streamingMessageIndex else { return }
                self.messages[idx].content = accumulated
            },
            onComplete: { [weak self] in
                guard let self, let idx = self.streamingMessageIndex else { return }
                self.messages[idx].isStreaming = false
                self.streamingMessageIndex = nil
                self.isStreaming = false
                self.conversation.updatedAt = .now
                self.save()
            },
            onError: { [weak self] error in
                guard let self, let idx = self.streamingMessageIndex else { return }
                self.messages[idx].content = "Ошибка: \(error.localizedDescription)"
                self.messages[idx].isStreaming = false
                self.streamingMessageIndex = nil
                self.isStreaming = false
                self.save()
            }
        )
    }

    func stopGeneration() {
        chatService.stopGeneration()
        if let idx = streamingMessageIndex {
            messages[idx].isStreaming = false
        }
        streamingMessageIndex = nil
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
