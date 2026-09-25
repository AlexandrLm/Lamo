import Foundation

// MARK: - Shared String + URL formatting (single owner)

// One home for page-content cleanup + URL shortening previously triplicated
// across FetchToolBlock / SearchToolBlock / ToolCallBlock.
enum TextFormat {
    /// Collapse excessive whitespace/blank lines in fetched page content.
    static func cleanedPageContent(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 || $0.isEmpty }
        var result = cleaned.joined(separator: "\n")
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Host without `www.` ("" when unparseable).
    static func domainHost(from urlString: String, fallback: String = "") -> String {
        guard let url = URL(string: urlString), let host = url.host else { return fallback }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// `https://www.example.com/a/b` → `example.com`.
    static func shortURL(_ urlString: String) -> String {
        urlString.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/").first ?? urlString
    }
}

extension String {
    /// Cleaned page content (see `TextFormat.cleanedPageContent`).
    var cleanedPageContent: String { TextFormat.cleanedPageContent(self) }
    /// Short host form (see `TextFormat.shortURL`).
    var shortURLString: String { TextFormat.shortURL(self) }
    /// Domain host without `www.`.
    var domainHost: String { TextFormat.domainHost(from: self) }
}
