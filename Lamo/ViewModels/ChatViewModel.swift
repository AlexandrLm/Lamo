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
    var pendingImages: [PendingImage] = []
    /// Non-image files attached to the current input, waiting to be sent.
    var pendingFiles: [PendingFile] = []
    /// Benchmark data captured from the last inference response.
    private var pendingBenchmark: BenchmarkData?

    var conversationTitle: String { conversation.title }

    private let modelContext: ModelContext
    private let conversation: Conversation
    private var streamingMessageID: UUID?
    private var streamingTask: Task<Void, Never>?
    /// Accumulated text buffer during streaming — avoids per-token SwiftData writes.
    private var streamingBuffer: String = ""
    private var streamingThinkingBuffer: String = ""
    /// Timer for throttled SwiftData flushes during streaming.
    private var lastFlushTime: Date = .distantPast
    private let flushInterval: TimeInterval = 0.15 // 150ms throttle

    /// Override for testing. When non-nil, used instead of ProviderManager.shared.currentProvider.
    var llmProviderOverride: (any LLMProvider)?

    init(
        conversation: Conversation,
        modelContext: ModelContext
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        MemoryService.shared.setModelContext(modelContext)
        Task { await refreshContextTracker() }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty || !pendingFiles.isEmpty else { return }

        ProviderManager.shared.lastCompression = nil
        let imagesToProcess = pendingImages
        pendingImages = []
        let filesToProcess = pendingFiles
        pendingFiles = []

        Task { @MainActor in
            let attachments = await AttachmentProcessor.process(
                images: imagesToProcess.map(\.image),
                files: filesToProcess
            )

            let userMessage = Message(
                content: text,
                role: .user,
                imagePaths: attachments.imagePaths,
                attachedFilePaths: attachments.filePaths,
                attachedFileNames: attachments.fileNames,
                attachedFileSizes: attachments.fileSizes,
                fileContent: attachments.extractedText,
                conversation: conversation
            )
            addMessage(userMessage)
            inputText = ""

            let titleText = text.isEmpty
                ? (attachments.fileNames.first.map { "📎 \($0)" } ?? "New Chat")
                : String(text.prefix(40))
            if conversation.title == "New Chat" {
                conversation.title = titleText
            }

            MemoryService.shared.currentConversationID = conversation.id
            startAssistantResponse()
        }
    }

    /// Create a new assistant message and start streaming.
    private func startAssistantResponse() {
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        let history = self.chatMessages
        startStreaming(chatMessages: history)
    }

    func retryLastMessage() {
        // Find the last assistant message — not just messages.last.
        // The last message could be a user message (e.g. after an error).
        guard let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        let lastMsg = messages[lastAssistantIdx]

        messages.remove(at: lastAssistantIdx)
        modelContext.delete(lastMsg)

        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        let history = self.chatMessages

        startStreaming(chatMessages: history)
    }

    func editMessage(_ message: Message) {
        guard message.role == .user else { return }

        // Load message content into input
        inputText = message.content

        // Find index of this message and delete everything after it (including itself)
        let sorted = messages.sorted(by: { $0.timestamp < $1.timestamp })
        guard let idx = sorted.firstIndex(where: { $0.id == message.id }) else { return }

        // Delete all messages from idx onwards — including their attachment files
        for i in idx..<sorted.count {
            let msg = sorted[i]
            // Clean up attachment files (images, documents) to prevent orphans on disk
            for path in msg.imagePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            for path in msg.attachedFilePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            messages.removeAll { $0.id == msg.id }
            modelContext.delete(msg)
        }
        saveWithErrorHandling()
    }

    func stopGeneration() {
        // Cancel the task. onTermination in LiteRTLMProvider's AsyncStream
        // will call conversation.cancel() to stop the native C++ stream.
        streamingTask?.cancel()
        streamingTask = nil
        finalizeStreaming()
    }

    // MARK: - Private

    /// Convert app Messages to lightweight ChatMessages for the engine.
    /// Filters out empty placeholder messages.
    private var chatMessages: [ChatMessage] {
        messages
            .filter { !$0.content.isEmpty || !$0.imagePaths.isEmpty || !$0.attachedFilePaths.isEmpty }
            .map { ChatMessage(
                id: $0.id, role: $0.role, content: $0.content,
                imagePaths: $0.imagePaths,
                attachedFilePaths: $0.attachedFilePaths,
                attachedFileNames: $0.attachedFileNames,
                attachedFileSizes: $0.attachedFileSizes,
                fileContent: $0.fileContent
            ) }
    }

    private func startStreaming(chatMessages: [ChatMessage], retryCount: Int = 0) {
        streamingTask?.cancel()
        streamingTask = nil

        let maxRetries = 2

        // Always resolve fresh provider from ProviderManager — if the user
        // switched models in Settings, the old provider wraps a stale engine.
        // llmProviderOverride is for testing — injected mock takes precedence.
        let provider = llmProviderOverride ?? ProviderManager.shared.currentProvider
        streamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await token in provider.streamResponse(messages: chatMessages) {
                guard !Task.isCancelled else { break }
                switch token {
                case .delta(let delta):
                    self.streamingBuffer += delta
                    self.flushStreamingBuffer()
                case .thinkingDelta(let thought):
                    self.streamingThinkingBuffer += thought
                    self.flushStreamingBuffer()
                case .toolCall(let name, let params):
                    self.addToolCall(name: name, params: params)
                case .toolResult(let name, let result):
                    self.addToolResult(name: name, result: result)
                case .benchmark(let data):
                    self.pendingBenchmark = data
                case .loopDetected:
                    if retryCount < maxRetries {
                        LamoLogger.engine.warning("Loop detected, retry #\(retryCount + 1)")
                        // Delete the botched partial message
                        if let msgIdx = messages.firstIndex(where: { $0.id == self.streamingMessageID }) {
                            modelContext.delete(messages[msgIdx])
                            messages.remove(at: msgIdx)
                        }
                        // Reset streaming state
                        streamingTask?.cancel()
                        streamingBuffer = ""
                        streamingThinkingBuffer = ""
                        streamingMessageID = nil
                        isStreaming = false
                        // Create a fresh message for the retry
                        let retryMsg = Message(content: "[Retrying…]", role: .assistant, isStreaming: true, conversation: conversation)
                        addMessage(retryMsg)
                        streamingMessageID = retryMsg.id
                        startStreaming(chatMessages: chatMessages, retryCount: retryCount + 1)
                        return
                    } else {
                        finalizeStreaming(success: false, error: LamoError.modelStuckInLoop)
                        return
                    }
                case .done:
                    self.finalizeStreaming(success: true)
                    return
                case .error(let err):
                    self.finalizeStreaming(success: false, error: err)
                    return
                }
            }
            // Cancelled or stream ended without .done/.error
            if self.streamingMessageID != nil {
                self.finalizeStreaming()
            }
        }
    }

    /// Flush accumulated streaming text to the SwiftData model, throttled to avoid disk thrashing.
    private func flushStreamingBuffer(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastFlushTime) >= flushInterval else { return }
        guard !streamingBuffer.isEmpty || !streamingThinkingBuffer.isEmpty else { return }
        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }

        if !streamingBuffer.isEmpty {
            messages[index].content += streamingBuffer
            streamingBuffer = ""
        }
        if !streamingThinkingBuffer.isEmpty {
            messages[index].thinkingContent += streamingThinkingBuffer
            streamingThinkingBuffer = ""
        }
        lastFlushTime = now
    }


    // MARK: - Tool Call Tracking

    private func addToolCall(name: String, params: String) {
        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var calls = messages[index].toolCalls
        calls.append(ToolCallRecord(name: name, params: params))
        messages[index].toolCalls = calls
        try? modelContext.save()
    }

    private func addToolResult(name: String, result: String) {
        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var calls = messages[index].toolCalls
        if let i = calls.lastIndex(where: { $0.name == name && $0.result == nil }) {
            calls[i].result = trimToolResult(result)
            messages[index].toolCalls = calls
            try? modelContext.save()
        }
    }

    /// Truncate large fields in tool result JSON to save storage.
    private func trimToolResult(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return json
        }
        // For search results: truncate "content" in each result item
        if let results = obj["results"] as? [[String: Any]] {
            obj["results"] = results.map { item in
                var m = item
                if let c = m["content"] as? String, c.count > 300 {
                    m["content"] = String(c.prefix(300)) + "…"
                }
                return m
            }
        }
        // Also handle direct arrays (web_search returns array of results)
        guard let trimmed = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: trimmed, encoding: .utf8) else {
            return json
        }
        return str
    }

    /// Finalize streaming state. Called on completion, error, or cancellation.
    private func finalizeStreaming(success: Bool? = nil, error: Error? = nil) {
        // Flush any remaining buffered text to the SwiftData model
        flushStreamingBuffer(force: true)

        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            isStreaming = false
            streamingMessageID = nil
            streamingBuffer = ""
            streamingThinkingBuffer = ""
            return
        }
        if success == false, let error {
            messages[index].content = "Error: \(error.localizedDescription)"
        }
        if let benchmark = pendingBenchmark {
            messages[index].benchmark = benchmark
            pendingBenchmark = nil
        }
        // Clear fileContent from older user messages — already processed by model
        for i in 0..<messages.count {
            if messages[i].role == .user && messages[i].id != messages.last(where: { $0.role == .user })?.id {
                messages[i].fileContent = ""
            }
        }
        messages[index].isStreaming = false
        streamingMessageID = nil
        isStreaming = false
        streamingBuffer = ""
        streamingThinkingBuffer = ""
        conversation.updatedAt = .now
        save()
        // Free memory AFTER save: clear fileContent (transient), keep thinking visible
        messages[index].fileContent = ""
        Task { await refreshContextTracker() }
        if success == true {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Proactive summarization: if KV-cache exceeds configured threshold, compress.
            let threshold = ProviderManager.shared.compressionThreshold
            if let tracker = contextTracker,
               tracker.fillRatio > threshold,
               messages.count > 6 {
                Task { await compressConversation() }
            }
            // Fallback: if messages were dropped from context, generate a basic summary.
            if (contextTracker?.hasDroppedMessages ?? false)
                && conversation.summary.isEmpty && messages.count > 15 {
                Task { await generateConversationSummary() }
            }
            Task { await refreshContextTracker() }
        }
    }

    private func addMessage(_ message: Message) {
        messages.append(message)
        conversation.updatedAt = .now
        save()
    }

    /// Rebuild the context tracker from current messages + settings.
    private func refreshContextTracker() async {
        let pm = ProviderManager.shared
        let currentChatMessages = self.chatMessages

        let fullSystem = MemoryService.shared.buildFullSystemPrompt(
            base: pm.systemPrompt,
            conversationID: conversation.id
        )

        let memCtx = MemoryService.shared.buildMemoryContext()
        let memTokens = memCtx.isEmpty ? 0 : await pm.tokenizeCount(memCtx)
        let sysTokens = await pm.tokenizeCount(fullSystem)

        let tokenCounts = await pm.tokenizeMessages(currentChatMessages)

        contextTracker = ContextTracker.build(
            messages: currentChatMessages,
            tokenCounts: tokenCounts,
            systemPromptTokens: sysTokens,
            memoryTokens: memTokens,
            toolTokens: pm.lastToolTokens,
            toolCount: pm.lastToolCount,
            toolCountTotal: pm.lastToolCountTotal,
            maxNumTokens: pm.currentMaxTokens ?? pm.maxNumTokens
        )
    }

    private func save() {
        saveWithErrorHandling()
    }

    /// Save with error logging — never silently swallows SwiftData errors.
    private func saveWithErrorHandling() {
        do {
            try modelContext.save()
        } catch {
            LamoLogger.general.error("SwiftData save error: \(error)")
        }
    }

    /// Generate a basic summary from dropped messages as a fallback.
    /// Skipped if the model already provided a summary via update_memory tool.
    private func generateConversationSummary() async {
        guard let tracker = contextTracker else { return }
        // Skip if the model already generated a summary via update_memory
        guard conversation.summary.isEmpty else { return }

        let droppedIDs = Set(tracker.messageUsages.filter { !$0.isInContext && !$0.isStreaming }.map(\.id))
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

    /// Compress conversation history using LLM summarization when KV-cache exceeds 60%.
    /// Stores result in conversation.summary, which is injected into system prompt on next turn.
    private func compressConversation() async {
        // Don't compress if already done recently (summary exists and messages haven't doubled since)
        if !conversation.summary.isEmpty, messages.count < 25 { return }

        let chatMessages = self.chatMessages
        guard chatMessages.count > 4 else { return }

        // Exclude the last exchange (user+assistant) — keep context for continuity
        let toCompress = Array(chatMessages.dropLast(2))
        guard toCompress.count >= 4 else { return }

        guard let summary = await ProviderManager.shared.summarizeMessages(toCompress) else { return }

        // Guard: user may have sent a new message while we were summarizing.
        // Don't show a stale compression card over new streaming content.
        guard !isStreaming, streamingMessageID == nil else { return }

        conversation.summary = summary
        save()
        MemoryService.shared.invalidateCaches()
        ProviderManager.shared.lastCompression = (oldCount: toCompress.count, summary: summary)
        LamoLogger.ui.info("Conversation compressed: \(toCompress.count) messages → \(summary.count) chars summary")
    }

}