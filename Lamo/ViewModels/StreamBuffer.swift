import Foundation

/// Throttled streaming text buffer.
///
/// Accumulates delta and thinking-delta tokens during inference,
/// and releases them in batches at `flushInterval` to avoid
/// per-token SwiftData writes.
@MainActor
final class StreamBuffer {
    private var text = ""
    private var thinking = ""
    private var lastFlushTime = Date.distantPast

    /// Minimum interval between flushes.
    let flushInterval: TimeInterval

    /// Whether there is unconsumed content in the buffer.
    var hasContent: Bool { !text.isEmpty || !thinking.isEmpty }

    init(flushInterval: TimeInterval = 0.15) {
        self.flushInterval = flushInterval
    }

    /// Append streaming deltas to the buffer.
    func append(text delta: String = "", thinking: String = "") {
        if !delta.isEmpty { text += delta }
        if !thinking.isEmpty { self.thinking += thinking }
    }

    /// Drain accumulated text if the throttle interval has elapsed (or `force` is true).
    /// Returns the text and thinking to write, or nil if throttled.
    func drain(force: Bool = false) -> (text: String, thinking: String)? {
        let now = Date()
        guard force || now.timeIntervalSince(lastFlushTime) >= flushInterval else { return nil }
        guard hasContent else { return nil }

        let result = (text, thinking)
        text = ""
        thinking = ""
        lastFlushTime = now
        return result
    }

    /// Discard all buffered content without flushing.
    func reset() {
        text = ""
        thinking = ""
        lastFlushTime = .distantPast
    }
}
