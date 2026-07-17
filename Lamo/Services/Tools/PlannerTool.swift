import Foundation
import LiteRTLM

// MARK: - Planner Tool

/// A meta-tool: the model calls `create_plan` to declare a multi-step plan.
/// ChatViewModel detects the plan and shows a progress card in the UI.
/// Each subsequent tool call advances the plan progress automatically.
struct PlannerTool: Tool {
    static let name = "create_plan"
    static let description = """
        Create a step-by-step plan for complex tasks. \
        Call this BEFORE executing tools for multi-step problems. \
        Returns a plan ID — then execute tools in order.
        """

    @ToolParam(description: "Short goal of the plan (e.g. 'Plan a trip to SPb this weekend').")
    var goal: String

    @ToolParam(description: """
        JSON array of steps. Each step: {"tool": "tool_name", "description": "what this step does"}. \
        Example: [{"tool":"calendar","description":"Check Sat-Sun availability"}, \
        {"tool":"weather","description":"Get SPb weekend forecast"}]
        """)
    var steps: String

    func run() async throws -> Any {
        let paramsDesc = "{\"goal\": \"\(goal)\", \"steps\": \"\(steps.prefix(100))...\"}"
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsDesc)

        // Parse steps from JSON string
        guard let data = steps.data(using: .utf8),
              let jsonSteps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            let err: [String: Any] = ["error": "Invalid steps JSON. Must be an array of {tool, description} objects."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }

        let parsedSteps: [[String: Any]] = jsonSteps.compactMap { step in
            guard let tool = step["tool"] as? String,
                  let desc = step["description"] as? String else { return nil }
            return ["tool": tool, "description": desc]
        }

        guard !parsedSteps.isEmpty else {
            let err: [String: Any] = ["error": "Plan must have at least one step."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }

        // Register the plan
        await AgenticLoopState.shared.startPlan(goal: goal, steps: parsedSteps)

        let result: [String: Any] = [
            "plan_created": true,
            "goal": goal,
            "total_steps": parsedSteps.count,
            "steps": parsedSteps,
        ]
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }
}
