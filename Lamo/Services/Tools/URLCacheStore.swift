import Foundation

// MARK: - URL Content Cache

/// Simple in-memory cache for fetched URL contents to avoid re-fetching the same URL within a conversation.
final class URLCacheStore {
    static let shared = URLCacheStore()
    private let cache = NSCache<NSString, NSString>()
    private init() {
        cache.countLimit = 50
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }

    func content(for url: String) -> String? {
        cache.object(forKey: url as NSString) as String?
    }

    func setContent(_ content: String, for url: String) {
        cache.setObject(content as NSString, forKey: url as NSString, cost: content.utf8.count)
    }

    func clear() {
        cache.removeAllObjects()
    }
}
