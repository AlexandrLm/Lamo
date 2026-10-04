import Foundation

struct ToolRoute: Sendable {
    var location = false
    var weather = false
    var calendar = false
    var webSearch = false
    var fetchURL = false

    nonisolated init(
        location: Bool = false,
        weather: Bool = false,
        calendar: Bool = false,
        webSearch: Bool = false,
        fetchURL: Bool = false
    ) {
        self.location = location
        self.weather = weather
        self.calendar = calendar
        self.webSearch = webSearch
        self.fetchURL = fetchURL
    }
}

nonisolated enum ToolRouter {
    private static let weatherMarkers = [
        "погод", "прогноз", "дожд", "снег", "снеж", "температур", "градус",
        "ветер", "ветр", "шторм", "влажност", "зонт", "потепле", "похолода",
        "жара", "мороз", "гололед",
        "weather", "forecast", "rain", "snow", "temperatur", "degree",
        "humidity", "storm", "windy", "umbrella",
    ]
    private static let locationMarkers = [
        "где я", "моё местоположение", "мое местоположение", "мои координаты",
        "моё место", "мое место", "геолокац", "координат",
        "where am i", "my location", "my coordinates", "current location",
        "current position",
    ]
    private static let calendarMarkers = [
        "календар", "встреч", "событи", "напомн", "напомина", "повестк",
        "заплани", "план на", "расписание",
        "meeting", "event", "appointment", "schedule", "reminder", "remind",
    ]
    private static let webMarkers = [
        "http", "www.", ".com", ".ru", ".org", ".net", ".io",
        "новост", "news", "цена", "цены", "стоимость", "сколько стоит",
        "курс", "price", "cost", "latest", "актуальн",
        "кто такой", "кто такая", "что такое", "who is", "what is",
        "найд", "узнай", "сравн", "рейтинг", "обзор",
        "find", "search", "compare", "explain", "guide", "how to", "review", "best ",
    ]
    private static let questionMarkers = [
        "кто", "что", "где", "когда", "почему", "сколько", "какой", "какая",
        "какое", "какие", "чей", "чья",
        "who", "what", "where", "when", "why", "how", "which", "whose", "is it",
    ]

    private static let greetingMarkers = [
        "привет", "здравствуй", "здравствуйте", "добрый день", "доброе утро",
        "добрый вечер", "спасибо", "благодарю", "пожалуйста", "понял",
        "понятно", "хорошо", "пока", "окей",
        "hello", "hey", "thanks", "thank you", "please", "okay",
        "got it", "good", "great", "bye",
    ]
    private static let greetingWords: Set<String> = ["ок", "ok", "hi"]

    static func route(for text: String) -> ToolRoute {
        let q = text.lowercased()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolRoute(location: true, weather: true, calendar: true, webSearch: true, fetchURL: true)
        }
        var location = false
        var weather = false
        var calendar = false
        var webSearch = false
        var fetchURL = false
        if containsAny(q, weatherMarkers) { weather = true }
        if containsAny(q, locationMarkers) { location = true }
        if containsAny(q, calendarMarkers) { calendar = true }
        if containsAny(q, webMarkers) || isQuestion(q) {
            webSearch = true
            fetchURL = true
        }
        let anyMatched = location || weather || calendar || webSearch || fetchURL
        if anyMatched {
            return ToolRoute(location: location, weather: weather, calendar: calendar, webSearch: webSearch, fetchURL: fetchURL)
        }
        if containsAny(q, greetingMarkers) || containsWord(q, greetingWords) {
            return ToolRoute()
        }
        if trimmed.count < 30 {
            return ToolRoute(location: true, weather: true, calendar: true, webSearch: true, fetchURL: true)
        }
        // Fail-safe default: a long message that matched nothing is usually an
        // informational request ("расскажи про квантовые компьютеры..."). Giving
        // the model web tools lets it verify facts instead of hallucinating;
        // the model still decides whether a call is actually needed.
        return ToolRoute(webSearch: true, fetchURL: true)
    }

    private static func isQuestion(_ q: String) -> Bool {
        // A "?" alone is usually a short follow-up ("а завтра?") — the length
        // rule above already routes those to all tools. Wh-words signal an
        // information need even without a question mark ("кто такой Пушкин").
        containsAny(q, questionMarkers)
    }

    private static func containsAny(_ text: String, _ markers: [String]) -> Bool {
        for m in markers {
            if text.contains(m) { return true }
        }
        return false
    }

    private static func containsWord(_ text: String, _ words: Set<String>) -> Bool {
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for t in tokens {
            if words.contains(String(t)) { return true }
        }
        return false
    }
}
