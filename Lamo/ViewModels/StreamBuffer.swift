import Foundation

/// Throttled streaming text buffer.
///
/// Accumulates delta and thinking-delta tokens during inference,
/// and releases them in batches at `flushInterval` to avoid
/// per-token SwiftData writes.
///
/// Plain Sendable struct (no @MainActor): the owning ChatViewModel is
/// @MainActor and mutates it synchronously on the main actor, so no
/// isolation is needed here. Keeps the type usable from any context.
struct StreamBuffer: Sendable {
    private var text = ""
    private var thinking = ""
    /// Monotonic clock — cheaper than Date() and immune to wall-clock jumps.
    private var lastFlushUptime: UInt64 = 0

    /// Minimum interval between flushes.
    let flushInterval: TimeInterval

    /// Hard cap — forces a drain even if the throttle interval hasn't elapsed,
    /// bounding memory when tokens arrive faster than flushes.
    static let maxBufferedChars = 8000

    /// Whether there is unconsumed content in the buffer.
    var hasContent: Bool { !text.isEmpty || !thinking.isEmpty }

    init(flushInterval: TimeInterval = 0.15) {
        self.flushInterval = flushInterval
    }

    /// Append streaming deltas to the buffer.
    mutating func append(text delta: String = "", thinking: String = "") {
        if !delta.isEmpty { text += delta }
        if !thinking.isEmpty { self.thinking += thinking }
    }

    /// Drain accumulated text if the throttle interval has elapsed (or `force` is true).
    /// Returns the text and thinking to write, or nil if throttled.
    mutating func drain(force: Bool = false) -> (text: String, thinking: String)? {
        let now = DispatchTime.now().uptimeNanoseconds
        let intervalNanos = UInt64(max(flushInterval, 0) * 1_000_000_000)
        let overLimit = (text.count + thinking.count) >= Self.maxBufferedChars
        guard force || overLimit || now &- lastFlushUptime >= intervalNanos else { return nil }
        guard hasContent else { return nil }

        let result = (text, thinking)
        text = ""
        thinking = ""
        lastFlushUptime = now
        return result
    }

    /// Discard all buffered content without flushing.
    mutating func reset() {
        text = ""
        thinking = ""
        lastFlushUptime = 0
    }
}
