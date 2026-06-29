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
    private let provider: any LLMProvider
    private var streamingMessageID: UUID?
    private var streamingTask: Task<Void, Never>?

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        provider: any LLMProvider
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.provider = provider
        self.messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 1) Add user message
        let userMessage = Message(content: text, role: .user, conversation: conversation)
        addMessage(userMessage)
        inputText = ""

        // 2) Add empty assistant message (streaming placeholder)
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        // 3) Update title from first message
        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(40))
        }

        // 4) Build chat history for the provider (only non-empty messages)
        let chatMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ChatMessage(role: $0.role, content: $0.content) }

        // 5) Stream response
        startStreaming(chatMessages: chatMessages)
    }

    func retryLastMessage() {
        guard let lastMsg = messages.last, lastMsg.role == .assistant else { return }

        // Remove the last assistant message
        messages.removeLast()
        modelContext.delete(lastMsg)

        // Add fresh streaming placeholder
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        let chatMessages = messages
            .filter { !$0.content.isEmpty }
            .map { ChatMessage(role: $0.role, content: $0.content) }

        startStreaming(chatMessages: chatMessages)
    }

    func stopGeneration() {
        // Cancel the task. onTermination in LiteRTLMProvider's AsyncStream
        // will call conversation.cancel() to stop the native C++ stream.
        streamingTask?.cancel()
        streamingTask = nil
        finalizeStreaming()
    }

    // MARK: - Private

    private func startStreaming(chatMessages: [ChatMessage]) {
        // Cancel any in-flight streaming
        streamingTask?.cancel()
        streamingTask = nil

        let provider = self.provider
        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await token in provider.streamResponse(messages: chatMessages) {
                guard !Task.isCancelled else { break }
                switch token {
                case .delta(let delta):
                    guard let id = self.streamingMessageID,
                          let index = self.messages.firstIndex(where: { $0.id == id }) else { continue }
                    self.messages[index].content += delta
                case .done:
                    self.finalizeStreaming(success: true)
                    return
                case .error(let error):
                    self.finalizeStreaming(success: false, error: error)
                    return
                }
            }
            // Cancelled or stream ended without .done/.error
            if self.streamingMessageID != nil {
                self.finalizeStreaming()
            }
        }
    }

    /// Finalize streaming state. Called on completion, error, or cancellation.
    private func finalizeStreaming(success: Bool? = nil, error: Error? = nil) {
        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            isStreaming = false
            streamingMessageID = nil
            return
        }
        if success == false, let error {
            messages[index].content = "Error: \(error.localizedDescription)"
        }
        messages[index].isStreaming = false
        streamingMessageID = nil
        isStreaming = false
        conversation.updatedAt = .now
        save()
        if success == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func addMessage(_ message: Message) {
        messages.append(message)
        conversation.updatedAt = .now
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("[Lamo] SwiftData save error: \(error)")
        }
    }
}
