import Foundation

/// Bridges tool call reports from any tool's run() into the streaming pipeline.
/// Tools call `reportCall` before execution and `reportResult` after,
/// and the registered continuation yields StreamingToken events to the UI.
@globalActor
actor ToolCallReporter {
    static let shared = ToolCallReporter()

    private var continuation: AsyncStream<StreamingToken>.Continuation?

    func register(continuation: AsyncStream<StreamingToken>.Continuation) {
        self.continuation = continuation
    }

    func reset() {
        continuation = nil
    }

    func reportCall(name: String, params: String) {
        continuation?.yield(.toolCall(name: name, params: params))
    }

    func reportResult(name: String, result: String) {
        // Truncate long results to avoid flooding the UI
        let truncated = result.count > 2000
            ? String(result.prefix(2000)) + "\n... [truncated]"
            : result
        continuation?.yield(.toolResult(name: name, result: truncated))
    }
}
