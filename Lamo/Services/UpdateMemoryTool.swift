import Foundation
import LiteRTLM

/// Tool that Gemma 4 can call to save facts and update conversation summary.
///
/// The model calls this automatically during its response when it detects
/// facts worth remembering or when the conversation needs summarizing.
struct UpdateMemoryTool: Tool {
    static let name = "update_memory"
    static let description = """
        Save, remove, or read important facts about the user. \
        Call with 'facts' when the user shares personal info — each fact is one short sentence. \
        Call with 'forget' to remove facts by exact text match. \
        Call with 'include_existing' = true to read all currently stored facts. \
        Call with 'summary' when the conversation is long and key points should be preserved.
        """

    @ToolParam(description: "New facts about the user to remember. Each fact is one short sentence.")
    var facts: [String]?

    @ToolParam(description: "Exact text of facts to forget. Must match stored fact text exactly. Use include_existing=true first to see current facts.")
    var forget: [String]?

    @ToolParam(description: "Brief summary of the conversation so far (2-3 sentences). Use when conversation is long.")
    var summary: String?

    @ToolParam(description: "Set to true to read back all currently stored facts. Use before updating to avoid duplicates.")
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
            result["existing_facts"] = MemoryService.shared.allFactTexts()
        }
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }
}
