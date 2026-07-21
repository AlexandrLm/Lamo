import Foundation
import LiteRTLM
import os

/// Token budget calculation and tokenization with caching.
@MainActor
final class TokenBudget {
    /// Tokenization cache — avoids re-tokenizing unchanged messages.
    /// Key: message content (String), Value: token count.
    /// State is held inside OSAllocatedUnfairLock for async-safe access.
    private let tokenCacheLock = OSAllocatedUnfairLock(initialState: [String: Int]())

    /// Calculate a safe maximum token count based on available memory,
    /// model size on disk, and user settings.
    func safeMaxTokens(
        modelPath: String,
        useGPU: Bool,
        kvCacheAuto: Bool,
        maxNumTokens: Int
    ) -> Int? {
        let availableBytes: UInt64
        #if os(iOS)
        availableBytes = UInt64(os_proc_available_memory())
        #else
        availableBytes = ProcessInfo.processInfo.physicalMemory / 2
        #endif

        let availableMB = Double(availableBytes) / (1024 * 1024)

        // Detect model size to estimate KV-cache memory per token
        let kvMBPer1K: Double
        if let fileAttrs = try? FileManager.default.attributesOfItem(atPath: modelPath),
           let fileSize = fileAttrs[.size] as? Int64 {
            let fileSizeGB = Double(fileSize) / 1_073_741_824
            if useGPU {
                // GPU: model weights loaded into GPU memory, KV-cache extra
                // E2B (2.6GB): ~280 MB/1K, E4B (3.7GB): ~600 MB/1K
                kvMBPer1K = fileSizeGB < 3.0 ? 280.0 : 600.0
            } else {
                // CPU: model heavily memory-mapped, more room for KV-cache
                kvMBPer1K = 150.0
            }
        } else {
            // Fallback: conservative GPU estimate
            kvMBPer1K = useGPU ? 500.0 : 200.0
        }

        let safetyFactor: Double
        if availableMB < 1500 {
            safetyFactor = 0.25
        } else if availableMB < 3000 {
            safetyFactor = 0.35
        } else if availableMB < 5000 {
            safetyFactor = 0.45
        } else {
            safetyFactor = 0.55
        }

        let usableMB = availableMB * safetyFactor
        let maxTokensFromMemory = max(512, Int(usableMB / kvMBPer1K * 1024))

        let requested: Int
        if kvCacheAuto {
            requested = maxTokensFromMemory
        } else {
            requested = maxNumTokens > 0 ? maxNumTokens : 1024
        }

        let capped = min(requested, maxTokensFromMemory)
        let result = (capped / 256) * 256
        LamoLogger.engine.debug("safeMaxTokens: kv=\(String(format: "%.0f", kvMBPer1K))MB/1K, available=\(String(format: "%.0f", availableMB))MB, safety=\(Int(safetyFactor*100))%, usable=\(String(format: "%.0f", usableMB))MB, maxFromMem=\(maxTokensFromMemory), requested=\(requested), result=\(result)")
        return result
    }

    /// Tokenize a string using the engine's real tokenizer.
    /// Uses tokenization cache to avoid re-tokenizing identical strings.
    func tokenizeCount(_ text: String, engine: LiteRTLM.Engine?) async -> Int {
        let cached = tokenCacheLock.withLock { $0[text] }
        if let cached { return cached }

        guard let engine = engine else { return text.count / 4 }
        let count = (try? await engine.tokenize(text))?.count ?? (text.count / 4)

        tokenCacheLock.withLock { $0[text] = count }

        return count
    }

    /// Tokenize all messages and return per-message token counts.
    /// Uses cached token counts for unchanged messages.
    func tokenizeMessages(_ messages: [ChatMessage], engine: LiteRTLM.Engine?) async -> [UUID: Int] {
        guard let engine = engine else {
            var fallback: [UUID: Int] = [:]
            for msg in messages { fallback[msg.id] = msg.content.count / 4 }
            return fallback
        }

        var counts: [UUID: Int] = [:]
        for msg in messages {
            let cached = tokenCacheLock.withLock { $0[msg.content] }
            if let cached {
                counts[msg.id] = cached
                continue
            }

            if let tokens = try? await engine.tokenize(msg.content) {
                let count = tokens.count
                counts[msg.id] = count
                tokenCacheLock.withLock { $0[msg.content] = count }
            } else {
                counts[msg.id] = msg.content.count / 4
            }
        }
        return counts
    }

    /// Clear tokenization cache (e.g., when engine changes).
    func clearTokenCache() {
        tokenCacheLock.withLock { $0.removeAll() }
    }
}
