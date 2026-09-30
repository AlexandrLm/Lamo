import Foundation
import os

final class RepetitionDetector: Sendable {
    private let logger = Logger(subsystem: LamoLogger.subsystem, category: "RepDetector")

    private let lock: OSAllocatedUnfairLock<State>

    private let windowSize: Int
    private let minBufferSize: Int
    private let checkFrequency: Int

    private struct State {
        var buffer: String = ""
        var bufferLength: Int = 0
        var totalCharacters: Int = 0
        var tokenCount: Int = 0
    }

    init(windowSize: Int = 2000, minBufferSize: Int = 200, checkFrequency: Int = 5) {
        self.windowSize = max(1, windowSize)
        self.minBufferSize = max(1, minBufferSize)
        self.checkFrequency = max(1, checkFrequency)
        self.lock = OSAllocatedUnfairLock(initialState: State())
    }

    func feed(_ chunk: String) -> Bool {
        let textToInspect: String? = lock.withLock { state in
            state.buffer.append(chunk)
            state.bufferLength += chunk.count
            state.totalCharacters += chunk.count
            state.tokenCount += 1

            if state.bufferLength > windowSize * 3 {
                state.buffer = String(state.buffer.suffix(windowSize * 2))
                state.bufferLength = state.buffer.count
            }

            guard state.bufferLength >= minBufferSize,
                  state.tokenCount.isMultiple(of: checkFrequency) else {
                return nil
            }
            return String(state.buffer.suffix(windowSize))
        }

        guard let textToInspect else { return false }
        return detectLoop(text: textToInspect)
    }

    var totalChars: Int {
        lock.withLock { $0.totalCharacters }
    }

    func reset() {
        lock.withLock { state in
            state.buffer = ""
            state.bufferLength = 0
            state.totalCharacters = 0
            state.tokenCount = 0
        }
    }

    // MARK: - Detection Strategies

    private nonisolated func detectLoop(text: String) -> Bool {
        detectConsecutiveRepeats(text)
            || detectNgramFlood(text)
            || detectLineLoop(text)
    }

    private nonisolated func detectConsecutiveRepeats(_ text: String) -> Bool {
        let textCount = text.count
        for patternLen in 5...80 {
            if patternLen > 16 && patternLen % 5 != 0 { continue }
            guard textCount >= patternLen * 3 else { continue }
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

    private nonisolated func detectNgramFlood(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let wordCount = words.count
        guard wordCount >= 20 else { return false }

        let n = 3
        guard wordCount >= n else { return false }
        var counts: [Int: Int] = [:]
        counts.reserveCapacity(wordCount - n + 1)
        for i in 0...(wordCount - n) {
            var hasher = Hasher()
            hasher.combine(words[i])
            hasher.combine(words[i + 1])
            hasher.combine(words[i + 2])
            counts[hasher.finalize(), default: 0] += 1
        }
        // Threshold: more occurrences than reasonable
        let threshold = max(5, wordCount / (n * 4))
        for (_, count) in counts where count >= threshold {
            logger.warning("N-gram flood: a 3-gram appears \(count) times in \(wordCount) words")
            return true
        }
        return false
    }

    private nonisolated func detectLineLoop(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 6 else { return false }

        let tail = Array(lines.suffix(10))
        for patternLen in 1...5 {
            guard tail.count >= patternLen * 3 else { continue }
            let end = tail.count
            let pattern = Array(tail[(end - patternLen)..<end])
            guard pattern.allSatisfy({ Self.hasContent($0) }) else { continue }

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

    private nonisolated static func hasContent(_ line: String) -> Bool {
        var alnum = 0
        for scalar in line.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                alnum += 1
                if alnum >= 4 { return true }
            }
        }
        return false
    }
}
