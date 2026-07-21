import Foundation
import SwiftData
import Testing
@testable import Lamo

// MARK: - Test Doubles

/// Mock LLMProvider that yields a configurable sequence of tokens.
/// Each call to `streamResponse` emits all queued tokens then finishes the stream.
final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    let name = "Mock"
    var tokens: [StreamingToken] = []

    func streamResponse(messages: [ChatMessage]) -> AsyncStream<StreamingToken> {
        let snapshot = tokens
        return AsyncStream { continuation in
            for token in snapshot {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}

// MARK: - Tests

/// Top-level suite: pure-logic tests that don't touch shared mutable state.
/// These run in parallel.
struct LamoTests {

    // MARK: - 1. ChatViewModel.send()

    @Test func chatViewModelSendCreatesUserMessageAndStartsStreaming() async throws {
        // Setup in-memory SwiftData stack
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Conversation.self, Message.self, MemoryEntry.self,
            configurations: config
        )
        let context = container.mainContext
        let conversation = Conversation()
        context.insert(conversation)
        try context.save()

        MemoryService.shared.setModelContext(context)

        let viewModel = ChatViewModel(conversation: conversation, modelContext: context)

        // Inject mock that emits .done right away
        let mock = MockLLMProvider()
        mock.tokens = [.done]
        viewModel.llmProviderOverride = mock

        viewModel.inputText = "Hello, world!"
        viewModel.send()

        // The send() method spawns a Task on @MainActor.
        // Yield via a brief sleep so the streaming Task can drain
        // the mock stream and call finalizeStreaming.
        try await Task.sleep(for: .milliseconds(500))

        // After streaming completes, we expect:
        // - At least 2 messages (user + assistant)
        #expect(viewModel.messages.count >= 2)
        // - First message is the user's
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].content == "Hello, world!")
        // - Input text was cleared
        #expect(viewModel.inputText.isEmpty)
        // - Streaming has finished (mock yielded .done → finalizeStreaming)
        #expect(!viewModel.isStreaming)
        // - The assistant message is no longer streaming
        #expect(viewModel.messages.last?.isStreaming == false)

        // Clean up
        MemoryService.shared.clearAll()
    }

    // MARK: - 2. ContextTracker budget calculation

    @Test func contextTrackerBudgetIncludesRecentMessagesDropsOld() {
        // Create 5 messages with known token counts.
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "msg1"),
            ChatMessage(id: UUID(), role: .assistant, content: "reply1"),
            ChatMessage(id: UUID(), role: .user, content: "msg2"),
            ChatMessage(id: UUID(), role: .assistant, content: "reply2"),
            ChatMessage(id: UUID(), role: .user, content: "msg3"),
        ]

        // Each message is 100 tokens (except last which is 50)
        var tokenCounts: [UUID: Int] = [:]
        for (i, msg) in messages.enumerated() {
            tokenCounts[msg.id] = i == messages.count - 1 ? 50 : 100
        }

        // Budget = 1024 - 100 - 0 - 512 = 412.
        // Walk most-recent-first, excluding last message (msg3):
        //   reply2(100) → fits, used=100
        //   msg2(100)   → fits, used=200
        //   reply1(100) → fits, used=300
        //   msg1(100)   → fits, used=400 (400 ≤ 412)
        // All 4 history messages fit.
        let result = ContextTracker.calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 100,
            memoryTokens: 0,
            maxNumTokens: 1024
        )
        #expect(result.includedIDs.count == 4)
        #expect(result.dropped.isEmpty)
        #expect(result.usedTokens == 400)

        // Shrink budget: maxNumTokens=512 → effective=512, budget=512-100-0-512=-100 → max(0,-100)=0
        let result2 = ContextTracker.calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 100,
            memoryTokens: 0,
            maxNumTokens: 512
        )
        #expect(result2.includedIDs.isEmpty)
        #expect(result2.dropped.count == 4)
    }

    @Test func contextTrackerBudgetWithMemoryTokens() {
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "hello"),
            ChatMessage(id: UUID(), role: .assistant, content: "hi"),
            ChatMessage(id: UUID(), role: .user, content: "how are you"),
        ]

        var tokenCounts: [UUID: Int] = [:]
        for (i, msg) in messages.enumerated() {
            tokenCounts[msg.id] = i == messages.count - 1 ? 30 : 50
        }

        // maxNumTokens=2048, sys=200, mem=300 → budget = 2048-200-300-512 = 1036
        let result = ContextTracker.calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: 200,
            memoryTokens: 300,
            maxNumTokens: 2048
        )

        // Last message excluded from budget walk.
        // History: assistant(50) → fits, user(50) → fits → usedTokens=100
        #expect(result.includedIDs.count == 2)
        #expect(result.dropped.isEmpty)
        #expect(result.usedTokens == 100)
    }

    // MARK: - 3. ToolFilter category selection

    @Test func toolFilterSelectsCorrectCategoriesByQuery() {
        let allTools = [
            "calculator", "web_search", "wikipedia", "fetch_url",
            "calendar", "contacts", "update_memory",
            "get_location", "weather", "shortcuts",
            "health",
        ]

        // Knowledge query → knowledge tools
        let knowledgeResult = ToolFilter.filter(toolNames: allTools, query: "search for latest news about AI")
        #expect(knowledgeResult.contains("web_search"))
        #expect(knowledgeResult.contains("wikipedia"))
        #expect(knowledgeResult.contains("fetch_url"))
        #expect(!knowledgeResult.contains("calendar"))
        #expect(!knowledgeResult.contains("health"))

        // Productivity query → productivity tools
        let prodResult = ToolFilter.filter(toolNames: allTools, query: "schedule a meeting and remind me about it")
        #expect(prodResult.contains("calendar"))
        #expect(prodResult.contains("update_memory"))
        #expect(!prodResult.contains("web_search"))
        #expect(!prodResult.contains("weather"))

        // System query → system tools
        let sysResult = ToolFilter.filter(toolNames: allTools, query: "what is the weather forecast for today")
        #expect(sysResult.contains("weather"))
        #expect(sysResult.contains("get_location"))

        // Health query → health tools
        let healthResult = ToolFilter.filter(toolNames: allTools, query: "how many steps did I take today")
        #expect(healthResult.contains("health"))
        #expect(!healthResult.contains("calculator"))

        // Code query → code tools
        let codeResult = ToolFilter.filter(toolNames: allTools, query: "calculate 2+2 and run this script")
        #expect(codeResult.contains("calculator"))

        // Vague/greeting query → no category match → only core tools (core is empty → empty)
        let vagueResult = ToolFilter.filter(toolNames: allTools, query: "hello how are you")
        #expect(vagueResult.isEmpty)
    }

    @Test func toolFilterMultiCategoryQuery() {
        let allTools = ["calculator", "web_search", "calendar", "weather", "health"]

        // Query matching both knowledge and productivity
        let result = ToolFilter.filter(
            toolNames: allTools,
            query: "search the web and add a calendar event"
        )
        #expect(result.contains("web_search"))
        #expect(result.contains("calendar"))
        // Tools from unmatched categories excluded
        #expect(!result.contains("health"))
        #expect(!result.contains("weather"))
    }

    // MARK: - 5. RepetitionDetector loop detection

    @Test func repetitionDetectorDetectsConsecutiveRepeats() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)

        // Build prefix to exceed minBufferSize (200 chars)
        var prefix = ""
        for i in 0..<50 {
            prefix += "padding text number \(i) goes here. "
        }

        // Use a 10-char pattern (10 is in the detection stride 5,10,15,...,80)
        // Repeated 4 times → 40 chars of consecutive repeats
        let pattern = "ABCDEFGHIJ"
        let repeated = String(repeating: pattern, count: 4)
        let input = prefix + repeated

        let detected = detector.feed(input)
        #expect(detected, "4 consecutive repeats of a 10-char pattern should be detected")
    }

    @Test func repetitionDetectorPassesNormalText() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)

        var text = ""
        for i in 0..<60 {
            text += "This is sentence number \(i) with some variety here. "
        }

        let detected = detector.feed(text)
        #expect(!detected, "Varied text should not trigger loop detection")
    }

    @Test func repetitionDetectorDetectsLineLoop() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)

        var prefix = ""
        for i in 0..<40 {
            prefix += "Line \(i) of the test prefix goes right here.\n"
        }

        let repeatedLine = "This is the same line repeated over and over.\n"
        let input = prefix + String(repeating: repeatedLine, count: 4)

        let detected = detector.feed(input)
        #expect(detected, "Repeated line 4 times should trigger line loop detection")
    }

    @Test func repetitionDetectorBelowMinBufferReturnsFalse() {
        let detector = RepetitionDetector(windowSize: 2000, minBufferSize: 200, checkFrequency: 1)

        let detected = detector.feed("short text")
        #expect(!detected, "Below min buffer size should always return false")
    }

    // MARK: - Existing tests (preserved)

    @Test func presetModelProperties() {
        for model in PresetModel.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.filename.isEmpty)
            #expect(model.downloadURL != nil)
            #expect(model.fileSizeGB > 0)
            #expect(!model.parameterCount.isEmpty)
        }
    }

    @Test func safeMaxTokensPositive() {
        let manager = ProviderManager.shared
        #expect(manager.isEngineReady || manager.engineError != nil || manager.litertLMModelPath == nil)
    }
}

// MARK: - Serialized tests (shared mutable state)

/// Tests that mutate MemoryService.shared (a singleton) run serially
/// to avoid races on the shared modelContext and factsCache.
@Suite(.serialized)
struct MemoryServiceTests {

    // MARK: - 4. MemoryService Jaccard duplicate detection

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

        // Store base fact (4 words → short fact, threshold = 0.75)
        await MemoryService.shared.storeFacts(["user likes chocolate cake"])

        let afterFirst = MemoryService.shared.allFactTexts()
        #expect(afterFirst.count == 1)

        // Near-duplicate: Jaccard = 3/5 = 0.60 → below threshold (0.75), should be stored
        // "user likes chocolate cake" → {user, likes, chocolate, cake}
        // "user likes vanilla cake"   → {user, likes, vanilla, cake}
        await MemoryService.shared.storeFacts(["user likes vanilla cake"])

        let afterSecond = MemoryService.shared.allFactTexts()
        #expect(afterSecond.count == 2, "Jaccard 0.60 below threshold 0.75 — should be stored")

        // Identical word set, different order: Jaccard = 4/4 = 1.0 > 0.75 → rejected
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

        // Store 7-word fact (long → threshold = 0.60)
        await MemoryService.shared.storeFacts(["user likes chocolate cake with cream frosting"])

        let afterFirst = MemoryService.shared.allFactTexts()
        #expect(afterFirst.count == 1)

        // Jaccard = 6/8 = 0.75 > 0.60 → duplicate, should be rejected
        // "user likes chocolate cake with cream frosting" → 7 unique words
        // "user likes chocolate cake with cream topping"  → 7 unique words
        // intersection = 6 (user, likes, chocolate, cake, with, cream)
        // union = 8 (frosting + topping are unique)
        await MemoryService.shared.storeFacts(["user likes chocolate cake with cream topping"])

        let afterSecond = MemoryService.shared.allFactTexts()
        #expect(afterSecond.count == 1, "Jaccard 0.75 above long threshold 0.60 — should be rejected")

        // Jaccard = 2/12 ≈ 0.167 < 0.60 → not duplicate, should be stored
        await MemoryService.shared.storeFacts(["alice enjoys vanilla pie with fresh berries"])

        let afterThird = MemoryService.shared.allFactTexts()
        #expect(afterThird.count == 2, "Jaccard 0.167 below threshold 0.60 — should be stored")
    }
}
