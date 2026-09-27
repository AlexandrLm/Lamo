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
    /// Memory service used for context building. Injectable so tests can use
    /// per-test instances instead of racing on the shared singleton's context.
    private let memoryService: MemoryService
    @ObservationIgnored private var streamingMessageID: UUID?
    @ObservationIgnored private var streamingTask: Task<Void, Never>?
    /// Throttled buffer for streaming text — avoids per-token SwiftData writes.
    @ObservationIgnored private var streamBuffer = StreamBuffer()
    /// Cache of lightweight ChatMessages — rebuilt only when the message list changes.
    /// Without it, the full history is re-filtered/re-mapped on every access
    /// (tracker, provider, compression — several times per response).
    @ObservationIgnored private var chatMessagesCache: [ChatMessage]?
    /// Token counts per message ID for the chat list — avoids an O(n)
    /// first(where:) lookup per bubble on every render pass.
    /// Excluded from observation: updated in bulk, read as dictionary lookup.
    @ObservationIgnored private(set) var messageTokenCounts: [UUID: Int] = [:]
    /// Cached index of the streaming message — avoids firstIndex(where:) on every flush.
    /// Always validated against streamingMessageID before use (see indexForStreamingMessage()).
    @ObservationIgnored private var streamingIndex: Int?
    /// Shared encoder for tool-call payloads.
    private static let toolEncoder = JSONEncoder()
    /// Reused haptics generator — creating one per response wastes an engine + taptic setup.
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    /// Override for testing. When non-nil, used instead of ProviderManager.shared.currentProvider.
    var llmProviderOverride: (any LLMProvider)?

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        memoryService: MemoryService? = nil
    ) {
        self.conversation = conversation
        self.modelContext = modelContext
        self.memoryService = memoryService ?? .shared
        self.messages = conversation.messages.sorted { $0.timestamp < $1.timestamp }

        // Weak capture: the task must never outlive this view model (and thus the
        // SwiftData container it was created with) — a stray task would later touch
        // a torn-down context. The injected memoryService also isolates tests.
        Task { [weak self] in
            guard let self else { return }
            await self.refreshContextTracker()
        }
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
                ? (attachments.fileNames.first.map { String(localized: "📎 \($0)") } ?? String(localized: "New Chat"))
                : String(text.prefix(40))
            if conversation.title == String(localized: "New Chat") {
                conversation.title = titleText
            }

            startAssistantResponse()
        }
    }

    /// Create a new assistant message and start streaming.
    private func startAssistantResponse() {
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        streamingIndex = messages.firstIndex(where: { $0.id == assistantMessage.id })
        isStreaming = true

        let history = self.chatMessages
        startStreaming(chatMessages: history)
    }

    func retryLastMessage() {
        // Find the last assistant message — not just messages.last.
        // The last message could be a user message (e.g. after an error).
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        retryMessage(lastAssistant)
    }

    /// Regenerate from a specific assistant message: deletes it and everything after it
    /// (mirrors editMessage semantics), then streams a fresh response.
    func retryMessage(_ message: Message) {
        guard message.role == .assistant, !isStreaming else { return }

        // Delete the target message and everything after it — including attachment files
        // to prevent orphans on disk.
        let sorted = messages.sorted(by: { $0.timestamp < $1.timestamp })
        guard let idx = sorted.firstIndex(where: { $0.id == message.id }) else { return }
        let doomed = sorted[idx...]
        let doomedIDs = Set(doomed.map(\.id))
        for msg in doomed {
            // Clean up attachment files (images, documents) to prevent orphans on disk
            for path in msg.imagePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            for path in msg.attachedFilePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            modelContext.delete(msg)
        }
        // Single-pass removal — the old per-item removeAll was O(n²)
        messages.removeAll { doomedIDs.contains($0.id) }
        invalidateChatMessages()
        saveWithErrorHandling()

        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        streamingIndex = messages.firstIndex(where: { $0.id == assistantMessage.id })
        isStreaming = true

        startStreaming(chatMessages: self.chatMessages)
    }

    func editMessage(_ message: Message) {
        guard message.role == .user else { return }

        // Load message content into input
        inputText = message.content

        // Find index of this message and delete everything after it (including itself)
        let sorted = messages.sorted(by: { $0.timestamp < $1.timestamp })
        guard let idx = sorted.firstIndex(where: { $0.id == message.id }) else { return }

        // Delete all messages from idx onwards — including their attachment files
        let doomed = sorted[idx...]
        let doomedIDs = Set(doomed.map(\.id))
        for msg in doomed {
            // Clean up attachment files (images, documents) to prevent orphans on disk
            for path in msg.imagePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            for path in msg.attachedFilePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
            modelContext.delete(msg)
        }
        // Single-pass removal — the old per-item removeAll was O(n²)
        messages.removeAll { doomedIDs.contains($0.id) }
        invalidateChatMessages()
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
    /// Filters out empty placeholder messages. Cached — invalidated on message mutation.
    private var chatMessages: [ChatMessage] {
        if let cached = chatMessagesCache { return cached }
        let built = messages
            .filter { !$0.content.isEmpty || !$0.imagePaths.isEmpty || !$0.attachedFilePaths.isEmpty }
            .map { ChatMessage(
                id: $0.id, role: $0.role, content: $0.content,
                imagePaths: $0.imagePaths,
                attachedFilePaths: $0.attachedFilePaths,
                attachedFileNames: $0.attachedFileNames,
                attachedFileSizes: $0.attachedFileSizes,
                fileContent: $0.fileContent,
                conversationID: conversation.id
            ) }
        chatMessagesCache = built
        return built
    }

    /// Invalidate the ChatMessage cache — call on any message-list mutation.
    private func invalidateChatMessages() {
        chatMessagesCache = nil
    }

    /// Cached index of the streaming message. The cache is validated against
    /// streamingMessageID on every use and falls back to a lookup if stale
    /// (append/delete shifts indices) — amortized O(1) instead of O(n) per flush.
    private func indexForStreamingMessage() -> Int? {
        guard let id = streamingMessageID else { return nil }
        if let idx = streamingIndex,
           messages.indices.contains(idx),
           messages[idx].id == id {
            return idx
        }
        guard let idx = messages.firstIndex(where: { $0.id == id }) else {
            streamingIndex = nil
            return nil
        }
        streamingIndex = idx
        return idx
    }

    private func startStreaming(chatMessages: [ChatMessage], retryCount: Int = 0) {
        streamingTask?.cancel()
        streamingTask = nil

        // Refresh the tracker when generation starts (not only when it finishes),
        // so the context % chip updates immediately on send. The growing reply
        // itself is excluded from "used", so this snapshot stays valid all
        // through streaming. Mostly cache hits — cheap.
        Task { await refreshContextTracker() }

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
                    self.streamBuffer.append(text: delta)
                    self.flushStreamingBuffer()
                case .thinkingDelta(let thought):
                    self.streamBuffer.append(thinking: thought)
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
                        if let msgIdx = indexForStreamingMessage() {
                            modelContext.delete(messages[msgIdx])
                            messages.remove(at: msgIdx)
                        }
                        // Reset streaming state
                        streamingTask?.cancel()
                        streamBuffer.reset()
                        streamingMessageID = nil
                        streamingIndex = nil
                        isStreaming = false
                        invalidateChatMessages()
                        // Create a fresh message for the retry
                        let retryMsg = Message(content: String(localized: "[Retrying…]"), role: .assistant, isStreaming: true, conversation: conversation)
                        addMessage(retryMsg)
                        streamingMessageID = retryMsg.id
                        streamingIndex = messages.firstIndex(where: { $0.id == retryMsg.id })
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
        guard let (text, thinking) = streamBuffer.drain(force: force) else { return }
        guard let index = indexForStreamingMessage() else { return }

        messages[index].content += text
        messages[index].thinkingContent += thinking
    }


    // MARK: - Tool Call Tracking

    private func addToolCall(name: String, params: String) {
        guard let index = indexForStreamingMessage() else { return }
        var calls = messages[index].toolCalls
        calls.append(ToolCallRecord(name: name, params: params))
        messages[index].toolCalls = calls
        try? modelContext.save()
    }

    private func addToolResult(name: String, result: String) {
        guard let index = indexForStreamingMessage() else { return }
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

        guard let index = indexForStreamingMessage() else {
            isStreaming = false
            streamingMessageID = nil
            streamingIndex = nil
            streamBuffer.reset()
            return
        }
        if success == false, let error {
            // Keep any partial content streamed before the failure; surface the error
            // in a dedicated state so the UI can offer a retry action.
            messages[index].errorDescription = error.localizedDescription
        }
        if let benchmark = pendingBenchmark {
            messages[index].benchmark = benchmark
            pendingBenchmark = nil
        }
        // Clear fileContent from older user messages — already processed by model.
        // Hoisted the last-user lookup out of the loop (was O(n²)).
        let lastUserID = messages.last(where: { $0.role == .user })?.id
        for i in 0..<messages.count {
            if messages[i].role == .user && messages[i].id != lastUserID {
                messages[i].fileContent = ""
            }
        }
        messages[index].isStreaming = false
        streamingMessageID = nil
        streamingIndex = nil
        isStreaming = false
        streamBuffer.reset()
        conversation.updatedAt = .now
        saveWithErrorHandling()
        // Free memory AFTER save: clear fileContent (transient), keep thinking visible
        messages[index].fileContent = ""
        invalidateChatMessages()
        if success == true {
            feedbackGenerator.notificationOccurred(.success)
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
        }
        // Single refresh — the old code ran this twice on success.
        Task { await refreshContextTracker() }
    }

    private func addMessage(_ message: Message) {
        messages.append(message)
        invalidateChatMessages()
        conversation.updatedAt = .now
        saveWithErrorHandling()
    }

    /// Rebuild the context tracker from current messages + settings.
    private func refreshContextTracker() async {
        guard !Task.isCancelled else { return }
        let pm = ProviderManager.shared
        let currentChatMessages = self.chatMessages

        // Extract last user message for semantic memory retrieval (RAG).
        let userQuery = messages.last(where: { $0.role == .user })?.content

        let fullSystem = memoryService.buildFullSystemPrompt(
            base: pm.systemPrompt,
            conversationID: conversation.id,
            userQuery: userQuery
        )

        // Memory context is already baked into fullSystem — count it once.
        // Splitting it back out keeps the tracker breakdown honest (memory shown
        // as its own row) without charging the budget twice and dropping
        // messages earlier than necessary.
        let memCtx = memoryService.buildMemoryContext(for: userQuery)
        // Count exactly what the builder sends: full system prompt + the same
        // <current_time> block (ConversationBuilder.currentTimeBlock).
        let timedSystem = fullSystem + ConversationBuilder.currentTimeBlock(messageCount: currentChatMessages.count)
        // Concurrent tokenization — the three counts are independent.
        async let sysTokensTask: Int = pm.tokenizeCount(timedSystem)
        async let tokenCountsTask: [UUID: Int] = pm.tokenizeMessages(currentChatMessages)
        async let memTokensRawTask: Int = pm.tokenizeCount(memCtx)
        let (sysTokens, tokenCounts, memTokensRaw) = await (sysTokensTask, tokenCountsTask, memTokensRawTask)
        let memTokens = memCtx.isEmpty ? 0 : memTokensRaw
        messageTokenCounts = tokenCounts

        contextTracker = ContextTracker.build(
            messages: currentChatMessages,
            tokenCounts: tokenCounts,
            systemPromptTokens: max(sysTokens - memTokens, 0),
            memoryTokens: memTokens,
            toolTokens: pm.lastToolTokens,
            toolCount: pm.lastToolCount,
            toolCountTotal: pm.lastToolCountTotal,
            maxNumTokens: pm.currentMaxTokens ?? pm.maxNumTokens
        )
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
        saveWithErrorHandling()
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

        let capped = String(summary.prefix(Conversation.maxSummaryChars))
        conversation.summary = capped
        saveWithErrorHandling()
        memoryService.invalidateCaches()
        ProviderManager.shared.lastCompression = (oldCount: toCompress.count, summary: capped)
        LamoLogger.ui.info("Conversation compressed: \(toCompress.count) messages → \(capped.count) chars summary")
    }

}