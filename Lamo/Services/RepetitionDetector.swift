import Foundation
import os

/// Detects when the model gets stuck in a generation loop.
/// Monitors streamed text for repeating patterns and triggers a stop.
final class RepetitionDetector: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.lamo", category: "RepDetector")

    /// Collected output text so far.
    private var buffer: String = ""
    /// How many tokens/chars to keep in the sliding window.
    private let windowSize: Int
    /// Minimum buffer size before detection kicks in (avoid false positives on short output).
    private let minBufferSize: Int

    init(windowSize: Int = 2000, minBufferSize: Int = 200) {
        self.windowSize = windowSize
        self.minBufferSize = minBufferSize
    }

    /// Feed a new chunk of text. Returns `true` if repetition detected.
    func feed(_ chunk: String) -> Bool {
        buffer.append(chunk)
        // Keep buffer bounded
        if buffer.count > windowSize * 3 {
            buffer = String(buffer.suffix(windowSize * 2))
        }
        guard buffer.count >= minBufferSize else { return false }

        return detectLoop()
    }

    // MARK: - Detection Strategies

    private func detectLoop() -> Bool {
        let text = String(buffer.suffix(windowSize))
        return detectConsecutiveRepeats(text)
            || detectNgramFlood(text)
            || detectLineLoop(text)
    }

    /// Same substring repeated 3+ times consecutively.
    /// e.g. "abc abc abc abc" or "!!!  !!!  !!!  !!!"
    private func detectConsecutiveRepeats(_ text: String) -> Bool {
        // Check for repeating patterns of various lengths
        for patternLen in stride(from: 5, through: 80, by: 5) {
            guard text.count >= patternLen * 3 else { continue }
            let end = text.endIndex
            let p1Start = text.index(end, offsetBy: -patternLen)
            let pattern = String(text[p1Start..<end])

            // Count consecutive occurrences from the end
            var count = 1
            var pos = p1Start
            let minIndex = text.index(text.startIndex, offsetBy: patternLen)
            while pos >= minIndex {
                let prevStart = text.index(pos, offsetBy: -patternLen)
                let prev = String(text[prevStart..<pos])
                if prev == pattern {
                    count += 1
                    pos = prevStart
                } else {
                    break
                }
            }
            if count >= 3 {
                logger.warning("Repetition detected: pattern '\(pattern.prefix(30))...' repeated \(count) times")
                return true
            }
        }
        return false
    }

    /// Same short phrase appearing too many times in the window.
    /// e.g. "click the button" appearing 8+ times in 2000 chars
    private func detectNgramFlood(_ text: String) -> Bool {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 20 else { return false }

        // Check 3-grams and 4-grams
        for n in [3, 4, 5] {
            guard words.count >= n else { continue }
            var counts: [String: Int] = [:]
            for i in 0...(words.count - n) {
                let ngram = words[i..<i+n].joined(separator: " ")
                counts[ngram, default: 0] += 1
            }
            // Threshold: more occurrences than reasonable
            let threshold = max(5, words.count / (n * 4))
            for (ngram, count) in counts where count >= threshold {
                logger.warning("N-gram flood: '\(ngram.prefix(40))...' appears \(count) times in \(words.count) words")
                return true
            }
        }
        return false
    }

    /// Same line repeated 3+ times (common with code/list generation loops).
    private func detectLineLoop(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 6 else { return false }

        // Check last N lines for repetition
        let tail = Array(lines.suffix(10))
        for patternLen in 1...5 {
            guard tail.count >= patternLen * 3 else { continue }
            let end = tail.count
            let pattern = Array(tail[(end - patternLen)..<end])

            var count = 1
            var pos = end - patternLen
            while pos >= patternLen {
                let prev = Array(tail[(pos - patternLen)..<pos])
                if prev == pattern {
                    count += 1
                    pos -= patternLen
                } else {
                    break
                }
            }
            if count >= 3 {
                logger.warning("Line loop: last \(patternLen) lines repeated \(count) times")
                return true
            }
        }
        return false
    }

    /// Total chars generated so far.
    var totalChars: Int { buffer.count }

    /// Reset for a new generation.
    func reset() {
        buffer = ""
    }
}
