import Foundation

// MARK: - Property Wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    init(_ key: String, default defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get {
            // Typed read for Bool: `object(forKey:) as? Bool` misbehaves for
            // values bridged as NSNumber, so use `bool(forKey:)` when the key
            // exists and fall back to the default otherwise.
            if T.self == Bool.self {
                guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
                return UserDefaults.standard.bool(forKey: key) as! T
            }
            return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// Specialization for String? since object(forKey:) returns nil for unset
@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String
    var wrappedValue: T? {
        get { UserDefaults.standard.object(forKey: key) as? T }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Centralized Defaults

enum AppDefaults {
    // Provider
    static var providerType = UserDefault("providerType", default: "LiteRT-LM")

    // Model
    static var modelPath = OptionalUserDefault<String>(key: "litertLMModelPath")

    // Compute
    static var useGPU = UserDefault("litertLMUseGPU", default: true)
    static var cpuThreadCount = UserDefault("litertLMCpuThreadCount", default: 4)

    // Sampler
    static var topK = UserDefault("litertLMTopK", default: 64)
    static var topP = UserDefault("litertLMTopP", default: 0.95)
    static var temperature = UserDefault("litertLMTemperature", default: 1.0)

    // KV-Cache
    static var maxNumTokens = UserDefault("litertLMMaxNumTokens", default: 4096)
    static var kvCacheAuto = UserDefault("litertLMKvCacheAuto", default: true)

    // Performance
    static var speculativeDecoding = UserDefault("litertLMSpeculativeDecoding", default: true)

    // Vision
    static var visualTokenBudget = UserDefault("litertLMVisualTokenBudget", default: 560)

    // Prompt
    /// Canonical default system prompt — the single source of truth
    /// (ModelSettings.defaultSystemPrompt delegates here).
    static var systemPrompt = UserDefault("litertLMSystemPrompt", default: """
        You are a helpful personal AI assistant running fully on the user's device. Answer in the user's language.

        TOOLS — for real-time or on-device data you MUST call tools; never answer such questions from memory:
        - weather/forecast → weather (it detects the location itself — no get_location call needed)
        - "where am I" / current position → get_location
        - events, schedule, "what's on my calendar" → calendar
        - current facts, news, prices → web_search (short keyword query), then fetch_url to read a page in full
        - remember facts about the user → update_memory

        CRITICAL — NEVER simulate tools:
        - You MUST actually call the tool and wait for its real result. Never output fake JSON or invented data.
        - Use EXACT values from tool results — never round, estimate, or invent numbers.
        - Current date and time are in <current_time> — use them directly, no tool needed. Resolve relative dates ("tomorrow", "next Monday") against them.
        - If a tool returns an error, follow its "hint": fix the arguments and retry once, or explain the problem to the user.
        - If a tool you need is not available (e.g. offline), say so instead of fabricating an answer.
        - Don't call a tool when the answer is already in the conversation or in <memory>.

        ANSWERS:
        - Be concise: direct answer first; details only when asked.
        - Use markdown formatting. When you used web_search or fetch_url, cite sources as links.
        """)


    // Memory
    // Thinking (model-level reasoning, not a tool)
    static var thinkingMode = UserDefault("litertLMThinkingMode", default: false)
    static var memoryEnabled = UserDefault("memoryEnabled", default: true)

    // Web
    static var webAutoFetch = UserDefault("web_auto_fetch", default: true)

    // MARK: - Summarization
    /// KV-cache fill ratio that triggers automatic compression (0.0–1.0, default 0.6 = 60%)
    static var compressionThreshold = UserDefault("compressionThreshold", default: 0.6)

    // MARK: - Tool Toggles (all enabled by default)

    static var toolWebSearch = UserDefault("tool_web_search", default: true)
    static var toolFetchURL = UserDefault("tool_fetch_url", default: true)
    static var toolGetLocation = UserDefault("tool_get_location", default: true)
    static var toolWeather = UserDefault("tool_weather", default: true)

    static var toolCalendar = UserDefault("tool_calendar", default: true)

    /// Reset all defaults to their factory values.
    static func resetAll() {
        modelPath.wrappedValue = nil
        useGPU.wrappedValue = true
        cpuThreadCount.wrappedValue = 4
        topK.wrappedValue = 64
        topP.wrappedValue = 0.95
        temperature.wrappedValue = 1.0
        maxNumTokens.wrappedValue = 4096
        kvCacheAuto.wrappedValue = true
        speculativeDecoding.wrappedValue = true
        visualTokenBudget.wrappedValue = 560
        systemPrompt.wrappedValue = systemPrompt.defaultValue
        thinkingMode.wrappedValue = false
        memoryEnabled.wrappedValue = true
        webAutoFetch.wrappedValue = true
        compressionThreshold.wrappedValue = compressionThreshold.defaultValue
        toolWebSearch.wrappedValue = true
        toolFetchURL.wrappedValue = true
        toolGetLocation.wrappedValue = true
        toolWeather.wrappedValue = true
        toolCalendar.wrappedValue = true
        providerType.wrappedValue = "LiteRT-LM"
    }
}
