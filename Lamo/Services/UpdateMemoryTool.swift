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
    static let name = "update_memory"
    static let description = """
        Manage remembered facts about the user. \
        Use 'facts' to save new personal info (each fact one short sentence, e.g. "User lives in Berlin"). \
        Old contradictory facts are automatically replaced — no need to manually forget first. \
        Use 'forget' to remove facts by EXACT text (use include_existing=true first to see what's stored). \
        Use 'summary' for a brief 2-3 sentence recap of the conversation so far. \
        Use 'include_existing'=true to read all stored facts before making changes. \
        DO NOT call for generic assistant tasks or temporary info — only for persistent personal facts.
        """

    @ToolParam(description: "New facts about the user to remember. Each fact is one short sentence. Old contradictory facts are auto-replaced.")
    var facts: [String]?

    @ToolParam(description: "Exact full text of facts to forget (not substring). Use include_existing=true first to see current facts and copy exact text.")
    var forget: [String]?

    @ToolParam(description: "Brief summary of the conversation so far (2-3 sentences). Use when conversation is long.")
    var summary: String?

    @ToolParam(description: "Set to true to read back all currently stored facts. Always do this before forgetting or updating.")
    var includeExisting: Bool = false

    func run() async throws -> Any {
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
            let noop: [String: Any] = ["status": "noop", "info": "No memory changes or read requested"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: noop)
            return noop
        }

        if hasFacts, let facts = facts { await MemoryService.shared.storeFacts(facts) }
        if hasForget, let forget = forget { await MemoryService.shared.removeFacts(forget) }
        if hasSummary, let summary = summary { await MemoryService.shared.updateConversationSummary(summary) }

        var result: [String: Any] = ["status": hasFacts || hasForget || hasSummary ? "saved" : "ok"]
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
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }
}
