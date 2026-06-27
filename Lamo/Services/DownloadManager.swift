import Foundation
import Combine
import SwiftUI

/// Manages downloading LiteRT-LM models from HuggingFace.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [String: DownloadState] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]
    private let session: URLSession

    struct DownloadState {
        var progress: Double = 0
        var bytesWritten: Int64 = 0
        var totalBytes: Int64 = 0
        var isDownloading: Bool = false
        var error: String? = nil
        var isComplete: Bool = false

        var progressPercentage: Int {
            guard totalBytes > 0 else { return 0 }
            return Int(bytesWritten * 100 / totalBytes)
        }

        var downloadedSizeString: String {
            ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        }

        var totalSizeString: String {
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        session = URLSession(configuration: config)
    }

    func download(model: PresetModel) {
        guard let url = model.downloadURL else { return }
        guard activeDownloads[model.filename]?.isDownloading != true else { return }

        // Create models directory
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destination = modelsDir.appendingPathComponent(model.filename)

        activeDownloads[model.filename] = DownloadState(isDownloading: true)

        let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            Task { @MainActor in
                guard let self else { return }

                if let error = error {
                    self.activeDownloads[model.filename]?.error = error.localizedDescription
                    self.activeDownloads[model.filename]?.isDownloading = false
                    return
                }

                guard let tempURL = tempURL else {
                    self.activeDownloads[model.filename]?.error = "Download failed: no data"
                    self.activeDownloads[model.filename]?.isDownloading = false
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    self.activeDownloads[model.filename]?.isComplete = true
                    self.activeDownloads[model.filename]?.isDownloading = false
                    self.activeDownloads[model.filename]?.progress = 1.0
                } catch {
                    self.activeDownloads[model.filename]?.error = error.localizedDescription
                    self.activeDownloads[model.filename]?.isDownloading = false
                }
            }
        }

        // Track progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.activeDownloads[model.filename]?.progress = progress.fractionCompleted
                self?.activeDownloads[model.filename]?.bytesWritten = progress.completedUnitCount
                self?.activeDownloads[model.filename]?.totalBytes = progress.totalUnitCount
            }
        }

        observations[model.filename] = observation
        tasks[model.filename] = task
        task.resume()
    }

    func cancelDownload(model: PresetModel) {
        tasks[model.filename]?.cancel()
        activeDownloads[model.filename]?.isDownloading = false
        activeDownloads[model.filename]?.error = nil
        observations.removeValue(forKey: model.filename)
        tasks.removeValue(forKey: model.filename)
    }

    func deleteModel(_ model: PresetModel) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent("models").appendingPathComponent(model.filename)
        try? FileManager.default.removeItem(at: fileURL)
        activeDownloads.removeValue(forKey: model.filename)
    }
}
