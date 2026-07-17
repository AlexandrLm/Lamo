import Foundation
import JavaScriptCore
import LiteRTLM

// MARK: - Code Sandbox Tool

struct CodeSandboxTool: Tool {
    static let name = "code_sandbox"
    static let description = "Run JavaScript code in a secure sandbox. Use for calculations, data analysis, and text processing."

    @ToolParam(description: "JavaScript code to execute. Use `result` variable to return output.")
    var code: String

    func run() async throws -> Any {
        let codePreview = code.count > 120 ? String(code.prefix(120)) + "..." : code
        await ToolCallReporter.shared.reportCall(name: Self.name, params: "{\"code\": \"\(codePreview.replacingOccurrences(of: "\"", with: "\\\""))\"}")

        let (output, error) = await executeWithTimeout(code: code)

        var result: [String: Any] = [:]
        if let output = output {
            result["output"] = output
        }
        if let error = error {
            result["error"] = error
        }

        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)

        let limit = await AgenticLoopBudget.shared.consumeIteration()
        let truncated = await TokenTruncator.truncateResult(result, maxTokens: limit)
        guard let finalResult = truncated as? [String: Any] else {
            return result
        }
        return finalResult
    }

    // MARK: - Sandbox Execution

    /// Runs JavaScript in a JSContext with a 5-second timeout.
    /// The timeout is best-effort: JS execution on the main thread cannot be preempted,
    /// but the timeout task will win the race if the sandbox task is cancelled.
    private func executeWithTimeout(code: String) async -> (output: String?, error: String?) {
        await withTaskGroup(of: (String?, String?).self) { group in
            group.addTask { @MainActor in
                return runInSandbox(code: code)
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return (nil, nil) }
                return (nil, "Execution timed out after 5 seconds")
            }

            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// Synchronously evaluates JavaScript inside a sandboxed JSContext.
    /// MUST be called on the main thread (JSContext requirement).
    @MainActor
    private func runInSandbox(code: String) -> (output: String?, error: String?) {
        guard let context = JSContext() else {
            return (nil, "Failed to create JavaScript context")
        }

        // Capture exceptions thrown in the sandbox
        context.exceptionHandler = { _, exception in
            // Stored on context.exception, read after evaluateScript
            _ = exception
        }

        // Evaluate the user's code
        let evalResult = context.evaluateScript(code)

        // Check for runtime exceptions
        if let exception = context.exception {
            let errorMessage = exception.toString() ?? "Unknown JavaScript error"
            return (nil, errorMessage)
        }

        // Capture the `result` variable if set by the user's script
        let resultValue = context.objectForKeyedSubscript("result")
        let output: String
        if let resultStr = resultValue?.toString(), !resultStr.isEmpty, resultStr != "undefined" {
            output = resultStr
        } else if let evalStr = evalResult?.toString(), !evalStr.isEmpty, evalStr != "undefined" {
            // Fall back to the last expression's value
            output = evalStr
        } else if evalResult?.isUndefined == true && (resultValue?.isUndefined ?? true) {
            output = ""
        } else {
            output = evalResult?.toString() ?? ""
        }

        return (output, nil)
    }
}
