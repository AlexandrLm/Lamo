import Foundation
import LiteRTLM

struct UpdateMemoryTool: Tool {
    static let name = ToolDefinitions.UpdateMemory.name
    static let description = ToolDefinitions.UpdateMemory.description

    @ToolParam(description: "New facts about the user to remember (max 20 per call). Each fact is one short sentence. Old contradictory facts are auto-replaced.")
    var facts: [String]?

    @ToolParam(description: "Facts to forget: exact text, [index] from include_existing, or close paraphrase. Use include_existing=true first.")
    var forget: [String]?

    @ToolParam(description: "Brief summary of the conversation so far (2-3 sentences). Use when conversation is long.")
    var summary: String?

    @ToolParam(description: "Set to true to read back all currently stored facts. Always do this before forgetting or updating.")
    var includeExisting: Bool = false

    func run() async throws -> Any {
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
                result["hint"] = "Some facts were not found. Call again with include_existing=true, then retry with exact text or [index]."
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
                var numbered: [String] = []
                for (i, fact) in allFacts.enumerated() {
                    numbered.append("[\(i)] \(fact)")
                }
                result["existing_facts"] = allFacts
                result["numbered"] = numbered
                result["total"] = allFacts.count
            }
        }
        if includeExisting {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }
        let limited = await AgenticLoopBudget.shared.limitResult(result)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
        return limited
    }
}
