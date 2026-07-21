import Foundation

/// Pure data holder for all LiteRT-LM settings backed by AppDefaults.
/// No side effects — invalidation and validation are handled by ProviderManager.
@MainActor
final class ModelSettings {
    var litertLMModelPath: String? {
        get { AppDefaults.modelPath.wrappedValue }
        set { AppDefaults.modelPath.wrappedValue = newValue }
    }

    var litertLMUseGPU: Bool {
        get { AppDefaults.useGPU.wrappedValue }
        set { AppDefaults.useGPU.wrappedValue = newValue }
    }

    var cpuThreadCount: Int {
        get { AppDefaults.cpuThreadCount.wrappedValue }
        set { AppDefaults.cpuThreadCount.wrappedValue = newValue }
    }

    var topK: Int {
        get { AppDefaults.topK.wrappedValue }
        set { AppDefaults.topK.wrappedValue = newValue }
    }

    var topP: Double {
        get { AppDefaults.topP.wrappedValue }
        set { AppDefaults.topP.wrappedValue = newValue }
    }

    var temperature: Double {
        get { AppDefaults.temperature.wrappedValue }
        set { AppDefaults.temperature.wrappedValue = newValue }
    }

    var maxNumTokens: Int {
        get { AppDefaults.maxNumTokens.wrappedValue }
        set { AppDefaults.maxNumTokens.wrappedValue = newValue }
    }

    var kvCacheAuto: Bool {
        get { AppDefaults.kvCacheAuto.wrappedValue }
        set { AppDefaults.kvCacheAuto.wrappedValue = newValue }
    }

    var speculativeDecoding: Bool {
        get { AppDefaults.speculativeDecoding.wrappedValue }
        set { AppDefaults.speculativeDecoding.wrappedValue = newValue }
    }

    var visualTokenBudget: Int {
        get { AppDefaults.visualTokenBudget.wrappedValue }
        set { AppDefaults.visualTokenBudget.wrappedValue = newValue }
    }

    var systemPrompt: String {
        get { AppDefaults.systemPrompt.wrappedValue }
        set { AppDefaults.systemPrompt.wrappedValue = newValue }
    }

    var thinkingMode: Bool {
        get { AppDefaults.thinkingMode.wrappedValue }
        set { AppDefaults.thinkingMode.wrappedValue = newValue }
    }

    /// Compact system prompt — tool details are in their schemas, not here.
    var defaultSystemPrompt: String {
        """
        You are a helpful personal AI assistant. Answer in the user's language.

        You have tools for real-time data, device sensors, and knowledge. Call them when needed.

        CRITICAL — NEVER simulate tools:
        - You MUST actually call the tool and wait for its real result.
        - NEVER output fake JSON or pretend you received data. If you don't call the tool,
          you have NO data — say "I need to check" and call it.
        - If a tool returns an error, report it. Do NOT invent numbers.
        - Health, calendar, contacts — ALL return real on-device data. You CANNOT guess it.

        RULES:
        1. Use EXACT values from actual tool results. Never invent, round, or estimate.
        2. Keep summaries brief (1-2 sentences).
        3. If a tool fails, tell the user and suggest a fix.
        4. Use markdown for formatting.
        """
    }
}
