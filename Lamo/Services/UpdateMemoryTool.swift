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
        if let facts = facts, !facts.isEmpty {
            await MemoryService.shared.storeFacts(facts)
        }
        if let forget = forget, !forget.isEmpty {
            await MemoryService.shared.removeFacts(forget)
        }
        if let summary = summary, !summary.isEmpty {
            await MemoryService.shared.updateConversationSummary(summary)
        }
        return ["status": "saved"]
    }
}
