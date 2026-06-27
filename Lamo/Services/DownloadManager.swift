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
    private var resumeData: [String: Data] = [:]
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

        // Check if already downloaded
        if model.isDownloaded {
            activeDownloads[model.filename] = DownloadState(progress: 1.0, isComplete: true)
            return
        }

        // Create models directory
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destination = modelsDir.appendingPathComponent(model.filename)

        activeDownloads[model.filename] = DownloadState(isDownloading: true)

        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: model.filename) {
            // Resume from saved data
            task = session.downloadTask(withResumeData: data) { [weak self] tempURL, response, error in
                self?.handleDownloadCompletion(model: model, tempURL: tempURL, response: response, error: error)
            }
        } else {
            // Fresh download
            task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
                self?.handleDownloadCompletion(model: model, tempURL: tempURL, response: response, error: error)
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
        // Save resume data before cancelling
        if let task = tasks[model.filename] {
            let semaphore = DispatchSemaphore(value: 0)
            var savedData: Data?
            task.cancel { data in
                savedData = data
                semaphore.signal()
            }
            semaphore.wait()
            if let data = savedData {
                resumeData[model.filename] = data
            }
        }
        tasks[model.filename]?.cancel()
        activeDownloads[model.filename]?.isDownloading = false
        observations.removeValue(forKey: model.filename)
        tasks.removeValue(forKey: model.filename)
    }

    func deleteModel(_ model: PresetModel) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent("models").appendingPathComponent(model.filename)
        try? FileManager.default.removeItem(at: fileURL)
        activeDownloads.removeValue(forKey: model.filename)

        // If this was the active model, invalidate engine so it reloads
        // litertLMModelPath stores just the filename, compare with model.filename
        if ProviderManager.shared.litertLMModelPath == model.filename {
            ProviderManager.shared.litertLMModelPath = nil
            ProviderManager.shared.invalidateEngine()
        }
    }

    private func handleDownloadCompletion(
        model: PresetModel,
        tempURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
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

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent("models").appendingPathComponent(model.filename)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                self.activeDownloads[model.filename]?.isComplete = true
                self.activeDownloads[model.filename]?.isDownloading = false
                self.activeDownloads[model.filename]?.progress = 1.0

                // Notify ProviderManager to reload engine with the new model
                ProviderManager.shared.reloadEngine()
            } catch {
                self.activeDownloads[model.filename]?.error = error.localizedDescription
                self.activeDownloads[model.filename]?.isDownloading = false
            }
        }
    }
}
