import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: UIImage, forKey key: String) {
        let rawCost = Int(image.size.width * image.size.height * image.scale * 4)
        let cost = rawCost > 0 ? min(rawCost, Int.max / 2) : 1
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}
