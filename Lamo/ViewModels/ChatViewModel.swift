import Foundation
import SwiftData
import UIKit
import PhotosUI

@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isStreaming: Bool = false
    /// Images attached to the current input, waiting to be sent.
    var pendingImages: [UIImage] = []

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
        guard !text.isEmpty || !pendingImages.isEmpty else { return }

        // 1) Save pending images to tmp directory
        let imagePaths = saveImagesToTmp(pendingImages)
        pendingImages = []

        // 2) Add user message
        let userMessage = Message(
            content: text,
            role: .user,
            imagePaths: imagePaths,
            conversation: conversation
        )
        addMessage(userMessage)
        inputText = ""

        // 3) Add empty assistant message (streaming placeholder)
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        // 4) Update title from first message
        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(40))
        }

        // 5) Build chat history for the provider (only non-empty messages)
        let chatMessages = messages
            .filter { !$0.content.isEmpty || !$0.imagePaths.isEmpty }
            .map { ChatMessage(role: $0.role, content: $0.content, imagePaths: $0.imagePaths) }

        // 6) Stream response
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
            .filter { !$0.content.isEmpty || !$0.imagePaths.isEmpty }
            .map { ChatMessage(role: $0.role, content: $0.content, imagePaths: $0.imagePaths) }

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

        // Always resolve fresh provider from ProviderManager — if the user
        // switched models in Settings, the old provider wraps a stale engine.
        let provider = ProviderManager.shared.currentProvider
        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await token in provider.streamResponse(messages: chatMessages) {
                guard !Task.isCancelled else { break }
                switch token {
                case .delta(let delta):
                    guard let id = self.streamingMessageID,
                          let index = self.messages.firstIndex(where: { $0.id == id }) else { continue }
                    self.messages[index].content += delta
                case .thinkingDelta(let thought):
                    guard let id = self.streamingMessageID,
                          let index = self.messages.firstIndex(where: { $0.id == id }) else { continue }
                    self.messages[index].thinkingContent += thought
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

            // Extract facts from this turn for cross-conversation memory
            if let userMsg = messages.last(where: { $0.role == .user }),
               !userMsg.content.isEmpty {
                let assistantContent = messages[index].content
                let convID = conversation.id
                let provider = ProviderManager.shared.currentProvider
                Task {
                    MemoryService.shared.setModelContext(modelContext)
                    await MemoryService.shared.extractAndStore(
                        userMessage: userMsg.content,
                        assistantResponse: assistantContent,
                        conversationID: convID,
                        provider: provider
                    )
                }
            }
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

    /// Save UIImages to tmp directory as JPEG (resized to max 1024px), return file paths.
    private func saveImagesToTmp(_ images: [UIImage]) -> [String] {
        var paths: [String] = []
        for image in images {
            let resized = image.resizedForModel(maxDimension: 1024)
            guard let data = resized.jpegData(compressionQuality: 0.8) else { continue }
            let filename = "img_\(UUID().uuidString).jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                paths.append(url.path)
            } catch {
                print("[Lamo] Failed to save image: \(error)")
            }
        }
        return paths
    }
}

// MARK: - UIImage Resize for Model

private extension UIImage {
    /// Resize image so the longest side is `maxDimension` pixels.
    /// Reduces token usage and memory without losing visual quality for the model.
    func resizedForModel(maxDimension: CGFloat) -> UIImage {
        let size = self.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
