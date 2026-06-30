import Foundation
import LiteRTLM

/// Tool that Gemma 4 can call to save facts about the user.
///
/// When the model decides something is worth remembering (name, preferences,
/// projects, dates), it calls this tool automatically during its response.
/// No separate LLM extraction call needed.
///
/// The engine handles tool calls automatically:
/// 1. Model generates tool call → engine intercepts
/// 2. Engine calls `run()` → facts saved to MemoryService
/// 3. Engine returns result to model → model continues response
struct UpdateMemoryTool: Tool {
    static let name = "update_memory"
    static let description = """
        Save important facts about the user for future conversations. \
        Call this when the user shares personal information, preferences, \
        projects, dates, or any details worth remembering long-term. \
        Each fact should be a short, self-contained sentence.
        """

    @ToolParam(description: "List of new facts about the user to remember. Each fact should be one short sentence, e.g. ['User's name is Alexey', 'User is an iOS developer']")
    var facts: [String]

    @ToolParam(description: "List of facts to forget (if user corrects something). Each should match an existing fact.")
    var forget: [String]?

    func run() async throws -> Any {
        await MemoryService.shared.storeFacts(facts)
        if let forget = forget {
            await MemoryService.shared.removeFacts(forget)
        }
        return ["status": "saved", "facts_count": facts.count]
    }
}
