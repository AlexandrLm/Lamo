import UIKit

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: Self.cost(for: image))
    }

    /// Async variant: deduplicates decode off the main thread.
    func image(forKey key: String, load: @Sendable @escaping () async -> UIImage?) async -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let loaded = await load() else { return nil }
        // Decode in background so the first display doesn't hitch.
        let decoded = await Task.detached(priority: .utility) {
            Self.decodedImage(loaded)
        }.value
        let final = decoded ?? loaded
        cache.setObject(final, forKey: key as NSString, cost: Self.cost(for: final))
        return final
    }

    func clear() {
        cache.removeAllObjects()
    }

    // MARK: - Helpers

    private static func cost(for image: UIImage) -> Int {
        if let cg = image.cgImage {
            let bytes = cg.bytesPerRow * cg.height
            if bytes > 0 { return min(bytes, Int.max / 2) }
        }
        let rawCost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        return rawCost > 0 ? min(rawCost, Int.max / 2) : 1
    }

    /// Forces decode into a bitmap context so drawing later is cheap.
    nonisolated private static func decodedImage(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }
}
