import UIKit

extension UIImage {
    /// Resizes the image so its longest side does not exceed `maxDimension`.
    /// Returns `self` if already within bounds (no upscaling).
    func resizedForModel(maxDimension: CGFloat) -> UIImage {
        guard maxDimension > 0 else { return self }
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard newSize.width > 0, newSize.height > 0 else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// Background variant — same resize, off the main thread.
    func resizedForModelAsync(maxDimension: CGFloat) async -> UIImage {
        await Task.detached(priority: .utility) { self.resizedForModel(maxDimension: maxDimension) }.value
    }
}
