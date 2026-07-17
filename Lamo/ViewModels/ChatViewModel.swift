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

        let imagesToProcess = pendingImages
        pendingImages = []
        let filesToProcess = pendingFiles
        pendingFiles = []

        Task { @MainActor in
            let attachments = await processAttachments(
                images: imagesToProcess,
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

    /// Process attached images and files — resize images, extract file content, copy to attachments dir.
    private func processAttachments(
        images: [UIImage],
        files: [PendingFile]
    ) async -> (imagePaths: [String], filePaths: [String], fileNames: [String], fileSizes: [String], extractedText: String) {
        var imagePaths = saveImagesToTmp(images)
        var filePaths: [String] = []
        var fileNames: [String] = []
        var fileSizes: [String] = []
        var fileTextParts: [String] = []

        for file in files {
            let accessing = file.url.startAccessingSecurityScopedResource()
            defer { if accessing { file.url.stopAccessingSecurityScopedResource() } }

            if file.isImage {
                if let data = try? Data(contentsOf: file.url),
                   let image = UIImage(data: data) {
                    let paths = saveImagesToTmp([image])
                    imagePaths.append(contentsOf: paths)
                }
            } else if file.isAudio {
                let tmpURL = ChatViewModel.attachmentsDirectory
                    .appendingPathComponent("audio_\(UUID().uuidString).\(file.url.pathExtension)")
                do {
                    try FileManager.default.copyItem(at: file.url, to: tmpURL)
                    filePaths.append(tmpURL.path)
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                    fileTextParts.append("[Audio file: \(file.name)]")
                } catch {
                    LamoLogger.ui.error("Failed to copy audio file: \(error)")
                }
            } else if file.type.conforms(to: .pdf) {
                if FileContentExtractor.pdfHasTextLayer(file.url) {
                    do {
                        let extracted = try await FileContentExtractor.extract(from: file.url)
                        fileTextParts.append(extracted)
                        let tmpURL = ChatViewModel.attachmentsDirectory
                            .appendingPathComponent("file_\(UUID().uuidString).pdf")
                        try? FileManager.default.copyItem(at: file.url, to: tmpURL)
                        filePaths.append(tmpURL.path)
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                    } catch {
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                        LamoLogger.ui.error("Failed to extract PDF text: \(error)")
                    }
                } else {
                    // Scanned PDF — render pages as images for the multimodal model
                    let pageImages = FileContentExtractor.extractPDFImages(from: file.url)
                    let tmpPaths = saveImagesToTmp(pageImages)
                    imagePaths.append(contentsOf: tmpPaths)
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                    fileTextParts.append("[Scanned PDF: \(file.name) — \(pageImages.count) pages sent as images]")
                }
            } else {
                do {
                    let extracted = try await FileContentExtractor.extract(from: file.url)
                    fileTextParts.append(extracted)
                    let tmpURL = ChatViewModel.attachmentsDirectory
                        .appendingPathComponent("file_\(UUID().uuidString).\(file.url.pathExtension)")
                    try? FileManager.default.copyItem(at: file.url, to: tmpURL)
                    filePaths.append(tmpURL.path)
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                } catch {
                    fileTextParts.append("[Error reading file \(file.name): \(error.localizedDescription)]")
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                    LamoLogger.ui.error("Failed to extract file content: \(error)")
                }
            }
        }

        return (imagePaths, filePaths, fileNames, fileSizes, fileTextParts.joined(separator: "\n\n"))
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
        let provider = ProviderManager.shared.currentProvider
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
                case .benchmark(let data):
                    self.pendingBenchmark = data
                case .loopDetected:
                    if retryCount < maxRetries {
                        LamoLogger.engine.warning("Loop detected, retry #\(retryCount + 1)")
                        // Delete the entire assistant message and create a fresh one.
                        // Content already flushed to SwiftData survives buffer clears, so
                        // we must remove the message from the model entirely.
                        if let oldID = self.streamingMessageID,
                           let index = self.messages.firstIndex(where: { $0.id == oldID }) {
                            let oldMsg = self.messages[index]
                            self.messages.remove(at: index)
                            self.modelContext.delete(oldMsg)
                        }
                        self.streamingBuffer = ""
                        self.streamingThinkingBuffer = ""
                        let newMsg = Message(content: "", role: .assistant, isStreaming: true, conversation: self.conversation)
                        self.addMessage(newMsg)
                        self.streamingMessageID = newMsg.id
                        self.startStreaming(chatMessages: chatMessages, retryCount: retryCount + 1)
                        return
                    } else {
                        if let id = self.streamingMessageID,
                           let index = self.messages.firstIndex(where: { $0.id == id }) {
                            self.messages[index].content += "\n\n⚠️ Generation stopped — loop could not be resolved"
                        }
                        self.finalizeStreaming(success: true)
                        return
                    }
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
        messages[index].isStreaming = false
        streamingMessageID = nil
        isStreaming = false
        streamingBuffer = ""
        streamingThinkingBuffer = ""
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
            Task { await autoFetchUnfetchedURLs(from: messages[index].content) }
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

    // MARK: - Auto-Fetch Unfetched URLs

    /// Heuristic words indicating the model intended to fetch but didn't.
    private static let fetchIntentPatterns = [
        "проверь", "проверю", "посмотрю", "прочитаю", "извлеку", "подождите", "подожди",
        "let me check", "let me read", "let me fetch", "please wait", "i'll check",
        "i will check", "i'll read", "i will read", "i'll fetch", "give me a moment",
        "just a moment", "one moment"
    ]

    /// After streaming completes, detect URLs the model mentioned but didn't actually fetch.
    /// If found, fetch them automatically and send a follow-up so the model can answer.
    /// Skipped if the response contains tool call indicators (model already used tools).
    private func autoFetchUnfetchedURLs(from response: String) async {
        // Skip if the model already used tools — detected by tool call markers in the response.
        // LiteRT-LM tool calls produce JSON blocks with "name" and "arguments" fields.
        let toolCallMarkers = ["\"name\":", "\"arguments\":", "web_search", "fetch_url", "deep_research"]
        let lowerResponse = response.lowercased()
        let hasToolCall = toolCallMarkers.contains { lowerResponse.contains($0) }
        guard !hasToolCall else { return }

        let urlPattern = #"https?://[^\s<>"'\)\],;:!?"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return }
        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: range)

        guard !matches.isEmpty else { return }

        let urls = matches.compactMap { match -> URL? in
            guard let r = Range(match.range, in: response) else { return nil }
            let urlString = String(response[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\\"))
            return URL(string: urlString)
        }.filter { $0.scheme == "http" || $0.scheme == "https" }

        guard !urls.isEmpty else { return }

        // Check if the response looks like a "failed tool call" — model mentioned
        // a URL and expressed intent to fetch but didn't actually do it
        // (lowerResponse already declared above for tool call check)
        let hasFetchIntent = Self.fetchIntentPatterns.contains { lowerResponse.contains($0) }

        guard hasFetchIntent else { return }

        // De-duplicate: skip URLs that appear in very short snippets (< 20 chars around them)
        // which usually means the model already fetched and quoted them
        let unfetchedURLs = urls.filter { url in
            if let urlRange = response.range(of: url.absoluteString) {
                let beforeStart = response.index(urlRange.lowerBound, offsetBy: -100, limitedBy: response.startIndex) ?? response.startIndex
                let afterEnd = response.index(urlRange.upperBound, offsetBy: 100, limitedBy: response.endIndex) ?? response.endIndex
                let nearbyText = String(response[beforeStart..<afterEnd])
                // If there's substantial content near the URL (>500 chars context),
                // the model probably already fetched and quoted it.
                return nearbyText.count < 500
            }
            return true
        }

        guard !unfetchedURLs.isEmpty else { return }

        LamoLogger.ui.info("Auto-fetching \(unfetchedURLs.count) unfetched URLs")

        var fetchedContent = ""
        var fetchedCount = 0
        for url in unfetchedURLs.prefix(2) { // Max 2 URLs to avoid token overflow
            do {
                let content = try await WebFetcher.fetch(url: url)
                fetchedContent += "\n\n[Page content \(url.absoluteString)]:\n\(content.prefix(3000))"
                fetchedCount += 1
            } catch {
                LamoLogger.ui.warning("Auto-fetch failed for \(url): \(error.localizedDescription)")
            }
        }

        // Don't send follow-up if every fetch failed — error messages would confuse the model
        guard fetchedCount > 0 else { return }
        guard !fetchedContent.isEmpty else { return }

        let followUp = Message(
            content: "Here is the content of the pages you wanted to check:\(fetchedContent)\n\nNow, based on this information, answer the user's question.",
            role: .user,
            conversation: conversation
        )
        addMessage(followUp)

        startAssistantResponse()
    }

    /// Save UIImages to Documents/Attachments as JPEG (resized to max 1024px), return file paths.
    /// Stored in Documents so they persist until the conversation is explicitly deleted.
    private func saveImagesToTmp(_ images: [UIImage]) -> [String] {
        let attachmentsDir = Self.attachmentsDirectory
        var paths: [String] = []
        for image in images {
            let resized = image.resizedForModel(maxDimension: 1024)
            guard let data = resized.jpegData(compressionQuality: 0.8) else { continue }
            let filename = "img_\(UUID().uuidString).jpg"
            let url = attachmentsDir.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                paths.append(url.path)
            } catch {
                LamoLogger.ui.error("Failed to save image: \(error)")
            }
        }
        return paths
    }

    /// Shared directory for all attachment files (images, audio, documents).
    static let attachmentsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}