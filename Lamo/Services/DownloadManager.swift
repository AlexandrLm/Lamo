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
    private let backgroundSessionID = "com.lamo.download"

    struct DownloadState {
        var progress: Double = 0
        var bytesWritten: Int64 = 0
        var totalBytes: Int64 = 0
        var isDownloading: Bool = false
        var error: String? = nil
        var isComplete: Bool = false
        var retryCount: Int = 0
        var lastError: String? = nil

        var progressPercentage: Int {
            guard totalBytes > 0 else { return Int(progress * 100) }
            return Int(progress * 100)
        }

        var downloadedSizeString: String {
            ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        }

        var totalSizeString: String {
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
    }

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionID)
        config.allowsCellularAccess = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: DownloadSessionDelegate.shared, delegateQueue: nil)
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

        activeDownloads[model.filename] = DownloadState(isDownloading: true)

        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: model.filename) {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }

        // Store metadata for delegate
        DownloadSessionDelegate.shared.pendingModels[model.filename] = model

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

        if ProviderManager.shared.litertLMModelPath == model.filename {
            ProviderManager.shared.litertLMModelPath = nil
            ProviderManager.shared.invalidateEngine()
        }
    }

    func handleCompletion(filename: String, tempURL: URL?, error: Error?) {
        Task { @MainActor in
            // Prevent double-handling (race condition between didFinishDownloadingTo and didCompleteWithError)
            guard self.activeDownloads[filename]?.isComplete != true else { return }

            if let error = error {
                self.activeDownloads[filename]?.lastError = error.localizedDescription
                self.activeDownloads[filename]?.error = error.localizedDescription
                self.activeDownloads[filename]?.isDownloading = false

                // Auto-retry up to 3 times for network errors
                if let urlError = error as? URLError,
                   [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code),
                   let retryCount = self.activeDownloads[filename]?.retryCount, retryCount < 3 {
                    self.activeDownloads[filename]?.retryCount = retryCount + 1
                    self.activeDownloads[filename]?.error = "Retrying... (attempt \(retryCount + 1)/3)"
                    self.activeDownloads[filename]?.isDownloading = true
                    // Wait before retry
                    try? await Task.sleep(for: .seconds(2))
                    if let model = DownloadSessionDelegate.shared.pendingModels[filename] {
                        self.download(model: model)
                    }
                }
                return
            }

            guard let tempURL = tempURL else {
                self.activeDownloads[filename]?.error = "Download failed: no data"
                self.activeDownloads[filename]?.isDownloading = false
                return
            }

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent("models").appendingPathComponent(filename)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                self.activeDownloads[filename]?.isComplete = true
                self.activeDownloads[filename]?.isDownloading = false
                self.activeDownloads[filename]?.progress = 1.0
                self.activeDownloads[filename]?.retryCount = 0
                self.activeDownloads[filename]?.lastError = nil
                self.observations.removeValue(forKey: filename)
                self.tasks.removeValue(forKey: filename)

                ProviderManager.shared.reloadEngine()
            } catch {
                self.activeDownloads[filename]?.error = error.localizedDescription
                self.activeDownloads[filename]?.isDownloading = false
            }
        }
    }
}

// MARK: - Background Session Delegate

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadSessionDelegate()
    var pendingModels: [String: PresetModel] = [:]

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let filename = downloadTask.originalRequest?.url?.lastPathComponent else { return }
        // Copy temp file immediately — iOS deletes it after this method returns
        let tempDir = FileManager.default.temporaryDirectory
        let backupURL = tempDir.appendingPathComponent("lamo_dl_\(filename)")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: location, to: backupURL)
        Task { @MainActor in
            DownloadManager.shared.handleCompletion(filename: filename, tempURL: backupURL, error: nil)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let filename = task.originalRequest?.url?.lastPathComponent else { return }
        if let error = error as? URLError, error.code == .cancelled { return }
        // Only report errors — success is handled by didFinishDownloadingTo
        if let error = error {
            Task { @MainActor in
                DownloadManager.shared.handleCompletion(filename: filename, tempURL: nil, error: error)
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .backgroundDownloadComplete, object: nil)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let backgroundDownloadComplete = Notification.Name("backgroundDownloadComplete")
}
