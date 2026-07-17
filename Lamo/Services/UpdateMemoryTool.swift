import Foundation
import LiteRTLM

/// Tool that Gemma 4 can call to save facts and update conversation summary.
///
/// The model calls this automatically during its response when it detects
/// facts worth remembering or when the conversation needs summarizing.
struct UpdateMemoryTool: Tool {
    static let name = "update_memory"
    static let description = """
        Save important facts about the user and optionally summarize the conversation. \
        Call with facts when the user shares personal info. \
        Call with summary when the conversation is long and key points should be preserved.
        """

    @ToolParam(description: "New facts about the user to remember. Each fact is one short sentence.")
    var facts: [String]?

    @ToolParam(description: "Facts to forget (if user corrects something).")
    var forget: [String]?

    @ToolParam(description: "Brief summary of the conversation so far (2-3 sentences). Use when conversation is long.")
    var summary: String?

    func run() async throws -> Any {
        let hasFacts = facts != nil && !(facts?.isEmpty ?? true)
        let hasForget = forget != nil && !(forget?.isEmpty ?? true)
        let hasSummary = summary != nil && !(summary?.isEmpty ?? true)

        var parts: [String] = []
        if let f = facts { parts.append("facts: [\(f.count) items]") }
        if let f = forget { parts.append("forget: [\(f.count) items]") }
        if summary != nil { parts.append("summary present") }
        let paramsDesc = parts.joined(separator: ", ")

        await ToolCallReporter.shared.reportCall(name: Self.name, params: "{\(paramsDesc)}")

        guard hasFacts || hasForget || hasSummary else {
            let result: [String: Any] = ["status": "noop", "info": "No memory changes provided"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: "\(result)")
            return result
        }

        if hasFacts, let facts = facts { await MemoryService.shared.storeFacts(facts) }
        if hasForget, let forget = forget { await MemoryService.shared.removeFacts(forget) }
        if hasSummary, let summary = summary { await MemoryService.shared.updateConversationSummary(summary) }

        let result: [String: Any] = ["status": "saved"]
        await ToolCallReporter.shared.reportResult(name: Self.name, result: "\(result)")
        return result
    }
}
