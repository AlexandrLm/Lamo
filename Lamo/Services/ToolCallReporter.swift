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

    func reportResult(name: String, result: Any) {
        let jsonStr: String
        let cleaned = stripOptionals(result)
        // Limit individual string values to keep JSON parseable
        let trimmed = trimStringValues(cleaned, maxLength: 2000)
        if let data = try? JSONSerialization.data(withJSONObject: trimmed, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            jsonStr = str
        } else {
            jsonStr = String(describing: result)
        }
        continuation?.yield(.toolResult(name: name, result: jsonStr))
    }

    /// Recursively truncates string values longer than maxLength.
    private nonisolated func trimStringValues(_ value: Any, maxLength: Int) -> Any {
        if let str = value as? String, str.count > maxLength {
            return String(str.prefix(maxLength)) + "…"
        }
        if var dict = value as? [String: Any] {
            for (k, v) in dict { dict[k] = trimStringValues(v, maxLength: maxLength) }
            return dict
        }
        if let arr = value as? [Any] {
            return arr.map { trimStringValues($0, maxLength: maxLength) }
        }
        return value
    }

    /// Recursively replaces Optional values with their unwrapped value or NSNull.
    private nonisolated func stripOptionals(_ value: Any) -> Any {
        // Check if it's an Optional
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let val = mirror.children.first?.value {
                return stripOptionals(val)
            }
            return NSNull()
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { stripOptionals($0) }
        }
        if let arr = value as? [Any] {
            return arr.map { stripOptionals($0) }
        }
        return value
    }
}
