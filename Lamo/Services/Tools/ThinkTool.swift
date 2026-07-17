import Foundation
import LiteRTLM

// MARK: - Think Tool

/// A no-op tool that lets the model "pause and think" mid-response.
/// When the model calls this, it signals it needs to reason through
/// something before continuing. The tool returns a brief acknowledgment,
/// and the model resumes generating in the same conversation.
///
/// Zero memory overhead — no second KV-cache, no sub-conversation.
/// The model just gets a nudge to continue its chain of thought.
struct ThinkTool: Tool {
    static let name = "think"
    static let description = """
        Call when you need to reason through a complex problem step by step \
        before giving your final answer. Use this to break down hard \
        questions, plan multi-step tasks, or verify your logic. \
        After calling, continue your response with your analysis.
        """

    @ToolParam(description: "What you need to think about. Be specific about the reasoning step.")
    var about: String

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(
            name: Self.name,
            params: "{\"about\": \"\(about.prefix(80))\"}"
        )
        let result: [String: Any] = [
            "status": "ok",
            "instruction": "Continue your response with your analysis of: \(about)",
        ]
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }
}
