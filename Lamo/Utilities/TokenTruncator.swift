import Foundation

// MARK: - Token-Aware Truncation

/// Truncates tool results to a target token count.
///
/// Two phases:
/// 1. **Per-string cap** — any single string field longer than the char budget is cut
///    (protects against one huge blob, e.g. a fetched page).
/// 2. **Aggregate fit** — if the *whole serialized result* still exceeds the budget,
///    the largest arrays are halved (with an omission marker) and the longest strings
///    shortened, round by round. This catches the "300 tiny calendar events" case,
///    where every field is short but the total blows the context.
///
/// Falls back to chars×4 approximation — no tokenizer is available at this layer.
enum TokenTruncator {

    /// Hard cap on reduction rounds — guarantees termination.
    private static let maxRounds = 10
    /// Never shrink a string below this in aggregate reduction.
    private static let minStringChars = 400
    /// Never shrink an array below this in aggregate reduction.
    private static let minArrayItems = 3

    static func truncateResult(_ value: Any, maxTokens: Int) async -> Any {
        let charBudget = max(400, maxTokens * 4)
        // Phase 1: cap oversized individual strings.
        let capped = capStrings(value, maxChars: charBudget, tokenLabel: maxTokens)
        // Phase 2: fit the aggregate within the budget.
        return fitToBudget(capped, charBudget: charBudget)
    }

    // MARK: - Phase 1: per-string cap

    private static func capStrings(_ value: Any, maxChars: Int, tokenLabel: Int) -> Any {
        if let str = value as? String {
            guard str.count > maxChars else { return str }
            return String(str.prefix(maxChars)) + "\n\n[Truncated to \(tokenLabel) tokens]"
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            result.reserveCapacity(dict.count)
            for (k, v) in dict {
                result[k] = capStrings(v, maxChars: maxChars, tokenLabel: tokenLabel)
            }
            return result
        }
        if let arr = value as? [Any] {
            return arr.map { capStrings($0, maxChars: maxChars, tokenLabel: tokenLabel) }
        }
        return value
    }

    // MARK: - Phase 2: aggregate fit

    private static func fitToBudget(_ value: Any, charBudget: Int) -> Any {
        var result = value
        var rounds = 0
        while serializedSize(result) > charBudget, rounds < maxRounds {
            rounds += 1
            guard let reduced = reduceOnce(result) else { break }
            result = reduced
        }
        // Last resort: hard-truncate the serialized form.
        if serializedSize(result) > charBudget, let serialized = serialize(result) {
            return String(serialized.prefix(charBudget)) + "\n\n[Truncated to fit token budget]"
        }
        return result
    }

    /// One reduction round: halve the largest array (count > min), else shorten the
    /// longest string. Returns nil when nothing can shrink further.
    private static func reduceOnce(_ value: Any) -> Any? {
        var largestArray: (path: [PathComponent], count: Int) = ([], 0)
        var longestString: (path: [PathComponent], length: Int) = ([], 0)
        collectMetrics(value, path: [], largestArray: &largestArray, longestString: &longestString)

        if largestArray.count > minArrayItems {
            return update(value, at: largestArray.path) { node in
                guard let arr = node as? [Any] else { return node }
                let keep = max(minArrayItems, arr.count / 2)
                return Array(arr.prefix(keep))
                    + ["… \(arr.count - keep) more item(s) omitted to fit the token budget …"]
            }
        }
        if longestString.length > minStringChars {
            return update(value, at: longestString.path) { node in
                guard let str = node as? String else { return node }
                return String(str.prefix(longestString.length / 2)) + "\n[Truncated to fit token budget]"
            }
        }
        return nil
    }

    // MARK: - Structure walking

    private enum PathComponent {
        case key(String)
        case index(Int)
    }

    /// DFS recording the largest array and longest string with their paths.
    private static func collectMetrics(
        _ value: Any,
        path: [PathComponent],
        largestArray: inout (path: [PathComponent], count: Int),
        longestString: inout (path: [PathComponent], length: Int)
    ) {
        if let arr = value as? [Any] {
            if arr.count > largestArray.count {
                largestArray = (path, arr.count)
            }
            for (i, item) in arr.enumerated() {
                collectMetrics(item, path: path + [.index(i)], largestArray: &largestArray, longestString: &longestString)
            }
            return
        }
        if let dict = value as? [String: Any] {
            for (k, v) in dict {
                collectMetrics(v, path: path + [.key(k)], largestArray: &largestArray, longestString: &longestString)
            }
            return
        }
        if let str = value as? String, str.count > longestString.length {
            longestString = (path, str.count)
        }
    }

    /// Returns a copy of `value` with the node at `path` replaced via `transform`.
    /// An empty path transforms the root itself.
    private static func update(_ value: Any, at path: [PathComponent], transform: (Any) -> Any) -> Any {
        guard let head = path.first else { return transform(value) }
        let rest = Array(path.dropFirst())
        switch head {
        case .key(let key):
            guard var dict = value as? [String: Any], let child = dict[key] else { return value }
            dict[key] = update(child, at: rest, transform: transform)
            return dict
        case .index(let i):
            guard var arr = value as? [Any], i < arr.count else { return value }
            arr[i] = update(arr[i], at: rest, transform: transform)
            return arr
        }
    }

    // MARK: - Size measurement

    private static func serialize(_ value: Any) -> String? {
        if let str = value as? String { return str }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func serializedSize(_ value: Any) -> Int {
        serialize(value)?.count ?? String(describing: value).count
    }
}
