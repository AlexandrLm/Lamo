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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty || !pendingFiles.isEmpty else { return }

        // 1) Save pending images to tmp directory
        var imagePaths = saveImagesToTmp(pendingImages)
        pendingImages = []

        // 2) Process attached files
        let filesToProcess = pendingFiles
        pendingFiles = []

        Task { @MainActor in
            var fileTextParts: [String] = []
            var filePaths: [String] = []
            var fileNames: [String] = []
            var fileSizes: [String] = []

            for file in filesToProcess {
                if file.isImage {
                    if let data = try? Data(contentsOf: file.url),
                       let image = UIImage(data: data) {
                        let paths = saveImagesToTmp([image])
                        imagePaths.append(contentsOf: paths)
                    }
                } else if file.isAudio {
                    let tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("audio_\(UUID().uuidString).\(file.url.pathExtension)")
                    do {
                        try FileManager.default.copyItem(at: file.url, to: tmpURL)
                        filePaths.append(tmpURL.path)
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                        fileTextParts.append("[Аудиофайл: \(file.name)]")
                    } catch {
                        LamoLogger.ui.error("Failed to copy audio file: \(error)")
                    }
                } else if file.type.conforms(to: .pdf) {
                    // PDF: text layer → extract text, scanned → render as images
                    let accessing = file.url.startAccessingSecurityScopedResource()
                    if FileContentExtractor.pdfHasTextLayer(file.url) {
                        do {
                            let extracted = try await FileContentExtractor.extract(from: file.url)
                            fileTextParts.append(extracted)
                            let tmpURL = FileManager.default.temporaryDirectory
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
                        fileTextParts.append("[Сканированный PDF: \(file.name) — \(pageImages.count) стр. отправлены как изображения]")
                    }
                    if accessing { file.url.stopAccessingSecurityScopedResource() }
                } else {
                    do {
                        let extracted = try await FileContentExtractor.extract(from: file.url)
                        fileTextParts.append(extracted)
                        let tmpURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("file_\(UUID().uuidString).\(file.url.pathExtension)")
                        try? FileManager.default.copyItem(at: file.url, to: tmpURL)
                        filePaths.append(tmpURL.path)
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                    } catch {
                        fileTextParts.append("[Ошибка чтения файла \(file.name): \(error.localizedDescription)]")
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                        LamoLogger.ui.error("Failed to extract file content: \(error)")
                    }
                }
            }

            // File content goes to separate field — NOT into message text
            let extractedFileContent = fileTextParts.joined(separator: "\n\n")

            // User message — clean text only
            let userMessage = Message(
                content: text,
                role: .user,
                imagePaths: imagePaths,
                attachedFilePaths: filePaths,
                attachedFileNames: fileNames,
                attachedFileSizes: fileSizes,
                fileContent: extractedFileContent,
                conversation: conversation
            )
            addMessage(userMessage)
            inputText = ""

            // Add empty assistant placeholder
            let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
            addMessage(assistantMessage)
            streamingMessageID = assistantMessage.id
            isStreaming = true

            // Update title
            let titleText = text.isEmpty
                ? (fileNames.first.map { "📎 \($0)" } ?? "New Chat")
                : String(text.prefix(40))
            if conversation.title == "New Chat" {
                conversation.title = titleText
            }

            // Build chat history from current messages
            let history = self.chatMessages

            // Stream response
            MemoryService.shared.currentConversationID = conversation.id
            startStreaming(chatMessages: history)
        }
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

        let history = self.chatMessages

        startStreaming(chatMessages: history)
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
        // Cancel any in-flight streaming
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
                    guard let id = self.streamingMessageID,
                          let index = self.messages.firstIndex(where: { $0.id == id }) else { continue }
                    self.messages[index].content += delta
                case .thinkingDelta(let thought):
                    guard let id = self.streamingMessageID,
                          let index = self.messages.firstIndex(where: { $0.id == id }) else { continue }
                    self.messages[index].thinkingContent += thought
                case .benchmark(let data):
                    self.pendingBenchmark = data
                case .loopDetected:
                    if retryCount < maxRetries {
                        // Auto-retry: clear generated text, invalidate cache for new seed
                        LamoLogger.engine.warning("Loop detected, retry #\(retryCount + 1)")
                        if let id = self.streamingMessageID,
                           let index = self.messages.firstIndex(where: { $0.id == id }) {
                            self.messages[index].content = ""
                            self.messages[index].thinkingContent = ""
                        }
                        // Invalidate conversation cache for fresh seed (breaks the loop)
                        (ProviderManager.shared.currentProvider as? LiteRTLMProvider)?.invalidateConversationCache()
                        self.startStreaming(chatMessages: chatMessages, retryCount: retryCount + 1)
                        return
                    } else {
                        // All retries exhausted
                        if let id = self.streamingMessageID,
                           let index = self.messages.firstIndex(where: { $0.id == id }) {
                            self.messages[index].content += "\n\n⚠️ Генерация остановлена — зацикливание не удалось устранить"
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
            // Auto-fetch URLs that the model mentioned but didn't actually fetch
            // (common with small models like E2B that generate text about tools
            // instead of actually calling them)
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
    private func autoFetchUnfetchedURLs(from response: String) async {
        // Extract all URLs from the response
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
        let lowerResponse = response.lowercased()
        let hasFetchIntent = Self.fetchIntentPatterns.contains { lowerResponse.contains($0) }

        // Also check if the response is short (< 300 chars) and contains a URL
        // — likely the model stopped before fetching
        let looksUnfinished = response.count < 500 && hasFetchIntent

        guard hasFetchIntent else { return }

        // De-duplicate: skip URLs that appear in very short snippets (< 20 chars around them)
        // which usually means the model already fetched and quoted them
        let unfetchedURLs = urls.filter { url in
            // Check if there's substantial content near the URL (> 100 chars of text around it)
            if let urlRange = response.range(of: url.absoluteString) {
                let beforeStart = response.index(urlRange.lowerBound, offsetBy: -100, limitedBy: response.startIndex) ?? response.startIndex
                let afterEnd = response.index(urlRange.upperBound, offsetBy: 100, limitedBy: response.endIndex) ?? response.endIndex
                let nearbyText = String(response[beforeStart..<afterEnd])
                // If there's a lot of text around the URL, it was probably fetched
                return nearbyText.count < 150
            }
            return true
        }

        guard !unfetchedURLs.isEmpty else { return }

        LamoLogger.ui.info("Auto-fetching \(unfetchedURLs.count) unfetched URLs")

        // Fetch the URLs
        var fetchedContent = ""
        for url in unfetchedURLs.prefix(2) { // Max 2 URLs to avoid token overflow
            do {
                let content = try await WebFetcher.fetch(url: url)
                fetchedContent += "\n\n[Содержимое страницы \(url.absoluteString)]:\n\(content.prefix(3000))"
            } catch {
                fetchedContent += "\n\n[Не удалось загрузить \(url.absoluteString): \(error.localizedDescription)]"
            }
        }

        guard !fetchedContent.isEmpty else { return }

        // Send fetched content as a follow-up user message and re-trigger the model
        let followUp = Message(
            content: "Вот содержимое страниц, которые вы хотели проверить:\(fetchedContent)\n\nТеперь, основываясь на этой информации, ответьте на вопрос пользователя.",
            role: .user,
            conversation: conversation
        )
        addMessage(followUp)

        // Re-trigger streaming with updated history
        let history = self.chatMessages

        // Add empty assistant placeholder
        let assistantMessage = Message(content: "", role: .assistant, isStreaming: true, conversation: conversation)
        addMessage(assistantMessage)
        streamingMessageID = assistantMessage.id
        isStreaming = true

        startStreaming(chatMessages: history)
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