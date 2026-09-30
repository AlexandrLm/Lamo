import Foundation
import SwiftData
import Testing
import UIKit
@testable import Lamo

// MARK: - Test Doubles

/// Mock LLMProvider that yields a configurable sequence of tokens.
final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    let name = "Mock"
    var tokens: [StreamingToken] = []
    /// When false, the stream stays open after the last token (never calls finish()) —
    /// mimics a long-running generation for stop/cancellation tests.
    var finishes = true

    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken> {
        let snapshot = tokens
        let shouldFinish = finishes
        return AsyncStream { continuation in
            for token in snapshot {
                continuation.yield(token)
            }
            if shouldFinish {
                continuation.finish()
            }
        }
    }
}

// MARK: - Models Tests

struct ModelTests {

    // MARK: Message

    @Test func messageInitializationDefaults() {
        let msg = Message(content: "Hello", role: .user)
        #expect(msg.content == "Hello")
        #expect(msg.role == .user)
        #expect(msg.thinkingContent.isEmpty)
        #expect(!msg.isStreaming)
        #expect(msg.imagePaths.isEmpty)
        #expect(msg.attachedFilePaths.isEmpty)
        #expect(msg.attachedFileNames.isEmpty)
        #expect(msg.attachedFileSizes.isEmpty)
        #expect(msg.fileContent.isEmpty)
        #expect(msg.benchmark == nil)
        #expect(msg.toolCalls.isEmpty)
        #expect(!msg.hasImages)
        #expect(!msg.hasAttachedFiles)
    }

    @Test func messageToolCallsRoundtrip() {
        let msg = Message(content: "test", role: .assistant)
        let call1 = ToolCallRecord(name: "search", params: "{\"q\":\"test\"}")
        let call2 = ToolCallRecord(name: "fetch", params: "{\"url\":\"x\"}", result: "ok")
        msg.toolCalls = [call1, call2]

        let decoded = msg.toolCalls
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "search")
        #expect(decoded[1].name == "fetch")
        #expect(decoded[1].result == "ok")
    }

    @Test func messageBenchmarkRoundtrip() {
        let msg = Message(content: "test", role: .assistant)
        let bench = BenchmarkData(
            timeToFirstToken: 0.5,
            decodeTokensPerSec: 30.0,
            decodeTokenCount: 150,
            prefillTokensPerSec: 100.0,
            prefillTokenCount: 200
        )
        msg.benchmark = bench

        let decoded = msg.benchmark
        #expect(decoded != nil)
        #expect(decoded!.timeToFirstToken == 0.5)
        #expect(decoded!.decodeTokensPerSec == 30.0)
        #expect(decoded!.decodeTokenCount == 150)
    }

    @Test func messageHasImagesTrue() {
        let msg = Message(content: "", role: .user, imagePaths: ["/tmp/img.jpg"])
        #expect(msg.hasImages)
    }

    @Test func messageHasAttachedFilesTrue() {
        let msg = Message(content: "", role: .user, attachedFilePaths: ["/tmp/doc.pdf"])
        #expect(msg.hasAttachedFiles)
    }

    @Test func messageRoleMapping() {
        #expect(MessageRole.user.rawValue == "user")
        #expect(MessageRole.assistant.rawValue == "assistant")
    }

    // MARK: Conversation

    @Test func conversationInitializationDefaults() {
        let conv = Conversation()
        #expect(conv.title == "New Chat")
        #expect(!conv.isPinned)
        #expect(conv.summary.isEmpty)
        #expect(conv.messages.isEmpty)
    }

    @Test func conversationCustomInit() {
        let id = UUID()
        let conv = Conversation(id: id, title: "Test", summary: "sum", isPinned: true)
        #expect(conv.id == id)
        #expect(conv.title == "Test")
        #expect(conv.isPinned)
        #expect(conv.summary == "sum")
    }

    // MARK: MemoryEntry

    @Test func memoryEntryInitialization() {
        let id = UUID()
        let convID = UUID()
        let entry = MemoryEntry(id: id, text: "User likes pizza", conversationID: convID, usageCount: 5)
        #expect(entry.id == id)
        #expect(entry.text == "User likes pizza")
        #expect(entry.conversationID == convID)
        #expect(entry.usageCount == 5)
    }

    @Test func memoryEntryDefaults() {
        let entry = MemoryEntry(text: "fact", conversationID: UUID())
        #expect(entry.usageCount == 0)
    }

    // MARK: PendingFile

    @Test func pendingFileIconNameImage() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("test.jpg")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = PendingFile(url: url)
        #expect(file.iconName == "photo")
        #expect(file.isImage)
        #expect(!file.isAudio)
        #expect(file.name == "test.jpg")
    }

    @Test func pendingFileIconNamePDF() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("doc.pdf")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = PendingFile(url: url)
        #expect(file.iconName == "doc.richtext")
    }

    @Test func pendingFileIconNameDefault() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("data.xyz")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = PendingFile(url: url)
        #expect(file.iconName == "doc")
    }

    @Test func pendingFileFormattedSize() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("test.txt")
        let content = String(repeating: "a", count: 2048)
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = PendingFile(url: url)
        #expect(!file.formattedSize.isEmpty)
        // ByteCountFormatter follows the system locale: "2 KB" (en) / "2 КБ" (ru)
        #expect(file.formattedSize.contains("KB") || file.formattedSize.contains("КБ"))
    }

    @Test func pendingFileEquality() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url1 = tmpDir.appendingPathComponent("a.txt")
        let url2 = tmpDir.appendingPathComponent("b.txt")
        try Data().write(to: url1)
        try Data().write(to: url2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let f1 = PendingFile(url: url1)
        let f2 = PendingFile(url: url2)
        #expect(f1 == f1)
        #expect(f1 != f2)
    }

    // MARK: PendingImage

    @Test func pendingImageInitialization() {
        let img = PendingImage(image: UIImage())
        #expect(!img.id.uuidString.isEmpty)
    }

    // MARK: ToolCallRecord

    @Test func toolCallRecordCodableRoundtrip() throws {
        let record = ToolCallRecord(
            id: UUID(),
            name: "web_search",
            params: "{\"query\":\"hello\"}",
            result: "found",
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ToolCallRecord.self, from: data)
        #expect(decoded.name == "web_search")
        #expect(decoded.params == "{\"query\":\"hello\"}")
        #expect(decoded.result == "found")
    }

    @Test func toolCallRecordDefaultInit() {
        let record = ToolCallRecord(name: "test", params: "{}")
        #expect(record.name == "test")
        #expect(record.result == nil)
    }

    // MARK: ChatMessage

    @Test func chatMessageInitialization() {
        let msg = ChatMessage(
            id: UUID(),
            role: .user,
            content: "hello",
            imagePaths: ["/a.jpg"],
            attachedFilePaths: ["/b.pdf"],
            attachedFileNames: ["doc.pdf"],
            attachedFileSizes: ["2 KB"],
            fileContent: "extracted text"
        )
        #expect(msg.role == .user)
        #expect(msg.content == "hello")
        #expect(msg.imagePaths == ["/a.jpg"])
        #expect(msg.attachedFilePaths == ["/b.pdf"])
        #expect(msg.attachedFileNames == ["doc.pdf"])
        #expect(msg.attachedFileSizes == ["2 KB"])
        #expect(msg.fileContent == "extracted text")
    }

    @Test func chatMessageDefaults() {
        let msg = ChatMessage(role: .assistant, content: "reply")
        #expect(msg.imagePaths.isEmpty)
        #expect(msg.attachedFilePaths.isEmpty)
        #expect(msg.fileContent.isEmpty)
    }

    // MARK: BenchmarkData

    @Test func benchmarkDataCodableRoundtrip() throws {
        let bench = BenchmarkData(
            timeToFirstToken: 0.123,
            decodeTokensPerSec: 45.6,
            decodeTokenCount: 500,
            prefillTokensPerSec: 200.0,
            prefillTokenCount: 1024
        )
        let data = try JSONEncoder().encode(bench)
        let decoded = try JSONDecoder().decode(BenchmarkData.self, from: data)
        #expect(decoded.timeToFirstToken == 0.123)
        #expect(decoded.decodeTokensPerSec == 45.6)
        #expect(decoded.decodeTokenCount == 500)
        #expect(decoded.prefillTokensPerSec == 200.0)
        #expect(decoded.prefillTokenCount == 1024)
    }

}

// MARK: - Services Tests

@Suite(.serialized) @MainActor
struct ServicesTests {

    // MARK: ContextTracker

    @Test func contextTrackerBuild() {
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "hello"),
            ChatMessage(id: UUID(), role: .assistant, content: "hi"),
        ]
        var tokenCounts: [UUID: Int] = [:]
        for msg in messages { tokenCounts[msg.id] = 50 }

        let tracker = ContextTracker.build(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 100,
            memoryTokens: 50,
            toolTokens: 200,
            toolCount: 3,
            toolCountTotal: 5,
            maxNumTokens: 4096
        )

        #expect(tracker.systemPromptTokens == 100)
        #expect(tracker.memoryTokens == 50)
        #expect(tracker.toolTokens == 200)
        #expect(tracker.toolCount == 3)
        #expect(tracker.toolCountTotal == 5)
        #expect(tracker.totalLimit == 4096)
        #expect(tracker.reservedForReply == 512)
        #expect(tracker.budgetTokens == 4096 - 512)
        #expect(tracker.headroom >= 0)
    }

    @Test func contextTrackerCalculateIncluded() {
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "msg1"),
            ChatMessage(id: UUID(), role: .assistant, content: "reply1"),
            ChatMessage(id: UUID(), role: .user, content: "msg2"),
        ]
        var tokenCounts: [UUID: Int] = [:]
        for (i, msg) in messages.enumerated() {
            tokenCounts[msg.id] = i == messages.count - 1 ? 30 : 100
        }

        let result = ContextTracker.calculateIncluded(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 100,
            memoryTokens: 0,
            maxNumTokens: 2048,
            reservedTokens: 512
        )
        #expect(!result.included.isEmpty)
    }

    @Test func contextTrackerChargesToolTokensAgainstTheBudget() {
        // Tool schemas are sent on every turn. If they are not charged, a large
        // tool set silently pushes the real request past the KV-cache limit.
        let messages = (0..<6).map { i in
            ChatMessage(id: UUID(), role: i.isMultiple(of: 2) ? .user : .assistant,
                        content: "message \(i)")
        }
        var tokenCounts: [UUID: Int] = [:]
        for msg in messages { tokenCounts[msg.id] = 200 }

        let withoutTools = ContextTracker.calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 100,
            memoryTokens: 0,
            maxNumTokens: 2048
        )
        let withTools = ContextTracker.calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 100,
            memoryTokens: 0,
            toolTokens: 1000,
            maxNumTokens: 2048
        )
        #expect(withoutTools.includedIDs.count > withTools.includedIDs.count)
    }

    @Test func contextTrackerFormatTokens() {
        #expect(ContextTracker.formatTokens(0) == "0")
        #expect(ContextTracker.formatTokens(256) == "256")
        #expect(ContextTracker.formatTokens(1200) == "1.2K")
        #expect(ContextTracker.formatTokens(14000) == "14K")
        #expect(ContextTracker.formatTokens(1500) == "1.5K")
        #expect(ContextTracker.formatTokens(999) == "999")
    }

    @Test func contextTrackerMessageUsageIdentifiable() {
        let usage = ContextTracker.MessageUsage(
            id: UUID(), role: "user", charCount: 50, tokenCount: 50,
            isInContext: true, tokenOffset: 0, isStreaming: false,
            preview: "hello"
        )
        #expect(usage.tokenCount == 50)
        #expect(usage.isInContext)
        #expect(usage.role == "user")
        #expect(usage.preview == "hello")
    }

    @Test func contextTrackerFillRatio() throws {
        let msg = ChatMessage(id: UUID(), role: .user, content: "x")
        let tracker = ContextTracker(
            systemPromptTokens: 100,
            memoryTokens: 0,
            toolTokens: 0,
            toolCount: 0,
            toolCountTotal: 0,
            totalLimit: 1024,
            messageUsages: [
                ContextTracker.MessageUsage(id: msg.id, role: "user", charCount: 50, tokenCount: 400, isInContext: true, tokenOffset: 0, isStreaming: false, preview: "x")
            ],
            usedTokens: 400
        )
        // budget = 1024 - 512 = 512, used = 400, ratio = 400/512 ≈ 0.78
        #expect(tracker.fillRatio > 0.7 && tracker.fillRatio < 0.8)
        #expect(tracker.headroom == 112)
    }

    @Test func contextTrackerHasDroppedMessages() {
        let droppedUsage = ContextTracker.MessageUsage(
            id: UUID(), role: "user", charCount: 50, tokenCount: 50,
            isInContext: false, tokenOffset: 0, isStreaming: false,
            preview: "old"
        )
        let includedUsage = ContextTracker.MessageUsage(
            id: UUID(), role: "assistant", charCount: 50, tokenCount: 50,
            isInContext: true, tokenOffset: 0, isStreaming: false,
            preview: "new"
        )
        let tracker = ContextTracker(
            systemPromptTokens: 0, memoryTokens: 0, toolTokens: 0,
            toolCount: 0, toolCountTotal: 0, totalLimit: 1024,
            messageUsages: [droppedUsage, includedUsage], usedTokens: 50
        )
        #expect(tracker.hasDroppedMessages)
        #expect(tracker.includedCount == 1)
        #expect(tracker.totalCountExcludingStreaming == 2)
    }

    // MARK: RepetitionDetector

    @Test func repetitionDetectorDetectsConsecutiveRepeats() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)
        var prefix = ""
        for i in 0..<50 { prefix += "padding text number \(i) goes here. " }
        let pattern = "ABCDEFGHIJ"
        let repeated = String(repeating: pattern, count: 4)
        let input = prefix + repeated
        #expect(detector.feed(input))
    }

    @Test func repetitionDetectorPassesNormalText() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)
        // Varied sentence pool: no 3/4/5-gram repeats within the window, so no
        // ngram-flood false positive despite 60 similar-looking sentences.
        let adjectives = ["quick", "lazy", "bright", "quiet", "gentle", "silent", "warm", "cold", "soft", "sharp"]
        let nouns = ["fox", "dog", "cat", "bird", "fish", "mouse", "bear", "wolf", "deer", "hare"]
        var text = ""
        for i in 0..<60 {
            text += "The \(adjectives[i % 10]) \(nouns[(i / 10) % 10]) jumped over \(adjectives[(i + 3) % 10]) \(nouns[(i + 7) / 10]) on day \(i). "
        }
        #expect(!detector.feed(text))
    }

    @Test func repetitionDetectorDetectsLineLoop() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)
        var prefix = ""
        for i in 0..<40 { prefix += "Line \(i) of the test prefix goes right here.\n" }
        let repeatedLine = "This is the same line repeated over and over.\n"
        let input = prefix + String(repeating: repeatedLine, count: 4)
        #expect(detector.feed(input))
    }

    @Test func repetitionDetectorBelowMinBufferReturnsFalse() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)
        #expect(!detector.feed("short text"))
    }

    @Test func repetitionDetectorNgramFloodDetection() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)
        var prefix = ""
        for i in 0..<50 { prefix += "padding text number \(i) goes here. " }
        // Repeat a short phrase many times (ngram flood)
        var flood = ""
        for _ in 0..<20 { flood += "click the button now. " }
        let input = prefix + flood
        #expect(detector.feed(input))
    }

    @Test func repetitionDetectorReset() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)
        var prefix = ""
        for i in 0..<50 { prefix += "padding text number \(i) goes here. " }
        let pattern = "ABCDEFGHIJ"
        let repeated = String(repeating: pattern, count: 4)
        _ = detector.feed(prefix + repeated)
        #expect(detector.totalChars > 0)
        detector.reset()
        #expect(detector.totalChars == 0)
    }

    // MARK: TokenBudget

    @Test func tokenBudgetSafeMaxTokensWithAutoKV() {
        let budget = TokenBudget()
        let result = budget.safeMaxTokens(
            modelPath: "/nonexistent/model.litertlm",
            useGPU: true,
            kvCacheAuto: true,
            maxNumTokens: 4096
        )
        #expect(result != nil)
        #expect(result! >= 512)
        #expect(result! % 256 == 0)
    }

    @Test func tokenBudgetSafeMaxTokensManualKV() {
        let budget = TokenBudget()
        let result = budget.safeMaxTokens(
            modelPath: "/nonexistent/model.litertlm",
            useGPU: false,
            kvCacheAuto: false,
            maxNumTokens: 2048
        )
        #expect(result != nil)
        #expect(result! >= 512)
        #expect(result! <= 2048)
    }

    @Test func tokenBudgetTokenizeCountFallback() async {
        let budget = TokenBudget()
        // With nil engine, falls back to char/4
        let count = await budget.tokenizeCount("hello world, this is a test string", engine: nil)
        #expect(count > 0)
        #expect(count == "hello world, this is a test string".count / 4)
    }

    @Test func tokenBudgetTokenizeMessagesFallback() async {
        let budget = TokenBudget()
        let msgs = [
            ChatMessage(role: .user, content: "short"),
            ChatMessage(role: .assistant, content: "longer message here"),
        ]
        let counts = await budget.tokenizeMessages(msgs, engine: nil)
        #expect(counts.count == 2)
        for (_, count) in counts { #expect(count > 0) }
    }

    @Test func tokenBudgetClearTokenCache() async {
        let budget = TokenBudget()
        _ = await budget.tokenizeCount("cached text", engine: nil)
        budget.clearTokenCache()
        // After clear, subsequent call should still work (just re-tokenizes)
        let count = await budget.tokenizeCount("cached text", engine: nil)
        #expect(count > 0)
    }

    // MARK: ModelDiscovery

    @Test func modelDiscoveryDisplayName() {
        let name = ModelDiscovery.displayName(forModelPath: "/models/gemma-4-E4B-it.litertlm")
        #expect(name.contains("gemma"))
        #expect(name.contains("4"))
        #expect(!name.contains(".litertlm"))
        #expect(!name.contains("-"))
    }

    @Test func modelDiscoveryDisplayNameReplacesUnderscores() {
        let name = ModelDiscovery.displayName(forModelPath: "/models/my_model_v2.litertlm")
        #expect(!name.contains("_"))
        #expect(name.contains("my"))
        #expect(name.contains("model"))
        #expect(name.contains("v2"))
    }

    @Test func modelDiscoveryModelsDirectory() {
        let dir = ModelDiscovery.modelsDirectory
        #expect(dir.lastPathComponent == "models")
        #expect(dir.path.contains("Documents"))
    }

    @Test func modelDiscoveryResolveModelPathCustomNotFound() {
        let result = ModelDiscovery.resolveModelPath(custom: "/nonexistent/path/model.litertlm")
        #expect(result == nil)
    }

    // MARK: ModelSettings

    @Test func modelSettingsDefaultSystemPrompt() {
        let settings = ModelSettings()
        let prompt = settings.defaultSystemPrompt
        #expect(prompt.contains("helpful personal AI assistant"))
        #expect(prompt.contains("tools"))
        #expect(!prompt.isEmpty)
    }

    @Test func systemPromptHasSingleCanonicalSource() {
        // ModelSettings delegates to AppDefaults — the two must never diverge.
        let settings = ModelSettings()
        #expect(settings.defaultSystemPrompt == AppDefaults.systemPrompt.defaultValue)
    }

    @Test func modelSettingsPropertiesReadWrite() {
        let settings = ModelSettings()
        let original = settings.maxNumTokens
        settings.maxNumTokens = 8192
        #expect(settings.maxNumTokens == 8192)
        settings.maxNumTokens = original // restore
    }

    // MARK: PresetModel

    @Test func presetModelAllCases() {
        #expect(PresetModel.allCases.count >= 2)
        for model in PresetModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.filename.isEmpty)
            #expect(model.downloadURL != nil)
            #expect(model.fileSizeGB > 0)
            #expect(!model.parameterCount.isEmpty)
            #expect(!model.description.isEmpty)
            #expect(!model.minRAM.isEmpty)
            #expect(!model.systemImage.isEmpty)
            #expect(model.license == "Apache 2.0")
            #expect(!model.capabilities.isEmpty)
        }
    }

    @Test func presetModelFileSizeString() {
        for model in PresetModel.allCases {
            #expect(model.fileSizeString.contains("GB"))
        }
    }

    @Test func presetModelLocalPath() {
        for model in PresetModel.allCases {
            let path = model.localPath
            #expect(path.contains(model.filename))
            #expect(path.contains("models"))
        }
    }

    @Test func presetModelIsDownloadedFalse() {
        // Models shouldn't be downloaded in test environment
        for model in PresetModel.allCases {
            #expect(!model.isDownloaded)
        }
    }

    @Test func presetModelDisplaySizeString() {
        for model in PresetModel.allCases {
            let str = model.displaySizeString()
            #expect(!str.isEmpty)
        }
    }

    // MARK: EmbeddingService

    @Test func embeddingServiceCosineSimilarityIdentical() {
        let emb = EmbeddingService.shared
        let vec = EmbeddedText(vector: [1.0, 2.0, 3.0], modelKey: "test")
        let sim = emb.cosineSimilarity(vec, vec)
        #expect(abs(sim - 1.0) < 0.001)
    }

    @Test func embeddingServiceCosineSimilarityOrthogonal() {
        let emb = EmbeddingService.shared
        let a = EmbeddedText(vector: [1.0, 0.0, 0.0], modelKey: "test")
        let b = EmbeddedText(vector: [0.0, 1.0, 0.0], modelKey: "test")
        let sim = emb.cosineSimilarity(a, b)
        #expect(abs(sim - 0.0) < 0.001)
    }

    @Test func embeddingServiceCosineSimilarityOpposite() {
        let emb = EmbeddingService.shared
        let a = EmbeddedText(vector: [1.0, 2.0, 3.0], modelKey: "test")
        let b = EmbeddedText(vector: [-1.0, -2.0, -3.0], modelKey: "test")
        let sim = emb.cosineSimilarity(a, b)
        #expect(abs(sim - (-1.0)) < 0.001)
    }

    @Test func embeddingServiceCosineSimilarityEmpty() {
        let emb = EmbeddingService.shared
        let a = EmbeddedText(vector: [], modelKey: "test")
        let sim = emb.cosineSimilarity(a, a)
        #expect(sim == 0)
    }

    @Test func embeddingServiceCosineSimilarityDifferentModels() {
        let emb = EmbeddingService.shared
        let a = EmbeddedText(vector: [1.0, 0.0, 0.0], modelKey: "cyrillic")
        let b = EmbeddedText(vector: [1.0, 0.0, 0.0], modelKey: "latin")
        // Different models live in different vector spaces — never comparable.
        #expect(emb.cosineSimilarity(a, b) == 0)
    }



    @Test func tokenTruncatorTruncateResultDict() async {
        let dict: [String: Any] = [
            "short": "ok",
            "long": String(repeating: "x", count: 10000)
        ]
        let result = await TokenTruncator.truncateResult(dict, maxTokens: 50)
        guard let resultDict = result as? [String: Any] else {
            #expect(Bool(false), "Expected dictionary result")
            return
        }
        #expect(resultDict["short"] as? String == "ok")
        guard let truncated = resultDict["long"] as? String else {
            #expect(Bool(false), "Expected string for 'long'")
            return
        }
        #expect(truncated.contains("[Truncated"))
    }

    @Test func tokenTruncatorTruncateResultArray() async {
        let arr: [Any] = [String(repeating: "x", count: 5000)]
        let result = await TokenTruncator.truncateResult(arr, maxTokens: 50)
        guard let resultArr = result as? [Any], let first = resultArr.first as? String else {
            #expect(Bool(false), "Expected array with string")
            return
        }
        #expect(first.contains("[Truncated"))
    }

    @Test func tokenTruncatorAggregateManySmallItems() async {
        // Every field is short, but the aggregate far exceeds the budget —
        // the item count must shrink (per-field truncation alone misses this).
        let events = (0..<200).map {
            ["title": "Event number \($0)", "start": "2026-08-06 10:00", "end": "2026-08-06 11:00"]
        }
        let dict: [String: Any] = ["events": events]
        let result = await TokenTruncator.truncateResult(dict, maxTokens: 50)
        guard let resultDict = result as? [String: Any],
              let resultEvents = resultDict["events"] as? [Any] else {
            #expect(Bool(false), "Expected dictionary with events array")
            return
        }
        #expect(resultEvents.count < 200)
        #expect(resultEvents.contains { ($0 as? String)?.contains("omitted") == true })
    }

    @Test func tokenTruncatorSmallResultUntouched() async {
        let dict: [String: Any] = ["city": "Berlin", "temperature_c": 21.5]
        let result = await TokenTruncator.truncateResult(dict, maxTokens: 500)
        guard let resultDict = result as? [String: Any] else {
            #expect(Bool(false), "Expected dictionary result")
            return
        }
        #expect(resultDict["city"] as? String == "Berlin")
        #expect(resultDict["temperature_c"] as? Double == 21.5)
    }

    // MARK: SearchResultCompactor

    @Test func compactorSanitizeQueryCollapsesWhitespace() {
        #expect(SearchResultCompactor.sanitizeQuery("  swift   programming\nnews  ") == "swift programming news")
        #expect(SearchResultCompactor.sanitizeQuery("   ") == "")
        let long = String(repeating: "a", count: 500)
        #expect(SearchResultCompactor.sanitizeQuery(long).count == SearchResultCompactor.maxQueryChars)
    }

    @Test func compactorSnippetKeepsShort() {
        #expect(SearchResultCompactor.compactSnippet("short snippet") == "short snippet")
        #expect(SearchResultCompactor.compactSnippet("") == "")
    }

    @Test func compactorSnippetCutsAtSentenceBoundary() {
        let text = "First sentence here. Second sentence follows with more words after it."
        let cut = SearchResultCompactor.compactSnippet(String(repeating: text + " ", count: 10))
        #expect(cut.count <= SearchResultCompactor.maxSnippetChars + 1)
        // Prefers a sentence end over a mid-sentence cut.
        #expect(cut.hasSuffix(".") || cut.hasSuffix("…"))
    }

    @Test func compactorCutAtBoundaryPrefersSentence() {
        let cut = SearchResultCompactor.cutAtBoundary("Hello world. This is next.", maxChars: 15)
        #expect(cut == "Hello world.")
    }

    @Test func compactorCutAtBoundaryFallsBackToWord() {
        let cut = SearchResultCompactor.cutAtBoundary(String(repeating: "word ", count: 100), maxChars: 30)
        #expect(cut.count <= 31)
        #expect(cut.hasSuffix("…"))
        #expect(!cut.contains("  "))
    }

    @Test func compactorFitKeepsURLsAndTitles() {
        let results: [[String: Any]] = (0..<5).map { i in
            [
                "title": "Title number \(i) with some extra words to make it longer",
                "snippet": String(repeating: "snippet text \(i). ", count: 40),
                "url": "https://example.com/page\(i)",
            ]
        }
        let fitted = SearchResultCompactor.fitResults(results, tokenLimit: 400)
        #expect(fitted.count <= results.count)
        for (i, item) in fitted.enumerated() {
            #expect(item["url"] as? String == "https://example.com/page\(i)")
            #expect(!(item["title"] as? String ?? "").isEmpty)
        }
        #expect(SearchResultCompactor.estimateTokens(ofResults: fitted) <= 500)
    }

    @Test func compactorFitDropsTrailingWithMarker() {
        let results: [[String: Any]] = (0..<5).map { i in
            [
                "title": "T\(i)",
                "snippet": String(repeating: "x", count: 1000),
                "url": "https://example.com/\(i)",
            ]
        }
        let fitted = SearchResultCompactor.fitResults(results, tokenLimit: 100)
        #expect(fitted.count < results.count)
        let lastSnippet = fitted.last?["snippet"] as? String ?? ""
        #expect(lastSnippet.contains("omitted"))
        // URLs of survivors are untouched.
        #expect(fitted.first?["url"] as? String == "https://example.com/0")
    }

    @Test func compactorFitShrinksContentFirst() {
        let results: [[String: Any]] = [
            [
                "title": "T",
                "snippet": "short snippet",
                "url": "https://example.com",
                "content": String(repeating: "fetched content. ", count: 200),
            ]
        ]
        let fitted = SearchResultCompactor.fitResults(results, tokenLimit: 300)
        #expect(fitted.count == 1)
        #expect(fitted[0]["url"] as? String == "https://example.com")
        #expect(fitted[0]["snippet"] as? String == "short snippet")
        let content = fitted[0]["content"] as? String ?? ""
        #expect(content.count < 200 * 17)
        #expect(SearchResultCompactor.estimateTokens(ofResults: fitted) <= 400)
    }

    @Test func compactorCacheKeyNormalizes() {
        #expect(SearchResultCompactor.cacheKey(query: "  Swift   News ", timeRange: nil) == "swift news")
        #expect(SearchResultCompactor.cacheKey(query: "Swift", timeRange: "week") == "swift|week")
    }

    // MARK: FileContentExtractor

    @Test func fileContentExtractorExtractTextFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("test_extract.txt")
        try "Hello, this is extracted text content.".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try await FileContentExtractor.extract(from: url)
        #expect(content.contains("Hello"))
        #expect(content.contains("extracted text"))
    }

    @Test func fileContentExtractorPdfHasTextLayerNonExistent() {
        let result = FileContentExtractor.pdfHasTextLayer(URL(fileURLWithPath: "/nonexistent.pdf"))
        #expect(!result)
    }

    // MARK: ImageCache

    @Test func imageCacheSetAndGet() {
        let cache = ImageCache.shared
        let image = UIImage()
        cache.setImage(image, forKey: "test_key")
        let retrieved = cache.image(forKey: "test_key")
        #expect(retrieved != nil)
    }

    @Test func imageCacheMiss() {
        let cache = ImageCache.shared
        #expect(cache.image(forKey: "nonexistent") == nil)
    }

    @Test func imageCacheClear() {
        let cache = ImageCache.shared
        cache.setImage(UIImage(), forKey: "k")
        cache.clear()
        #expect(cache.image(forKey: "k") == nil)
    }

    // MARK: URLCacheStore

    @Test func urlCacheStoreSetAndGet() {
        let store = URLCacheStore.shared
        store.setContent("cached content", for: "https://example.com")
        #expect(store.content(for: "https://example.com") == "cached content")
    }

    @Test func urlCacheStoreMiss() {
        let store = URLCacheStore.shared
        #expect(store.content(for: "https://missing.com") == nil)
    }


    // MARK: LamoError

    @Test func lamoErrorDescriptions() {
        // Descriptions are localized, so assert on the interpolated payload and
        // on the localized text itself rather than on English wording.
        #expect(LamoError.modelNotFound("path").errorDescription?.contains("path") ?? false)
        #expect(LamoError.engineInitFailed("reason").errorDescription?.contains("reason") ?? false)
        #expect(LamoError.modelCorrupted("corrupt").errorDescription?.contains("corrupt") ?? false)
        #expect(LamoError.insufficientMemory(available: 2.0, required: 4.0).errorDescription?.contains("2.0") ?? false)
        #expect(LamoError.insufficientDiskSpace.errorDescription == String(localized: "Not enough storage. Free up at least 1 GB."))
        #expect(LamoError.modelTooSmall(0.5).errorDescription?.contains("0.50") ?? false)
        #expect(LamoError.noModelAvailable.errorDescription == String(localized: "No model available. Download a model in Settings."))
        #expect(LamoError.modelStuckInLoop.errorDescription == String(localized: "Model stuck in a loop. Try rephrasing your message or adjusting temperature in Settings."))
        #expect(LamoError.engineNotReady.errorDescription?.isEmpty == false)
    }


    @Test func liteRTLMErrorDescriptions() {
        #expect(LiteRTLMError.modelNotFound("p").errorDescription?.contains("p") ?? false)
        #expect(LiteRTLMError.modelsDirectoryMissing.errorDescription?.contains("models") ?? false)
        #expect(LiteRTLMError.noModelFound.errorDescription?.contains(".litertlm") ?? false)
    }

    // MARK: LamoLogger

    @Test func lamoLoggerSubsystem() {
        // subsystem falls back to "com.lamo" in test bundle
        #expect(!LamoLogger.subsystem.isEmpty)
    }

    // MARK: KeychainHelper

    @Test func keychainHelperSaveLoadDelete() {
        // Unsigned test hosts (CODE_SIGNING_ALLOWED=NO) have no Keychain
        // entitlement at all, so the assertions below cannot run there.
        guard KeychainHelper.isKeychainAvailable() else { return }
        let key = "test_key_\(UUID().uuidString)"
        KeychainHelper.save(key: key, value: "secret_value")
        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == "secret_value")
        KeychainHelper.delete(key: key)
        #expect(KeychainHelper.load(key: key) == nil)
    }

    @Test func keychainHelperLoadMissing() {
        #expect(KeychainHelper.load(key: "nonexistent_key_xyz") == nil)
    }


    // MARK: AgenticLoopBudget

    @Test func agenticLoopBudgetConfigureAndReset() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 4096, systemOverhead: 1000, conversationSkeletonTokens: 500)
        let working = await budget.workingBudget
        #expect(working == 4096 - 1000 - 500 - 512)
        #expect(working > 0)
        await budget.reset()
    }

    @Test func agenticLoopBudgetShouldStopByIterations() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 1000, conversationSkeletonTokens: 500, maxIterations: 1)
        let limit = await budget.consumeIteration()
        #expect(limit > 0)
        let shouldStop = await budget.shouldStop
        #expect(shouldStop)
        await budget.reset()
    }

    @Test func agenticLoopBudgetHeadroomPositive() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 500, conversationSkeletonTokens: 500)
        let headroom = await budget.headroom
        #expect(headroom > 0)
        await budget.reset()
    }

    @Test func agenticLoopBudgetRecordCost() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 500, conversationSkeletonTokens: 500)
        let before = await budget.headroom
        await budget.recordCost(tokens: 1000)
        let after = await budget.headroom
        #expect(after == before - 1000)
        await budget.reset()
    }

    @Test func agenticLoopBudgetSoftStopAfterIterationCap() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 500, conversationSkeletonTokens: 500, maxIterations: 1)
        // Before any iteration: no soft-stop.
        #expect(await budget.softStopNotice() == nil)
        _ = await budget.consumeIteration()
        // Cap reached: tools get a wrap-up notice instead of executing.
        let notice = await budget.softStopNotice()
        #expect(notice?["notice"] != nil)
        #expect(notice?["hint"] != nil)
        await budget.reset()
    }

    @Test func agenticLoopBudgetLimitResultTruncatesAndRecords() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 4096, systemOverhead: 1000, conversationSkeletonTokens: 500, maxIterations: 5)
        let big: [String: Any] = ["content": String(repeating: "x", count: 20000)]
        let result = await budget.limitResult(big)
        let content = (result as? [String: Any])?["content"] as? String ?? ""
        #expect(content.count < 20000)
        // Cost was recorded: headroom shrank below the initial working budget.
        let headroom = await budget.headroom
        #expect(headroom < 4096 - 1000 - 500 - 512)
        await budget.reset()
    }

    @Test func agenticLoopBudgetSoftStopGrantsIteration() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 500, conversationSkeletonTokens: 500, maxIterations: 2)
        // Every granted pass consumes an iteration — even if the tool later fails,
        // so a model stuck retrying a failing tool hits the cap too.
        #expect(await budget.softStopNotice() == nil)
        #expect(await budget.totalIterations == 1)
        #expect(await budget.softStopNotice() == nil)
        #expect(await budget.totalIterations == 2)
        // Cap reached: wrap-up notice, nothing further consumed.
        let notice = await budget.softStopNotice()
        #expect(notice?["notice"] != nil)
        #expect(await budget.totalIterations == 2)
        await budget.reset()
    }

    @Test func agenticLoopBudgetProjectedLimitMatchesGrant() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 500, conversationSkeletonTokens: 500, maxIterations: 5)
        for _ in 0..<3 {
            let projected = await budget.projectedResultLimit()
            let granted = await budget.consumeIteration()
            #expect(projected == granted)
        }
        await budget.reset()
    }

    @Test func agenticLoopBudgetLimitResultUsesGrantedLimit() async {
        let budget = AgenticLoopBudget.shared
        await budget.configure(totalBudget: 8192, systemOverhead: 500, conversationSkeletonTokens: 500, maxIterations: 2)
        // Grant happens at softStopNotice; limitResult must not consume a second iteration.
        #expect(await budget.softStopNotice() == nil)
        let big: [String: Any] = ["content": String(repeating: "x", count: 20000)]
        _ = await budget.limitResult(big)
        #expect(await budget.totalIterations == 1)
        await budget.reset()
    }

    @Test func agenticLoopBudgetEstimateTokensWeightsNonASCII() async {
        // Non-ASCII text must not be under-estimated the way char/4 would —
        // Cyrillic tokenizes far denser than 4 chars/token.
        let cyrillic = AgenticLoopBudget.estimateTokens(of: String(repeating: "я", count: 400))
        let ascii = AgenticLoopBudget.estimateTokens(of: String(repeating: "a", count: 400))
        #expect(cyrillic > ascii)
        #expect(cyrillic >= 300)   // ≈1 token/char for non-ASCII
        #expect(ascii <= 101)      // ≈4 chars/token for ASCII
    }

    // MARK: Tool Error Handling (tools must return error dicts, never throw —
    // a thrown error aborts the whole agentic stream in LiteRT-LM)

    @Test func fetchUrlToolInvalidURLReturnsErrorDict() async throws {
        let json = #"{"url": "not a valid url"}"#.data(using: .utf8)!
        let tool = try JSONDecoder().decode(FetchUrlTool.self, from: json)
        let result = try await tool.run()
        guard let dict = result as? [String: Any] else {
            #expect(Bool(false), "Expected error dictionary")
            return
        }
        #expect(dict["error"] != nil)
        #expect(dict["hint"] != nil)
    }

    @Test func fetchUrlToolSchemelessURLReturnsErrorDict() async throws {
        let json = #"{"url": "example.com/page"}"#.data(using: .utf8)!
        let tool = try JSONDecoder().decode(FetchUrlTool.self, from: json)
        let result = try await tool.run()
        #expect((result as? [String: Any])?["error"] != nil)
    }

    /// Decodes a CalendarTool the way ToolManager does: every parameter key present,
    /// unset optionals as null (Swift's synthesized Decodable requires all keys).
    private func decodeCalendarTool(mode: String, title: String? = nil, startDate: String? = nil,
                                    startTime: String? = nil, endTime: String? = nil) throws -> CalendarTool {
        var json = "{\"mode\": \"\(mode)\""
        json += title.map { ", \"title\": \"\($0)\"" } ?? ", \"title\": null"
        json += startDate.map { ", \"startDate\": \"\($0)\"" } ?? ", \"startDate\": null"
        json += startTime.map { ", \"startTime\": \"\($0)\"" } ?? ", \"startTime\": null"
        json += endTime.map { ", \"endTime\": \"\($0)\"" } ?? ", \"endTime\": null"
        json += ", \"endDate\": null, \"notes\": null, \"location\": null, \"query\": null}"
        return try JSONDecoder().decode(CalendarTool.self, from: json.data(using: .utf8)!)
    }

    @Test func calendarToolInvalidModeReturnsErrorDict() async throws {
        let tool = try decodeCalendarTool(mode: "dance")
        let result = try await tool.run()
        guard let dict = result as? [String: Any] else {
            #expect(Bool(false), "Expected error dictionary")
            return
        }
        #expect((dict["error"] as? String)?.contains("dance") == true)
        #expect(dict["hint"] != nil)
    }

    @Test func calendarToolCreateWithoutTitleReturnsErrorDict() async throws {
        let tool = try decodeCalendarTool(mode: "create", startDate: "2026-08-15")
        let result = try await tool.run()
        #expect((result as? [String: Any])?["error"] != nil)
    }

    @Test func calendarToolUnparseableDateReturnsErrorDict() async throws {
        // "next Friday" must NOT silently fall back to today — that books the wrong day.
        let tool = try decodeCalendarTool(mode: "create", title: "Dentist", startDate: "next Friday")
        let result = try await tool.run()
        guard let dict = result as? [String: Any] else {
            #expect(Bool(false), "Expected error dictionary")
            return
        }
        #expect((dict["error"] as? String)?.contains("next Friday") == true)
    }

    @Test func calendarToolEndBeforeStartReturnsErrorDict() async throws {
        let tool = try decodeCalendarTool(mode: "create", title: "Call", startTime: "18:00", endTime: "09:00")
        let result = try await tool.run()
        #expect((result as? [String: Any])?["error"] != nil)
    }

    // MARK: ToolCallReporter

    @Test func toolCallReporterRegisterAndReport() async {
        let reporter = ToolCallReporter.shared
        let stream = AsyncStream<StreamingToken> { continuation in
            Task {
                await reporter.register(continuation: continuation)
                await reporter.reportCall(name: "test_tool", params: "{}")
                await reporter.reportResult(name: "test_tool", result: ["status": "ok"])
            }
        }

        var tokens: [StreamingToken] = []
        for await token in stream.prefix(2) {
            tokens.append(token)
        }

        #expect(tokens.count == 2)
        switch tokens[0] {
        case .toolCall(let name, let params):
            #expect(name == "test_tool")
            #expect(params == "{}")
        default:
            #expect(Bool(false), "Expected toolCall token")
        }
        switch tokens[1] {
        case .toolResult(let name, let result):
            #expect(name == "test_tool")
            #expect(result.contains("ok"))
        default:
            #expect(Bool(false), "Expected toolResult token")
        }

        await reporter.reset()
    }

    // MARK: AppDefaults

    @Test func appDefaultsUserDefaultWrapper() {
        @UserDefault("test_bool_key", default: true) var testBool: Bool
        testBool = false
        #expect(testBool == false)
        testBool = true
        #expect(testBool == true)
        UserDefaults.standard.removeObject(forKey: "test_bool_key")
    }

    @Test func appDefaultsUserDefaultInt() {
        @UserDefault("test_int_key", default: 42) var testInt: Int
        #expect(testInt == 42)
        testInt = 100
        #expect(testInt == 100)
        UserDefaults.standard.removeObject(forKey: "test_int_key")
    }

    @Test func appDefaultsOptionalUserDefault() {
        @OptionalUserDefault<String>(key: "test_opt_key") var testOpt: String?
        #expect(testOpt == nil)
        testOpt = "hello"
        #expect(testOpt == "hello")
        testOpt = nil
        #expect(testOpt == nil)
    }

    @Test func appDefaultsResetAll() {
        // Set non-default value
        AppDefaults.temperature.wrappedValue = 2.0
        #expect(AppDefaults.temperature.wrappedValue == 2.0)

        AppDefaults.resetAll()
        #expect(AppDefaults.temperature.wrappedValue == 1.0)
        #expect(AppDefaults.topK.wrappedValue == 64)
        #expect(AppDefaults.topP.wrappedValue == 0.95)
        #expect(AppDefaults.useGPU.wrappedValue == true)
        #expect(AppDefaults.cpuThreadCount.wrappedValue == 4)
        #expect(AppDefaults.kvCacheAuto.wrappedValue == true)
        #expect(AppDefaults.maxNumTokens.wrappedValue == 4096)
        #expect(AppDefaults.speculativeDecoding.wrappedValue == true)
        #expect(AppDefaults.thinkingMode.wrappedValue == false)
        #expect(AppDefaults.memoryEnabled.wrappedValue == true)
        #expect(AppDefaults.toolWebSearch.wrappedValue == true)
        #expect(AppDefaults.toolCalendar.wrappedValue == true)
        #expect(AppDefaults.modelPath.wrappedValue == nil)
    }

    // MARK: UIImage+Resize

    @Test func uiImageResizeNoUpscale() {
        // Create a 10x10 image — already smaller than maxDimension 1024
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let resized = image.resizedForModel(maxDimension: 1024)
        #expect(resized.size.width == 10)
        #expect(resized.size.height == 10)
    }

    @Test func uiImageResizeDownscale() {
        let size = CGSize(width: 2048, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let resized = image.resizedForModel(maxDimension: 1024)
        #expect(resized.size.width == 1024)
        #expect(resized.size.height == 512)
    }

    @Test func uiImageResizeSquareDownscale() {
        let size = CGSize(width: 2048, height: 2048)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let resized = image.resizedForModel(maxDimension: 1024)
        #expect(resized.size.width == 1024)
        #expect(resized.size.height == 1024)
    }
}

// MARK: - ChatViewModel Tests

@Suite(.serialized) @MainActor
struct ChatViewModelTests {

    @Test func chatViewModelSendCreatesUserMessageAndStartsStreaming() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        mock.tokens = [.done]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Hello, world!"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(viewModel.messages.count >= 2)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].content == "Hello, world!")
        #expect(viewModel.inputText.isEmpty)
        #expect(!viewModel.isStreaming)
        #expect(viewModel.messages.last?.isStreaming == false)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithStreamingDelta() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        mock.tokens = [
            .delta("Hello"),
            .delta(" world"),
            .done,
        ]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Hi"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)
        let assistantMsg = viewModel.messages.last
        #expect(assistantMsg?.role == .assistant)
        #expect(assistantMsg?.content.contains("Hello") ?? false)
        #expect(assistantMsg?.content.contains("world") ?? false)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithThinkingDelta() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        mock.tokens = [
            .thinkingDelta("Let me think..."),
            .delta("Answer"),
            .done,
        ]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Question"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)
        let assistantMsg = viewModel.messages.last
        #expect(assistantMsg?.thinkingContent.contains("Let me think") ?? false)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithToolCalls() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        mock.tokens = [
            .toolCall(name: "web_search", params: "{\"query\":\"test\"}"),
            .toolResult(name: "web_search", result: "{\"results\":[]}"),
            .delta("I found nothing."),
            .done,
        ]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Search something"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)
        let assistantMsg = viewModel.messages.last
        let calls = assistantMsg?.toolCalls ?? []
        #expect(calls.count == 1)
        #expect(calls[0].name == "web_search")
        #expect(calls[0].result != nil)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithBenchmark() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let bench = BenchmarkData(
            timeToFirstToken: 0.3,
            decodeTokensPerSec: 25.0,
            decodeTokenCount: 100,
            prefillTokensPerSec: 80.0,
            prefillTokenCount: 200
        )
        let mock = MockLLMProvider()
        mock.tokens = [
            .benchmark(bench),
            .done,
        ]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Bench me"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        let assistantMsg = viewModel.messages.last
        #expect(assistantMsg?.benchmark != nil)
        #expect(assistantMsg?.benchmark?.timeToFirstToken == 0.3)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithError() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        mock.tokens = [.error(LamoError.noModelAvailable)]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Hi"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)
        let assistantMsg = viewModel.messages.last
        // Error surfaces in a dedicated state, not in the message content
        #expect(assistantMsg?.errorDescription == LamoError.noModelAvailable.errorDescription)
        #expect(!(assistantMsg?.content.contains("Error") ?? true))

        memoryService.clearAll()
    }

    @Test func chatViewModelRetryLastMessage() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        // First send a message that gets an error
        let mock1 = MockLLMProvider()
        mock1.tokens = [.error(LamoError.noModelAvailable)]
        viewModel.llmProviderOverride = mock1
        viewModel.inputText = "Hi"
        viewModel.send()
        try await Task.sleep(for: .milliseconds(500))

        let countBeforeRetry = viewModel.messages.count

        // Retry
        let mock2 = MockLLMProvider()
        mock2.tokens = [.done]
        viewModel.llmProviderOverride = mock2
        viewModel.retryLastMessage()
        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)
        // Should have replaced the failed assistant message
        #expect(viewModel.messages.count == countBeforeRetry)
        // Fresh message carries no stale error state
        #expect(viewModel.messages.last?.errorDescription == nil)

        memoryService.clearAll()
    }

    @Test func chatViewModelRetryFailedMessageDeletesOnward() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        // 1. First exchange fails
        let mock1 = MockLLMProvider()
        mock1.tokens = [.error(LamoError.noModelAvailable)]
        viewModel.llmProviderOverride = mock1
        viewModel.inputText = "Hi"
        viewModel.send()
        try await Task.sleep(for: .milliseconds(500))

        let failedMessage = try #require(viewModel.messages.last)
        #expect(failedMessage.errorDescription != nil)

        // 2. User continues the conversation despite the failure
        let mock2 = MockLLMProvider()
        mock2.tokens = [.delta("follow up answer"), .done]
        viewModel.llmProviderOverride = mock2
        viewModel.inputText = "And another thing"
        viewModel.send()
        try await Task.sleep(for: .milliseconds(500))
        #expect(viewModel.messages.count == 4) // user, failed asst, user, ok asst

        // 3. Retrying the failed message removes it and everything after it
        let mock3 = MockLLMProvider()
        mock3.tokens = [.delta("regenerated answer"), .done]
        viewModel.llmProviderOverride = mock3
        viewModel.retryMessage(failedMessage)
        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)
        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages.last?.content == "regenerated answer")
        #expect(viewModel.messages.last?.errorDescription == nil)

        memoryService.clearAll()
    }

    @Test func chatViewModelStopGeneration() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        // Stream that never finishes (no .done/.error, no finish()) — will be cancelled by stop
        mock.finishes = false
        mock.tokens = [
            .delta("streaming..."),
            .delta("still going..."),
        ]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Go"
        viewModel.send()

        // Brief wait for streaming to start
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.isStreaming)

        viewModel.stopGeneration()
        try await Task.sleep(for: .milliseconds(200))

        #expect(!viewModel.isStreaming)

        memoryService.clearAll()
    }

    @Test func chatViewModelEditMessage() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        // Add a user message
        let userMsg = Message(content: "original question", role: .user, conversation: conversation)
        context.insert(userMsg)
        try context.save()
        viewModel.messages.append(userMsg)

        let assistantMsg = Message(content: "original answer", role: .assistant, conversation: conversation)
        context.insert(assistantMsg)
        try context.save()
        viewModel.messages.append(assistantMsg)

        #expect(viewModel.messages.count == 2)

        // Edit the user message — should delete it and everything after
        viewModel.editMessage(userMsg)

        // user message and assistant should be removed
        #expect(viewModel.messages.isEmpty)
        // inputText should contain the original message
        #expect(viewModel.inputText == "original question")

        memoryService.clearAll()
    }

    @Test func chatViewModelEditNonUserMessageNoOp() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let memoryService = MemoryService()
        memoryService.setModelContext(context)
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)
        let assistantMsg = Message(content: "reply", role: .assistant, conversation: conversation)
        context.insert(assistantMsg)
        try context.save()
        viewModel.messages.append(assistantMsg)

        viewModel.editMessage(assistantMsg)
        // Should be no-op for non-user messages
        #expect(viewModel.messages.count == 1)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithLoopDetectedRetry() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        // First attempt: loop detected → triggers retry
        // Second attempt (retry): done
        // The retry happens inside startStreaming by re-calling with retryCount+1,
        // so we need the mock to serve both calls
        mock.tokens = [
            .loopDetected,
            .done,
        ]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Hi"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(1000))

        #expect(!viewModel.isStreaming)
        // Should have completed after retry
        #expect(viewModel.messages.count >= 2)

        memoryService.clearAll()
    }

    @Test func chatViewModelConversationTitle() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation(title: "Custom Title")
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)
        #expect(viewModel.conversationTitle == "Custom Title")
    }

    @Test func chatViewModelSendUpdatesConversationTitle() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        let mock = MockLLMProvider()
        mock.tokens = [.done]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "This is a brand new conversation about cooking"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(conversation.title != "New Chat")
        #expect(conversation.title.hasPrefix("This is a brand new conversation"))

        memoryService.clearAll()
    }

    @Test func chatViewModelGenerateConversationSummary() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        // Add 16 messages (exceeds the 15 threshold for fallback summary)
        for i in 0..<8 {
            let user = Message(content: "user msg \(i)", role: .user, conversation: conversation)
            let assistant = Message(content: "assistant msg \(i) " + String(repeating: "padding ", count: 20), role: .assistant, conversation: conversation)
            context.insert(user)
            context.insert(assistant)
            viewModel.messages.append(user)
            viewModel.messages.append(assistant)
        }

        let mock = MockLLMProvider()
        mock.tokens = [.done]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Final question"
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(!viewModel.isStreaming)

        memoryService.clearAll()
    }

    @Test func chatViewModelSendWithImageAttachments() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)

        // Create a small test image
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let testImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        viewModel.pendingImages = [PendingImage(image: testImage)]

        let mock = MockLLMProvider()
        mock.tokens = [.done]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = ""
        viewModel.send()

        try await Task.sleep(for: .milliseconds(500))

        #expect(viewModel.messages.count >= 2)
        #expect(viewModel.pendingImages.isEmpty)
        // User message should have image paths
        let userMsg = viewModel.messages.first(where: { $0.role == .user })
        #expect(userMsg?.hasImages ?? false)

        // Clean up attachment files
        for msg in viewModel.messages {
            for path in msg.imagePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        memoryService.clearAll()
    }

    @Test func chatViewModelSendEmptyInputIgnored() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        let memoryService = MemoryService()
        memoryService.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context, memoryService: memoryService)
        viewModel.inputText = "   "
        viewModel.send()

        // No messages should be added for whitespace-only input
        #expect(viewModel.messages.isEmpty)
    }
}

// MARK: - Serialized tests (shared mutable state)

@Suite(.serialized) @MainActor
struct MemoryServiceTests {

    @Test func jaccardShortFactThreshold() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["user likes chocolate cake"])

        let afterFirst = MemoryService.shared.allFactTexts()
        #expect(afterFirst.count == 1)

        await MemoryService.shared.storeFacts(["user likes vanilla cake"])

        let afterSecond = MemoryService.shared.allFactTexts()
        #expect(afterSecond.count == 2, "Jaccard 0.60 below threshold 0.75 — should be stored")

        await MemoryService.shared.storeFacts(["chocolate cake user likes"])

        let afterThird = MemoryService.shared.allFactTexts()
        #expect(afterThird.count == 2, "Jaccard 1.0 above threshold — should be rejected")
    }

    @Test func jaccardLongFactThreshold() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["user likes chocolate cake with cream frosting"])

        let afterFirst = MemoryService.shared.allFactTexts()
        #expect(afterFirst.count == 1)

        await MemoryService.shared.storeFacts(["user likes chocolate cake with cream topping"])

        let afterSecond = MemoryService.shared.allFactTexts()
        #expect(afterSecond.count == 1, "Jaccard 0.75 above long threshold 0.60 — should be rejected")

        await MemoryService.shared.storeFacts(["alice enjoys vanilla pie with fresh berries"])

        let afterThird = MemoryService.shared.allFactTexts()
        #expect(afterThird.count == 2, "Jaccard 0.167 below threshold 0.60 — should be stored")
    }

    @Test func storeFactTooShortRejected() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["short"]) // < 10 chars
        #expect(MemoryService.shared.allFactTexts().isEmpty)
    }

    @Test func removeFactsExactMatch() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["user lives in Berlin Germany"])
        #expect(MemoryService.shared.allFactTexts().count == 1)

        await MemoryService.shared.removeFacts(["user lives in Berlin Germany"])
        #expect(MemoryService.shared.allFactTexts().isEmpty)
    }

    @Test func removeFactsCaseInsensitive() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["User Lives In BERLIN"])
        #expect(MemoryService.shared.allFactTexts().count == 1)

        await MemoryService.shared.removeFacts(["user lives in berlin"])
        #expect(MemoryService.shared.allFactTexts().isEmpty)
    }

    @Test func removeFactsReportsNotFound() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["user lives in Berlin Germany"])
        let outcome = await MemoryService.shared.removeFacts([
            "user lives in Berlin Germany",
            "user lives in Paris France",
        ])
        #expect(outcome.removed.count == 1)
        #expect(outcome.removed.first?.contains("Berlin") == true)
        #expect(outcome.notFound == ["user lives in Paris France"])
        #expect(MemoryService.shared.allFactTexts().isEmpty)
    }

    @Test func storeFactsReportsStoredAndSkipped() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        let first = await MemoryService.shared.storeFacts(["user likes chocolate cake"])
        #expect(first.stored.count == 1)
        #expect(first.skipped.isEmpty)

        // Exact duplicate is reported as skipped, not silently swallowed.
        let second = await MemoryService.shared.storeFacts(["user likes chocolate cake"])
        #expect(second.stored.isEmpty)
        #expect(second.skipped.count == 1)
    }

    @Test func buildMemoryContextEmpty() async throws {
        // Bind a fresh in-memory context — the singleton may otherwise point at a
        // previous test's container, which is reset once that test ends (fatal crash).
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        MemoryService.shared.setModelContext(container.mainContext)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        let ctx = MemoryService.shared.buildMemoryContext()
        // Without facts loaded, returns empty
        #expect(ctx.isEmpty)
    }

    @Test func buildFullSystemPromptEmptyMemory() async throws {
        // Same fresh-context binding as above (see buildMemoryContextEmpty).
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        MemoryService.shared.setModelContext(container.mainContext)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        let prompt = MemoryService.shared.buildFullSystemPrompt(base: "You are helpful.", conversationID: nil)
        #expect(prompt.contains("You are helpful."))
    }

    @Test func conflictDetectionReplaces() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        // Store a fact about user's name
        await MemoryService.shared.storeFacts(["user name is Alice Johnson"])

        // Store a conflicting fact (same subject, different value)
        await MemoryService.shared.storeFacts(["user name is Bob Smith"])

        let facts = MemoryService.shared.allFactTexts()
        // The old fact should be replaced
        #expect(facts.count == 1)
        #expect(facts[0].contains("Bob"))
        #expect(!facts.contains("user name is Alice Johnson"))
        #expect(facts.contains("user name is Bob Smith"))
    }

    @Test func pruneOldEntries() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        // Adding new facts — all should survive prune with 90 day cutoff
        await MemoryService.shared.storeFacts(["fact number one here", "fact number two goes here"])
        #expect(MemoryService.shared.allFactTexts().count == 2)

        MemoryService.shared.pruneOldEntries(olderThan: 0) // prune everything
        #expect(MemoryService.shared.allFactTexts().isEmpty)
    }

    @Test func allFactsSorted() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["first fact goes here", "second fact now here"])
        let facts = MemoryService.shared.allFacts
        #expect(facts.count == 2)
    }

    @Test func deleteFact() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        await MemoryService.shared.storeFacts(["fact to delete later on"])
        let facts = MemoryService.shared.allFacts
        #expect(facts.count == 1)

        MemoryService.shared.deleteFact(facts[0])
        #expect(MemoryService.shared.allFactTexts().isEmpty)
    }


    @Test func memoryServiceIsEnabledToggle() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        MemoryService.shared.isEnabled = false
        await MemoryService.shared.storeFacts(["should not be stored here"])
        #expect(MemoryService.shared.allFactTexts().isEmpty)

        MemoryService.shared.isEnabled = true
    }

    @Test func normalizeTextDedup() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        MemoryService.shared.setModelContext(context)
        MemoryService.shared.clearAll()
        defer { MemoryService.shared.clearAll() }

        // Store a fact
        await MemoryService.shared.storeFacts(["user is 25 years old"])
        #expect(MemoryService.shared.allFactTexts().count == 1)

        // Near-identical normalized text should be rejected
        await MemoryService.shared.storeFacts(["User is 25 years old!"])
        #expect(MemoryService.shared.allFactTexts().count == 1, "Normalized duplicate should be rejected")
    }
}

// MARK: - MemoryDeduplicator Tests

struct MemoryDeduplicatorTests {

    @Test func wordSet() {
        let words = MemoryDeduplicator.wordSet(from: "Hello World, Test!")
        #expect(words == ["hello", "world", "test"])
    }

    @Test func wordSetEmpty() {
        let words = MemoryDeduplicator.wordSet(from: "")
        #expect(words.isEmpty)
    }

    @Test func normalizeText() {
        let norm = MemoryDeduplicator.normalizeText("User's name is Alice!")
        #expect(norm == "users name is alice")
    }

    @Test func normalizeTextNumbers() {
        let norm = MemoryDeduplicator.normalizeText("User is 25 years old")
        #expect(norm == "user is 25 years old")
    }

    @Test func extractSubject() {
        let subject = MemoryDeduplicator.extractSubject("user name is Alice Johnson")
        #expect(subject == ["user", "name", "alice"])
    }

    @Test func extractSubjectWithPossessive() {
        let subject = MemoryDeduplicator.extractSubject("User's favorite color is blue")
        #expect(subject == ["user", "favorite", "color"])
    }

    @Test func extractSubjectShort() {
        let subject = MemoryDeduplicator.extractSubject("likes pizza")
        #expect(subject == ["likes", "pizza"])
    }

    @Test func isDuplicateTextIdentical() {
        var wordCache: [UUID: Set<String>] = [:]
        var normCache: [UUID: String] = [:]
        let id = UUID()
        let fact = MemoryEntry(id: id, text: "user likes chocolate cake", conversationID: UUID())
        wordCache[id] = MemoryDeduplicator.wordSet(from: "user likes chocolate cake")
        normCache[id] = MemoryDeduplicator.normalizeText("user likes chocolate cake")

        let isDup = MemoryDeduplicator.isDuplicateText(
            "user likes chocolate cake",
            existingFacts: [fact],
            wordSetsCache: &wordCache,
            normalizedCache: &normCache
        )
        #expect(isDup)
    }

    @Test func isDuplicateTextDifferent() {
        var wordCache: [UUID: Set<String>] = [:]
        var normCache: [UUID: String] = [:]
        let id = UUID()
        let fact = MemoryEntry(id: id, text: "user likes chocolate cake", conversationID: UUID())
        wordCache[id] = MemoryDeduplicator.wordSet(from: "user likes chocolate cake")
        normCache[id] = MemoryDeduplicator.normalizeText("user likes chocolate cake")

        let isDup = MemoryDeduplicator.isDuplicateText(
            "user enjoys playing tennis",
            existingFacts: [fact],
            wordSetsCache: &wordCache,
            normalizedCache: &normCache
        )
        #expect(!isDup)
    }

    @Test func isDuplicateTextEmptyFact() {
        var wordCache: [UUID: Set<String>] = [:]
        var normCache: [UUID: String] = [:]
        let isDup = MemoryDeduplicator.isDuplicateText(
            "",
            existingFacts: [],
            wordSetsCache: &wordCache,
            normalizedCache: &normCache
        )
        #expect(isDup) // empty word set → duplicate
    }

    @Test func findConflictingFactDetected() {
        let id = UUID()
        let fact = MemoryEntry(id: id, text: "user name is Alice Johnson", conversationID: UUID())
        let wordCache: [UUID: Set<String>] = [id: MemoryDeduplicator.wordSet(from: "user name is Alice Johnson")]
        let normCache: [UUID: String] = [id: MemoryDeduplicator.normalizeText("user name is Alice Johnson")]

        let conflictID = MemoryDeduplicator.findConflictingFact(
            "user name is Bob Smith",
            existingFacts: [fact],
            wordSetsCache: wordCache,
            normalizedCache: normCache
        )
        #expect(conflictID == id)
    }

    @Test func findConflictingFactLikesNoConflict() {
        let id = UUID()
        let fact = MemoryEntry(id: id, text: "user really loves visiting Paris every summer", conversationID: UUID())
        let wordCache: [UUID: Set<String>] = [id: MemoryDeduplicator.wordSet(from: "user really loves visiting Paris every summer")]
        let normCache: [UUID: String] = [id: MemoryDeduplicator.normalizeText("user really loves visiting Paris every summer")]

        let conflictID = MemoryDeduplicator.findConflictingFact(
            "user really enjoys visiting Berlin every winter",
            existingFacts: [fact],
            wordSetsCache: wordCache,
            normalizedCache: normCache
        )
        #expect(conflictID == nil)
    }

    @Test func findConflictingFactNoConflict() {
        let id = UUID()
        let fact = MemoryEntry(id: id, text: "user name is Alice", conversationID: UUID())
        let wordCache: [UUID: Set<String>] = [id: MemoryDeduplicator.wordSet(from: "user name is Alice")]
        let normCache: [UUID: String] = [id: MemoryDeduplicator.normalizeText("user name is Alice")]

        let conflictID = MemoryDeduplicator.findConflictingFact(
            "user likes chocolate cake",
            existingFacts: [fact],
            wordSetsCache: wordCache,
            normalizedCache: normCache
        )
        #expect(conflictID == nil)
    }
}

// MARK: - MemoryContextBuilder Tests

struct MemoryContextBuilderTests {

    @Test func relevanceScoreBaseline() {
        let builder = MemoryContextBuilder(maxFacts: 50, maxMemoryChars: 3000, ageDecayHalfLife: 30)
        let fact = MemoryEntry(text: "test fact here", conversationID: UUID())
        let score = builder.relevanceScore(fact: fact, now: fact.timestamp)
        #expect(score > 0.9) // brand-new fact should score near 1.0
        #expect(score <= 1.5) // with usageCount=0, base=1.0 * exp(0) = 1.0
    }

    @Test func relevanceScoreWithUsage() {
        let builder = MemoryContextBuilder(maxFacts: 50, maxMemoryChars: 3000, ageDecayHalfLife: 30)
        let fact = MemoryEntry(text: "test", conversationID: UUID(), usageCount: 10)
        let score = builder.relevanceScore(fact: fact, now: fact.timestamp)
        #expect(score > 5.0) // (1 + 10*0.5) * exp(0) = 6.0
    }

    @Test func buildContextEmpty() {
        let builder = MemoryContextBuilder(maxFacts: 50, maxMemoryChars: 3000, ageDecayHalfLife: 30)
        let result = builder.buildContext(
            factsCache: [],
            embeddingService: EmbeddingService.shared,
            lastQueryText: "",
            lastQueryEmbedding: nil
        )
        #expect(result.context.isEmpty)
        #expect(result.includedFacts.isEmpty)
    }

    @Test func buildContextWrapsInMemoryTag() {
        let builder = MemoryContextBuilder(maxFacts: 50, maxMemoryChars: 3000, ageDecayHalfLife: 30)
        let fact = MemoryEntry(text: "user likes cookies", conversationID: UUID())
        let result = builder.buildContext(
            factsCache: [fact],
            embeddingService: EmbeddingService.shared,
            lastQueryText: "",
            lastQueryEmbedding: nil
        )
        #expect(result.context.hasPrefix("<memory>\n"))
        #expect(result.context.hasSuffix("</memory>"))
        #expect(result.context.contains("user likes cookies"))
        #expect(result.includedFacts.count == 1)
    }

    @Test func buildContextRespectsMaxFacts() {
        let builder = MemoryContextBuilder(maxFacts: 2, maxMemoryChars: 3000, ageDecayHalfLife: 30)
        let facts = (0..<5).map {
            MemoryEntry(text: "fact number \($0) goes here", conversationID: UUID())
        }
        let result = builder.buildContext(
            factsCache: facts,
            embeddingService: EmbeddingService.shared,
            lastQueryText: "",
            lastQueryEmbedding: nil
        )
        #expect(result.includedFacts.count == 2)
    }
}

// MARK: - AttachmentProcessor Tests

struct AttachmentProcessorTests {

    @Test func attachmentsDirectoryExists() {
        let dir = AttachmentProcessor.attachmentsDirectory
        #expect(dir.lastPathComponent == "Attachments")
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func saveImagesToTmpEmpty() {
        let paths = AttachmentProcessor.saveImages([])
        #expect(paths.isEmpty)
    }

    @Test func saveImagesToTmp() {
        let size = CGSize(width: 10, height: 10)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let paths = AttachmentProcessor.saveImages([image])
        #expect(paths.count == 1)
        #expect(paths[0].hasSuffix(".jpg"))
        #expect(FileManager.default.fileExists(atPath: paths[0]))
        // Cleanup
        try? FileManager.default.removeItem(atPath: paths[0])
    }
}
