import os
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Stateless attachment processing — resizes images, extracts file content,
/// copies to the shared attachments directory.
///
/// All heavy work (image decode/resize/encode, PDF render, archive parsing)
/// runs in a detached task: on a large attachment this used to block the main
/// actor for seconds while the chat UI was frozen.
nonisolated enum AttachmentProcessor {

    // MARK: - Attachments Directory

    /// Shared directory for all attachment files (images, audio, documents).
    static let attachmentsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Accumulator for one file's contribution to the outgoing message.
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

    /// `UIImage` is not `Sendable`; it is only decoded/encoded here and never
    /// mutated by the caller while the task runs.
    private struct ImageBox: @unchecked Sendable {
        let images: [UIImage]
        init(_ images: [UIImage]) { self.images = images }
    }

    // MARK: - Public API

    /// Process attached images and files — resize images, extract file content,
    /// copy to attachments dir. Runs off the main actor.
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

    /// Body of one loop iteration. Kept in its own function so the `defer`
    /// releases the security-scoped URL per iteration — a `defer` inside `for`
    /// would keep every URL open until the whole batch finished.
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
            out.textParts = [String(localized: "[Audio file: \(name)]")]
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
                // Scanned PDF — render pages as images for the multimodal model.
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

    /// Copy a processed file into the shared attachments directory.
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

    /// Save UIImages as JPEG (resized to max 1024px) and return file paths.
    /// Stored in Documents so they persist until the conversation is deleted.
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
