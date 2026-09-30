import os
import Foundation
import UIKit
import UniformTypeIdentifiers

nonisolated enum AttachmentProcessor {

    // MARK: - Attachments Directory

    static let attachmentsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    struct Processed: Sendable {
        var imagePaths: [String] = []
        var filePaths: [String] = []
        var fileNames: [String] = []
        var fileSizes: [String] = []
        var textParts: [String] = []

        mutating func merge(_ other: Processed) {
            imagePaths.append(contentsOf: other.imagePaths)
            filePaths.append(contentsOf: other.filePaths)
            fileNames.append(contentsOf: other.fileNames)
            fileSizes.append(contentsOf: other.fileSizes)
            textParts.append(contentsOf: other.textParts)
        }
    }

    private struct ImageBox: @unchecked Sendable {
        let images: [UIImage]
        init(_ images: [UIImage]) { self.images = images }
    }

    // MARK: - Public API

    static func process(
        images: [UIImage],
        files: [PendingFile]
    ) async -> (imagePaths: [String], filePaths: [String], fileNames: [String], fileSizes: [String], extractedText: String) {
        let box = ImageBox(images)
        let result = await Task.detached(priority: .userInitiated) { () -> Processed in
            var accumulated = Processed()
            accumulated.imagePaths = saveImages(box.images)
            for file in files {
                accumulated.merge(await processFile(file))
            }
            return accumulated
        }.value

        return (
            result.imagePaths,
            result.filePaths,
            result.fileNames,
            result.fileSizes,
            result.textParts.joined(separator: "\n\n")
        )
    }

    // MARK: - Per-File Processing

    private static func processFile(_ file: PendingFile) async -> Processed {
        let accessing = file.url.startAccessingSecurityScopedResource()
        defer { if accessing { file.url.stopAccessingSecurityScopedResource() } }

        var out = Processed()
        let name = file.name
        let size = file.formattedSize

        if file.isImage {
            guard file.size <= FileContentExtractor.maxFileBytes,
                  let data = try? Data(contentsOf: file.url, options: .mappedIfSafe),
                  let image = UIImage(data: data) else { return out }
            out.imagePaths = saveImages([image])
        } else if file.isAudio {
            guard let copy = copyToAttachments(file.url, prefix: "audio") else { return out }
            out.filePaths = [copy.path]
            out.fileNames = [name]
            out.fileSizes = [size]
            out.textParts = [String(localized: "[Audio/video file: \(name) — model cannot hear audio, do not invent contents; ask user for transcript if needed]")]
        } else if file.type.conforms(to: .pdf) {
            if FileContentExtractor.pdfHasTextLayer(file.url) {
                do {
                    let extracted = try await FileContentExtractor.extract(from: file.url)
                    out.textParts = [extracted]
                    if let copy = copyToAttachments(file.url, prefix: "file") {
                        out.filePaths = [copy.path]
                    }
                    out.fileNames = [name]
                    out.fileSizes = [size]
                } catch {
                    out.fileNames = [name]
                    out.fileSizes = [size]
                    LamoLogger.ui.error("Failed to extract PDF text: \(error)")
                }
            } else {
                let pageImages = FileContentExtractor.extractPDFImages(from: file.url)
                out.imagePaths = saveImages(pageImages)
                out.fileNames = [name]
                out.fileSizes = [size]
                out.textParts = [
                    String(localized: "[Scanned PDF: \(name) — \(pageImages.count) pages sent as images]")
                ]
            }
        } else {
            do {
                let extracted = try await FileContentExtractor.extract(from: file.url)
                out.textParts = [extracted]
                if let copy = copyToAttachments(file.url, prefix: "file") {
                    out.filePaths = [copy.path]
                }
                out.fileNames = [name]
                out.fileSizes = [size]
            } catch {
                out.textParts = [String(localized: "[Error reading file \(name): \(error.localizedDescription)]")]
                out.fileNames = [name]
                out.fileSizes = [size]
                LamoLogger.ui.error("Failed to extract file content: \(error)")
            }
        }
        return out
    }

    private static func copyToAttachments(_ source: URL, prefix: String) -> URL? {
        let filename = "\(prefix)_\(UUID().uuidString).\(source.pathExtension)"
        let destination = attachmentsDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            LamoLogger.ui.error("Failed to copy attachment to app storage: \(error)")
            return nil
        }
    }

    // MARK: - Image Saving

    static func saveImages(_ images: [UIImage]) -> [String] {
        var paths: [String] = []
        paths.reserveCapacity(images.count)
        for image in images {
            let resized = image.resizedForModel(maxDimension: 1024)
            guard let data = resized.jpegData(compressionQuality: 0.8) else { continue }
            let url = attachmentsDirectory.appendingPathComponent("img_\(UUID().uuidString).jpg")
            do {
                try data.write(to: url)
                paths.append(url.path)
            } catch {
                LamoLogger.ui.error("Failed to save image: \(error)")
            }
        }
        return paths
    }
}
