import os
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Stateless attachment processing — resizes images, extracts file content, copies to the shared attachments directory.
enum AttachmentProcessor {

    // MARK: - Attachments Directory

    /// Shared directory for all attachment files (images, audio, documents).
    static let attachmentsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Public API

    /// Process attached images and files — resize images, extract file content, copy to attachments dir.
    static func process(
        images: [UIImage],
        files: [PendingFile]
    ) async -> (imagePaths: [String], filePaths: [String], fileNames: [String], fileSizes: [String], extractedText: String) {
        var imagePaths = saveImagesToTmp(images)
        var filePaths: [String] = []
        var fileNames: [String] = []
        var fileSizes: [String] = []
        var fileTextParts: [String] = []

        for file in files {
            let accessing = file.url.startAccessingSecurityScopedResource()
            defer { if accessing { file.url.stopAccessingSecurityScopedResource() } }

            if file.isImage {
                if let data = try? Data(contentsOf: file.url),
                   let image = UIImage(data: data) {
                    let paths = saveImagesToTmp([image])
                    imagePaths.append(contentsOf: paths)
                }
            } else if file.isAudio {
                let tmpURL = Self.attachmentsDirectory
                    .appendingPathComponent("audio_\(UUID().uuidString).\(file.url.pathExtension)")
                do {
                    try FileManager.default.copyItem(at: file.url, to: tmpURL)
                    filePaths.append(tmpURL.path)
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                    fileTextParts.append("[Audio file: \(file.name)]")
                } catch {
                    LamoLogger.ui.error("Failed to copy audio file: \(error)")
                }
            } else if file.type.conforms(to: .pdf) {
                if FileContentExtractor.pdfHasTextLayer(file.url) {
                    do {
                        let extracted = try await FileContentExtractor.extract(from: file.url)
                        fileTextParts.append(extracted)
                        let tmpURL = Self.attachmentsDirectory
                            .appendingPathComponent("file_\(UUID().uuidString).pdf")
                        try? FileManager.default.copyItem(at: file.url, to: tmpURL)
                        filePaths.append(tmpURL.path)
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                    } catch {
                        fileNames.append(file.name)
                        fileSizes.append(file.formattedSize)
                        LamoLogger.ui.error("Failed to extract PDF text: \(error)")
                    }
                } else {
                    // Scanned PDF — render pages as images for the multimodal model
                    let pageImages = FileContentExtractor.extractPDFImages(from: file.url)
                    let tmpPaths = saveImagesToTmp(pageImages)
                    imagePaths.append(contentsOf: tmpPaths)
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                    fileTextParts.append("[Scanned PDF: \(file.name) — \(pageImages.count) pages sent as images]")
                }
            } else {
                do {
                    let extracted = try await FileContentExtractor.extract(from: file.url)
                    fileTextParts.append(extracted)
                    let tmpURL = Self.attachmentsDirectory
                        .appendingPathComponent("file_\(UUID().uuidString).\(file.url.pathExtension)")
                    try? FileManager.default.copyItem(at: file.url, to: tmpURL)
                    filePaths.append(tmpURL.path)
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                } catch {
                    fileTextParts.append("[Error reading file \(file.name): \(error.localizedDescription)]")
                    fileNames.append(file.name)
                    fileSizes.append(file.formattedSize)
                    LamoLogger.ui.error("Failed to extract file content: \(error)")
                }
            }
        }

        return (imagePaths, filePaths, fileNames, fileSizes, fileTextParts.joined(separator: "\n\n"))
    }

    // MARK: - Image Saving

    /// Save UIImages to Documents/Attachments as JPEG (resized to max 1024px), return file paths.
    /// Stored in Documents so they persist until the conversation is explicitly deleted.
    static func saveImagesToTmp(_ images: [UIImage]) -> [String] {
        let attachmentsDir = Self.attachmentsDirectory
        var paths: [String] = []
        for image in images {
            let resized = image.resizedForModel(maxDimension: 1024)
            guard let data = resized.jpegData(compressionQuality: 0.8) else { continue }
            let filename = "img_\(UUID().uuidString).jpg"
            let url = attachmentsDir.appendingPathComponent(filename)
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
