import os
import SwiftUI
import UniformTypeIdentifiers

struct ChatDropDelegate: DropDelegate {
    @Binding var pendingImages: [PendingImage]
    @Binding var pendingFiles: [PendingFile]

    func performDrop(info: DropInfo) -> Bool {
        let imageProviders = info.itemProviders(for: [.image])
        for provider in imageProviders {
            // Тот же лимит, что у фото-пикера, чтобы дроп не раздувал очередь.
            guard pendingImages.count < ChatDropDelegate.maxImages else {
                LamoLogger.ui.error("Drop image ignored: attachment limit reached")
                break
            }
            _ = provider.loadObject(ofClass: UIImage.self) { image, error in
                if let error {
                    LamoLogger.ui.error("Drop image load failed: \(error)")
                    return
                }
                guard let uiImage = image as? UIImage else { return }
                // Ресайз в фоне — UIGraphicsImageRenderer на main подвешивал дроп.
                Task.detached(priority: .userInitiated) {
                    let resized = uiImage.resizedForModel(maxDimension: ChatDropDelegate.maxImageDimension)
                    await MainActor.run {
                        pendingImages.append(PendingImage(image: resized))
                    }
                }
            }
        }

        let fileProviders = info.itemProviders(for: [.fileURL])
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error {
                    LamoLogger.ui.error("Drop file load failed: \(error)")
                    return
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    pendingFiles.append(PendingFile(url: url))
                }
            }
        }

        return !imageProviders.isEmpty || !fileProviders.isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    nonisolated static let maxImageDimension: CGFloat = 1024
    /// Keep drops consistent with the photo picker limit.
    static let maxImages = 5
}
