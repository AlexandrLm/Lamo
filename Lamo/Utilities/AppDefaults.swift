import Foundation

// MARK: - Property Wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    let onSet: ((T) -> Void)?

    init(_ key: String, default defaultValue: T, onSet: ((T) -> Void)? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        self.onSet = onSet
    }

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            onSet?(newValue)
        }
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
    static var systemPrompt = UserDefault("litertLMSystemPrompt", default: "You are a helpful assistant. Answer in the user's language.\n\nCRITICAL RULES:\n1. You do NOT have real-time knowledge. For these topics you MUST call tools — never answer from memory: weather/temperature/forecast → weather tool, current time/date/day → get_current_time, math/calculations → calculator, facts/news/current events → web_search, device questions → get_device_info, location → get_location, reminders/alarms → create_reminder.\n2. For complex multi-step problems, call the think tool to reason step by step before answering.\n3. After a tool returns data, describe it using EXACT values from the result. Never invent numbers or details — the user sees the real data and will notice mismatches.\n4. Keep tool result summaries brief: 1-2 sentences maximum.\n5. If a tool returns an error or \"success\": false, tell the user it failed and what action they need to take. Never claim success on a failed tool call.\n6. Use markdown formatting when appropriate.")

    // Thinking
    static var thinkingMode = UserDefault("litertLMThinkingMode", default: false)

    // Memory
    static var memoryEnabled = UserDefault("memoryEnabled", default: true)

    // Web
    static var webAutoFetch = UserDefault("web_auto_fetch", default: true)

    // MARK: - Tool Toggles (all enabled by default)

    static var toolWebSearch = UserDefault("tool_web_search", default: true)
    static var toolFetchURL = UserDefault("tool_fetch_url", default: true)
    static var toolGetCurrentTime = UserDefault("tool_get_current_time", default: true)
    static var toolCalculator = UserDefault("tool_calculator", default: true)
    static var toolOpenURL = UserDefault("tool_open_url", default: true)
    static var toolWikipedia = UserDefault("tool_wikipedia", default: true)
    static var toolGetLocation = UserDefault("tool_get_location", default: true)
    static var toolDeviceInfo = UserDefault("tool_device_info", default: true)
    static var toolWeather = UserDefault("tool_weather", default: true)
    static var toolThink = UserDefault("tool_think", default: true)
    static var toolCreateReminder = UserDefault("tool_create_reminder", default: true)
}
