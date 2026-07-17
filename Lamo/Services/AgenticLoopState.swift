import Foundation
import Combine

// MARK: - Agentic Loop State

/// Shared state for plan tracking and scratchpad across the agentic loop.
/// Observed by the UI to show plan progress cards.
@MainActor
final class AgenticLoopState: ObservableObject {
    static let shared = AgenticLoopState()

    // MARK: - Plan State

    @Published var activePlan: Plan?
    @Published var currentStepIndex: Int = 0
    @Published var isPlanActive: Bool = false

    struct Plan: Identifiable {
        let id = UUID()
        let goal: String
        var steps: [PlanStep]
    }

    struct PlanStep: Identifiable {
        let id = UUID()
        let tool: String
        let description: String
        var status: StepStatus = .pending
    }

    enum StepStatus: String {
        case pending, running, done, failed
    }

    // MARK: - Plan Lifecycle

    func startPlan(goal: String, steps: [[String: Any]]) {
        let planSteps = steps.compactMap { step -> PlanStep? in
            guard let tool = step["tool"] as? String,
                  let desc = step["description"] as? String else { return nil }
            return PlanStep(tool: tool, description: desc)
        }
        guard !planSteps.isEmpty else { return }

        activePlan = Plan(goal: goal, steps: planSteps)
        currentStepIndex = 0
        isPlanActive = true

        // Mark first step as running
        if !planSteps.isEmpty {
            activePlan?.steps[0].status = .running
        }
    }

    /// Called when a tool completes. Advances the plan progress if the tool
    /// name matches the current expected step.
    func recordToolCompletion(toolName: String, success: Bool) {
        guard isPlanActive, let plan = activePlan else { return }

        let idx = currentStepIndex
        guard idx < plan.steps.count else { return }

        // Mark current step
        activePlan?.steps[idx].status = success ? .done : .failed

        // Advance to next step
        currentStepIndex += 1
        if currentStepIndex < plan.steps.count {
            activePlan?.steps[currentStepIndex].status = .running
        } else {
            // All steps complete
            isPlanActive = false
        }
    }

    func cancelPlan() {
        activePlan = nil
        currentStepIndex = 0
        isPlanActive = false
    }

    /// Summary of completed steps for context injection.
    var planSummary: String {
        guard let plan = activePlan else { return "" }
        let doneSteps = plan.steps.prefix(currentStepIndex)
            .filter { $0.status == .done }
        guard !doneSteps.isEmpty else { return "" }

        let lines = doneSteps.map { step in
            "  ✓ \(step.tool): \(step.description)"
        }
        return """
        <plan_progress goal="\(plan.goal)">
        \(lines.joined(separator: "\n"))
        </plan_progress>
        """
    }
}
