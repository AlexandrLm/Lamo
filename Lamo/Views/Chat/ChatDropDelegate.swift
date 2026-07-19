import os
import SwiftUI
import UniformTypeIdentifiers

struct ChatDropDelegate: DropDelegate {
    @Binding var pendingImages: [PendingImage]
    @Binding var pendingFiles: [PendingFile]

    func performDrop(info: DropInfo) -> Bool {
        let imageProviders = info.itemProviders(for: [.image])
        for provider in imageProviders {
            _ = provider.loadObject(ofClass: UIImage.self) { image, error in
                if let error {
                    LamoLogger.ui.error("Drop image load failed: \(error)")
                    return
                }
                guard let uiImage = image as? UIImage else { return }
                DispatchQueue.main.async {
                    pendingImages.append(
                        PendingImage(image: uiImage.resizedForModel(maxDimension: ChatDropDelegate.maxImageDimension))
                    )
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

    static let maxImageDimension: CGFloat = 1024
}
