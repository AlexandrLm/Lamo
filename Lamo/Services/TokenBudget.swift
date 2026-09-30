import Foundation
import LiteRTLM
import os

/// Token budget calculation and tokenization with caching.
///
/// All mutable state lives inside lock-protected value types, so the class is
/// safe to use from any actor; it is explicitly `nonisolated` to keep the
/// tokenizer off the main actor.
nonisolated final class TokenBudget {
    /// Tokenization cache — avoids re-tokenizing unchanged messages.
    /// Key: (hashValue, count) pair instead of the full string, so the cache
    /// doesn't retain every message body. Bounded at 500 entries (FIFO evict).
    /// State is held inside OSAllocatedUnfairLock for async-safe access.
    nonisolated private struct CacheKey: Hashable {
        let hash: Int
        let count: Int
    }
    nonisolated private struct CacheState {
        var values: [CacheKey: Int] = [:]
        var order: [CacheKey] = []
    }
    nonisolated private static let maxCacheEntries = 500
    private let tokenCacheLock = OSAllocatedUnfairLock(initialState: CacheState())

    nonisolated private static func cacheKey(for text: String) -> CacheKey {
        CacheKey(hash: text.hashValue, count: text.count)
    }

    private func cachedCount(for text: String) -> Int? {
        let key = Self.cacheKey(for: text)
        return tokenCacheLock.withLock { $0.values[key] }
    }

    private func storeCount(_ count: Int, for text: String) {
        let key = Self.cacheKey(for: text)
        tokenCacheLock.withLock { state in
            if state.values[key] == nil {
                state.order.append(key)
                if state.order.count > Self.maxCacheEntries {
                    let evicted = state.order.removeFirst()
                    state.values.removeValue(forKey: evicted)
                }
            }
            state.values[key] = count
        }
    }

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
        let result = max(512, (capped / 256) * 256)
        // Assemble first, then log: OSLogMessage requires a literal at the call site.
        let kvText = String(format: "%.0f", kvMBPer1K)
        let availableText = String(format: "%.0f", availableMB)
        let usableText = String(format: "%.0f", usableMB)
        let detail = [
            "kv=\(kvText)MB/1K",
            "available=\(availableText)MB",
            "safety=\(Int(safetyFactor * 100))%",
            "usable=\(usableText)MB",
            "maxFromMem=\(maxTokensFromMemory)",
            "requested=\(requested)",
            "result=\(result)",
        ].joined(separator: ", ")
        LamoLogger.engine.debug("safeMaxTokens: \(detail)")
        return result
    }

    /// Tokenize a string using the engine's real tokenizer.
    /// Uses tokenization cache to avoid re-tokenizing identical strings.
    func tokenizeCount(_ text: String, engine: LiteRTLM.Engine?) async -> Int {
        if let cached = cachedCount(for: text) { return cached }

        guard let engine = engine else { return TokenEstimation.estimateTokens(of: text) }
        let count = (try? await engine.tokenCount(text)) ?? TokenEstimation.estimateTokens(of: text)

        storeCount(count, for: text)

        return count
    }

    /// Tokenize all messages and return per-message token counts.
    /// Uses cached token counts for unchanged messages.
    /// Attached file text counts too — ConversationBuilder sends it as a
    /// separate message, so ignoring it would under-report messages with PDFs.
    func tokenizeMessages(_ messages: [ChatMessage], engine: LiteRTLM.Engine?) async -> [UUID: Int] {
        // Matches the exact prefix ConversationBuilder injects for file content.
        func fileText(for msg: ChatMessage) -> String {
            msg.fileContent.isEmpty ? "" : "Content of attached files:\n\n\(msg.fileContent)"
        }
        func fallback(_ s: String) -> Int { TokenEstimation.estimateTokens(of: s) }

        guard engine != nil else {
            var counts: [UUID: Int] = [:]
            for msg in messages { counts[msg.id] = fallback(msg.content) + (msg.fileContent.isEmpty ? 0 : fallback(fileText(for: msg))) }
            return counts
        }

        // Parallel tokenization across messages — engine calls dominate latency.
        // File texts are precomputed so task closures only capture Sendable strings.
        let jobs = messages.map { msg in
            (id: msg.id, content: msg.content,
             file: msg.fileContent.isEmpty ? nil as String? : "Content of attached files:\n\n\(msg.fileContent)")
        }
        return await withTaskGroup(of: (UUID, Int).self, returning: [UUID: Int].self) { group in
            for job in jobs {
                group.addTask { [engine] in
                    let content = await self.tokenizeCount(job.content, engine: engine)
                    let files = await self.filePartCount(job.file, engine: engine)
                    return (job.id, content + files)
                }
            }
            var counts: [UUID: Int] = [:]
            counts.reserveCapacity(messages.count)
            for await (id, count) in group { counts[id] = count }
            return counts
        }
    }

    /// File-part token count helper so `withTaskGroup` closures capture only
    /// Sendable values (no local-function captures).
    private func filePartCount(_ file: String?, engine: LiteRTLM.Engine?) async -> Int {
        guard let file else { return 0 }
        return await tokenizeCount(file, engine: engine)
    }

    /// Clear tokenization cache (e.g., when engine changes).
    func clearTokenCache() {
        tokenCacheLock.withLock { $0 = CacheState() }
    }
}
