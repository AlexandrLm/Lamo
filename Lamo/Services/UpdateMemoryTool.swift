import Foundation
import LiteRTLM

/// Tool that Gemma 4 can call to save, update, remove, or read remembered facts.
///
/// The model calls this automatically during its response when it detects
/// facts worth remembering or when the conversation needs summarizing.
///
/// Key behaviors:
/// - New facts are automatically deduplicated and conflicting old facts are replaced.
/// - Forgetting requires exact text — always use include_existing=true first to see current facts.
/// - Conversation summaries persist across sessions and help with long context windows.
struct UpdateMemoryTool: Tool {
    static let name = ToolDefinitions.UpdateMemory.name
    static let description = ToolDefinitions.UpdateMemory.description

    @ToolParam(description: "New facts about the user to remember. Each fact is one short sentence. Old contradictory facts are auto-replaced.")
    var facts: [String]?

    @ToolParam(description: "Exact full text of facts to forget (not substring). Use include_existing=true first to see current facts and copy exact text.")
    var forget: [String]?

    @ToolParam(description: "Brief summary of the conversation so far (2-3 sentences). Use when conversation is long.")
    var summary: String?

    @ToolParam(description: "Set to true to read back all currently stored facts. Always do this before forgetting or updating.")
    var includeExisting: Bool = false

    func run() async throws -> Any {
        // Owning conversation comes from the active stream (set by LiteRTLMProvider),
        // since ToolManager re-decodes tool instances from JSON args before run().
        let conversationID = await ToolCallReporter.shared.currentConversationID
        let hasFacts = facts != nil && !(facts?.isEmpty ?? true)
        let hasForget = forget != nil && !(forget?.isEmpty ?? true)
        let hasSummary = summary != nil && !(summary?.isEmpty ?? true)

        var parts: [String] = []
        if let f = facts { parts.append("facts: [\(f.count) items]") }
        if let f = forget { parts.append("forget: [\(f.count) items]") }
        if summary != nil { parts.append("summary present") }
        if includeExisting { parts.append("includeExisting: true") }
        let paramsDesc = parts.joined(separator: ", ")

        await ToolCallReporter.shared.reportCall(name: Self.name, params: "{\(paramsDesc)}")

        guard hasFacts || hasForget || hasSummary || includeExisting else {
            let noop: [String: Any] = ["status": "noop", "hint": "No memory changes requested. Provide facts, forget, summary, or set include_existing=true."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: noop)
            return noop
        }

        var result: [String: Any] = ["status": hasFacts || hasForget || hasSummary ? "saved" : "ok"]

        if hasFacts, let facts = facts {
            let outcome = await MemoryService.shared.storeFacts(facts, conversationID: conversationID)
            result["stored"] = outcome.stored
            if !outcome.skipped.isEmpty {
                result["skipped_duplicates"] = outcome.skipped
            }
        }
        if hasForget, let forget = forget {
            let outcome = await MemoryService.shared.removeFacts(forget)
            result["forgot"] = outcome.removed
            if !outcome.notFound.isEmpty {
                result["not_found"] = outcome.notFound
                result["hint"] = "Some facts were not found — exact text is required. Call again with include_existing=true to see the stored facts, then retry with their exact text."
            }
        }
        if hasSummary, let summary = summary {
            await MemoryService.shared.updateConversationSummary(summary, conversationID: conversationID)
        }

        if includeExisting {
            let allFacts = MemoryService.shared.allFactTexts()
            if allFacts.isEmpty {
                result["existing_facts"] = []
                result["note"] = "No facts stored yet."
            } else {
                // Numbered list for easy reference when model wants to forget specific facts
                var numbered: [String] = []
                for (i, fact) in allFacts.enumerated() {
                    numbered.append("[\(i)] \(fact)")
                }
                result["existing_facts"] = allFacts
                result["numbered"] = numbered
                result["total"] = allFacts.count
            }
        }
        // Truncate to budget without ever dropping the write itself (no soft-stop check:
        // memory writes are cheap, local, and must not be lost).
        let limited = await AgenticLoopBudget.shared.limitResult(result)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
        return limited
    }
}
