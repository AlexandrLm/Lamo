import Foundation

/// Bridges tool call reports from any tool's run() into the streaming pipeline.
/// Tools call `reportCall` before execution and `reportResult` after,
/// and the registered continuation yields StreamingToken events to the UI.
@globalActor
actor ToolCallReporter {
    static let shared = ToolCallReporter()

    private var continuation: AsyncStream<StreamingToken>.Continuation?
    /// Conversation that owns the currently streaming inference. Set alongside
    /// `register` so tools (e.g. UpdateMemoryTool) can persist per-conversation
    /// state without app-global mutable singletons. Nil outside an active stream.
    var currentConversationID: UUID?

    /// Bumps on every register/reset so late tasks from a previous stream
    /// can't yield into the new continuation (stale guard).
    private var generation = 0

    func register(continuation: AsyncStream<StreamingToken>.Continuation) {
        generation &+= 1
        self.continuation = continuation
    }

    /// Set the conversation owning this stream (isolated so callers can hop cleanly).
    func setConversationID(_ id: UUID?) {
        currentConversationID = id
    }

    func reset() {
        generation &+= 1
        continuation = nil
        currentConversationID = nil
    }

    /// Current generation for stale-task guards. Capture it before long work and
    /// pass it back to report* — mismatched generations are dropped.
    func currentGeneration() -> Int { generation }

    func reportCall(name: String, params: String, generation: Int? = nil) {
        if let generation, generation != self.generation { return }
        guard let continuation else { return }
        switch continuation.yield(.toolCall(name: name, params: params)) {
        case .terminated: self.continuation = nil
        case .enqueued, .dropped: break
        @unknown default: break
        }
    }

    func reportResult(name: String, result: Any, generation: Int? = nil) {
        if let generation, generation != self.generation { return }
        guard let continuation else { return }
        let sanitized = sanitize(result, depth: 0, maxLength: 2000)
        let jsonStr: String
        if JSONSerialization.isValidJSONObject(sanitized),
           let data = try? JSONSerialization.data(withJSONObject: sanitized, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            jsonStr = str
        } else {
            jsonStr = String(describing: result)
        }
        if case .terminated = continuation.yield(.toolResult(name: name, result: jsonStr)) {
            self.continuation = nil
        }
    }

    private static let maxDepth = 10

    /// Single-pass sanitize: unwraps optionals, truncates long strings.
    /// Fast-paths String/numbers/dicts without Mirror; Mirror is only used
    /// to detect Optional.
    private nonisolated func sanitize(_ value: Any, depth: Int, maxLength: Int) -> Any {
        if depth > Self.maxDepth { return "…" }
        // Fast paths — no Mirror.
        if let str = value as? String {
            return str.count > maxLength ? String(str.prefix(maxLength)) + "…" : str
        }
        if value is Int || value is Double || value is Float || value is Bool || value is NSNumber {
            return value
        }
        if value is NSNull { return value }
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict { out[k] = sanitize(v, depth: depth + 1, maxLength: maxLength) }
            return out
        }
        if let arr = value as? [Any] {
            return arr.map { sanitize($0, depth: depth + 1, maxLength: maxLength) }
        }
        // Optional only — the single Mirror use.
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let val = mirror.children.first?.value {
                return sanitize(val, depth: depth + 1, maxLength: maxLength)
            }
            return NSNull()
        }
        return String(describing: value)
    }
}
