import Foundation
import SwiftData
import UIKit
import PhotosUI
import os

@MainActor
@Observable
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isStreaming: Bool = false
    /// Current context window usage breakdown.
    var contextTracker: ContextTracker?
    /// Images attached to the current input, waiting to be sent.
    var pendingImages: [UIImage] = []
    /// Benchmark data captured from the last inference response.
    private var pendingBenchmark: BenchmarkData?

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

        // Wire up memory service with the SwiftData context
        MemoryService.shared.setModelContext(modelContext)

        // Build initial context tracker
        Task { await refreshContextTracker() }
    }

    func send() {
        Task { await refreshContextTracker() }
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
            .map { ChatMessage(id: $0.id, role: $0.role, content: $0.content, imagePaths: $0.imagePaths) }

        // 6) Stream response
        MemoryService.shared.currentConversationID = conversation.id
        startStreaming(chatMessages: chatMessages)
    }

    func retryLastMessage() {
        Task { await refreshContextTracker() }
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
            .map { ChatMessage(id: $0.id, role: $0.role, content: $0.content, imagePaths: $0.imagePaths) }

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
                case .benchmark(let data):
                    print("[VM] Benchmark received: \(data.decodeTokensPerSec) tok/s")
                    self.pendingBenchmark = data
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
        // Attach benchmark data to the response message
        if let benchmark = pendingBenchmark {
            print("[VM] Saving benchmark to message")
            messages[index].benchmark = benchmark
            pendingBenchmark = nil
        }
        messages[index].isStreaming = false
        streamingMessageID = nil
        isStreaming = false
        conversation.updatedAt = .now
        save()
        Task { await refreshContextTracker() }
        if success == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Auto-generate summary if old messages were dropped from context
            // and the model hasn't created one via update_memory tool yet
            if (contextTracker?.hasDroppedMessages ?? false)
                && conversation.summary.isEmpty && messages.count > 15 {
                Task { await generateConversationSummary() }
            }
        }
    }

    private func addMessage(_ message: Message) {
        messages.append(message)
        conversation.updatedAt = .now
        save()
        Task { await refreshContextTracker() }
    }

    /// Rebuild the context tracker from current messages + settings.
    private func refreshContextTracker() async {
        let pm = ProviderManager.shared
        let chatMessages = messages
            .filter { !$0.content.isEmpty || !$0.imagePaths.isEmpty }
            .map { ChatMessage(id: $0.id, role: $0.role, content: $0.content, imagePaths: $0.imagePaths) }

        // Build full system prompt (mirrors LiteRTLMProvider)
        var fullSystem = pm.systemPrompt
        var memTokens = 0
        if MemoryService.shared.isEnabled {
            fullSystem += "\n\nRemember important user facts via update_memory tool. Summarize long conversations via summary parameter."
            if let ctx = MemoryService.shared.modelContext {
                let id = conversation.id
                let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })
                if let summary = (try? ctx.fetch(descriptor).first?.summary), !summary.isEmpty {
                    fullSystem += "\n\n<conversation_summary>\n\(summary)\n</conversation_summary>"
                }
            }
            let memCtx = MemoryService.shared.buildMemoryContext()
            if !memCtx.isEmpty {
                fullSystem += "\n\n" + memCtx
                memTokens = await pm.tokenizeCount(memCtx)
            }
        }
        let sysTokens = await pm.tokenizeCount(fullSystem)

        // Tokenize all messages with real tokenizer
        let tokenCounts = await pm.tokenizeMessages(chatMessages)

        contextTracker = ContextTracker.build(
            messages: chatMessages,
            tokenCounts: tokenCounts,
            systemPromptTokens: sysTokens,
            memoryTokens: memTokens,
            maxNumTokens: pm.currentMaxTokens ?? pm.maxNumTokens
        )
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            LamoLogger.general.error("SwiftData save error: \(error)")
        }
    }

    /// Generate a basic summary from dropped messages as a fallback.
    /// The model can override this with a better summary via update_memory(summary:) tool.
    private func generateConversationSummary() async {
        guard let tracker = contextTracker else { return }
        let droppedIDs = Set(tracker.messageUsages.filter { !$0.isInContext }.map(\.id))
        guard !droppedIDs.isEmpty else { return }

        let droppedMessages = messages
            .filter { droppedIDs.contains($0.id) }
            .prefix(10)
            .map { "[\($0.role == .user ? "User" : "Assistant")]: \($0.content.prefix(150))" }
            .joined(separator: "\n")

        let summary = "Earlier in this conversation:\n\(droppedMessages)"
        conversation.summary = String(summary.prefix(500))
        save()
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
                LamoLogger.ui.error("Failed to save image: \(error)")
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