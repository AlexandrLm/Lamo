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
    static var systemPrompt = UserDefault("litertLMSystemPrompt", default: "You are a helpful assistant. Answer in the user's language.\n\nCRITICAL RULES:\n1. You do NOT have real-time knowledge. For these topics you MUST call tools — never answer from memory: weather/temperature/forecast → weather, math/calculations → calculator, facts/news/current events → web_search, location → get_location.\n2. Current date and time are provided in <current_time> — use them directly, no tool needed.\n3. After a tool returns data, describe it using EXACT values from the result. Never invent numbers or details.\n4. Use calendar tool for scheduling and date queries. Use contacts for people lookups.\n5. Be concise. Answer in 2-3 sentences unless the user asks for detail.")


    // Memory
    // Thinking (model-level reasoning, not a tool)
    static var thinkingMode = UserDefault("litertLMThinkingMode", default: false)
    static var memoryEnabled = UserDefault("memoryEnabled", default: true)

    // Web
    static var webAutoFetch = UserDefault("web_auto_fetch", default: true)

    // MARK: - Tool Toggles (all enabled by default)

    static var toolWebSearch = UserDefault("tool_web_search", default: true)
    static var toolFetchURL = UserDefault("tool_fetch_url", default: true)
    static var toolCalculator = UserDefault("tool_calculator", default: true)
    static var toolWikipedia = UserDefault("tool_wikipedia", default: true)
    static var toolGetLocation = UserDefault("tool_get_location", default: true)
    static var toolWeather = UserDefault("tool_weather", default: true)

    // MARK: Agent Tools (new)
    static var toolCalendar = UserDefault("tool_calendar", default: true)
    static var toolContacts = UserDefault("tool_contacts", default: true)
    static var toolShortcuts = UserDefault("tool_shortcuts", default: true)
    static var toolHealth = UserDefault("tool_health", default: true)
}
